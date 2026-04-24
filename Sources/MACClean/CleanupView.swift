import SwiftUI

struct CleanupView: View {
    @EnvironmentObject private var store: CleanupStore
    @State private var showingConfirm = false
    @State private var expandedIDs: Set<String> = []

    private var expandableIDs: Set<String> {
        Set(store.candidates
            .map(\.asTreeNode)
            .filter(\.isDirectory)
            .map(\.selectionKey))
    }

    var body: some View {
        VStack(spacing: 22) {
            HeaderView(
                title: "专家模式扫描",
                subtitle: "深度扫描缓存、日志、App 数据、容器、浏览器、开发环境、旧安装包和大文件，所有结果需选择后才会清理。",
                actionTitle: store.isScanning ? "深度扫描中" : "开始专家扫描",
                actionIcon: "magnifyingglass",
                isBusy: store.isScanning,
                action: store.scan
            )

            HStack(spacing: 14) {
                MetricTile(title: "可检查空间", value: store.summary.totalBytes.formattedBytes, icon: "externaldrive", tint: .teal)
                MetricTile(title: "发现项目", value: "\(store.summary.itemCount)", icon: "list.bullet.rectangle", tint: .blue)
                MetricTile(title: "已选择", value: store.selectedBytes.formattedBytes, icon: "checkmark.circle", tint: .green)
            }

            WorkStatusPanel(
                mode: store.workMode,
                title: store.activeTitle,
                detail: store.activeDetail,
                progress: store.progress,
                activity: store.recentActivity,
                tint: .teal
            )

            if let error = store.lastError {
                ErrorBanner(message: error)
            }

            VStack(spacing: 0) {
                HStack {
                    Text(store.status)
                        .font(.headline)
                    Spacer()
                    Button(expandedIDs.isEmpty ? "展开顶层" : "收起全部") {
                        if expandedIDs.count >= expandableIDs.count {
                            expandedIDs.removeAll()
                        } else {
                            expandedIDs = expandableIDs
                        }
                    }
                    .disabled(store.candidates.isEmpty || store.isScanning)

                    Button("取消选择") {
                        store.selectedIDs.removeAll()
                    }
                    .disabled(store.selectedIDs.isEmpty || store.isScanning)

                    Button {
                        showingConfirm = true
                    } label: {
                        Label("清理所选", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .disabled(store.selectedIDs.isEmpty || store.isScanning)
                }
                .padding(16)

                Divider()

                if store.candidates.isEmpty {
                    EmptyStateView(title: "还没有扫描结果", subtitle: "点击开始扫描后会列出可清理项目和需要确认的大文件。", icon: "sparkle.magnifyingglass")
                } else {
                    List(store.candidates) { candidate in
                        CleanupTreeRow(
                            node: candidate.asTreeNode,
                            level: 0,
                            expandedIDs: $expandedIDs,
                            isNodeSelected: { store.selectedIDs.contains($0.selectionKey) },
                            toggleNode: { store.toggle($0) },
                            childrenForNode: { store.children(for: $0) },
                            isLoadingNode: { store.isLoadingChildren(for: $0) },
                            loadChildren: { store.loadChildrenIfNeeded(for: $0) }
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }
                    .listStyle(.plain)
                }
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08)))
        }
        .padding(28)
        .confirmationDialog(
            "确认清理所选项目？",
            isPresented: $showingConfirm,
            titleVisibility: .visible
        ) {
            Button("移动到废纸篓", role: .destructive) {
                store.cleanSelected()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将移动 \(store.selectedCandidates.count) 个项目，约 \(store.selectedBytes.formattedBytes)。")
        }
    }
}

struct CleanupTreeRow: View {
    let node: CleanupTreeNode
    let level: Int
    @Binding var expandedIDs: Set<String>
    let isNodeSelected: (CleanupTreeNode) -> Bool
    let toggleNode: (CleanupTreeNode) -> Void
    let childrenForNode: (CleanupTreeNode) -> [CleanupTreeNode]
    let isLoadingNode: (CleanupTreeNode) -> Bool
    let loadChildren: (CleanupTreeNode) -> Void

    private var isExpanded: Bool {
        expandedIDs.contains(node.selectionKey)
    }

    private var children: [CleanupTreeNode] {
        childrenForNode(node)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Button {
                    toggleNode(node)
                } label: {
                    Image(systemName: isNodeSelected(node) ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isNodeSelected(node) ? .teal : .secondary)
                }
                .buttonStyle(.plain)

                Button {
                    if isExpanded {
                        expandedIDs.remove(node.selectionKey)
                    } else {
                        expandedIDs.insert(node.selectionKey)
                        loadChildren(node)
                    }
                } label: {
                    if isLoadingNode(node) {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: node.isDirectory ? "chevron.right" : "circle.fill")
                            .font(.system(size: node.isDirectory ? 12 : 5, weight: .bold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 16, height: 16)
                            .foregroundStyle(node.isDirectory ? Color.secondary : Color.secondary.opacity(0.35))
                    }
                }
                .buttonStyle(.plain)
                .disabled(!node.isDirectory)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(node.title)
                            .font(.system(size: level == 0 ? 14 : 13, weight: level == 0 ? .semibold : .medium))
                            .lineLimit(1)
                        RiskBadge(risk: node.risk)
                        if node.isDirectory {
                            Text(children.isEmpty ? "目录" : "\(children.count) 项")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    }
                    Text(node.path.displayPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(node.detail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                Text(node.size.formattedBytes)
                    .font(.system(size: level == 0 ? 14 : 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .padding(12)
            .padding(.leading, CGFloat(level) * 22)
            .background(isNodeSelected(node) ? Color.teal.opacity(0.08) : Color.primary.opacity(level == 0 ? 0.035 : 0.022))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if isExpanded {
                if isLoadingNode(node) && children.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在读取子文件夹...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, CGFloat(level + 1) * 22 + 42)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(children) { child in
                    CleanupTreeRow(
                        node: child,
                        level: level + 1,
                        expandedIDs: $expandedIDs,
                        isNodeSelected: isNodeSelected,
                        toggleNode: toggleNode,
                        childrenForNode: childrenForNode,
                        isLoadingNode: isLoadingNode,
                        loadChildren: loadChildren
                    )
                }
            }
        }
    }
}
