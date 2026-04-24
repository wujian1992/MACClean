import SwiftUI

struct AppsView: View {
    @EnvironmentObject private var store: AppsStore
    @State private var showingConfirm = false
    @State private var expandedIDs: Set<InstalledApp.ID> = []

    var body: some View {
        VStack(spacing: 22) {
            HeaderView(
                title: "专家 App 卸载",
                subtitle: "深度扫描应用本体、用户级残留、系统级残留、启动项、Receipts、PrivilegedHelper 和 Homebrew Cask 数据。",
                actionTitle: store.isScanning ? "深度扫描中" : "专家扫描 App",
                actionIcon: "app.badge",
                isBusy: store.isScanning,
                action: store.scan
            )

            HStack(spacing: 14) {
                MetricTile(title: "已发现 App", value: "\(store.apps.count)", icon: "app.dashed", tint: .teal)
                MetricTile(title: "所选可释放", value: store.selectedBytes.formattedBytes, icon: "externaldrive.badge.minus", tint: .green)
                MetricTile(title: "残留文件", value: "\(store.apps.reduce(0) { $0 + $1.residues.count })", icon: "doc.badge.gearshape", tint: .orange)
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
                HStack(spacing: 12) {
                    Text(store.status)
                        .font(.headline)
                    Spacer()
                    TextField("搜索 App 或 bundle id", text: $store.searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                        .animation(.snappy(duration: 0.22), value: store.searchText)
                    Button("取消选择") {
                        store.selectedIDs.removeAll()
                    }
                    .disabled(store.selectedIDs.isEmpty || store.isScanning)
                    Button {
                        showingConfirm = true
                    } label: {
                        Label("卸载所选", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .disabled(store.selectedIDs.isEmpty || store.isScanning)
                }
                .padding(16)

                if !store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SearchStatusPill(query: store.searchText, count: store.filteredApps.count)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Divider()

                if store.apps.isEmpty {
                    EmptyStateView(title: "还没有 App 扫描结果", subtitle: "点击扫描 App 后会列出应用体积和可能的残留数据。", icon: "app.badge")
                } else {
                    List(store.filteredApps) { app in
                        AppRow(
                            app: app,
                            isSelected: store.selectedIDs.contains(app.id),
                            isExpanded: expandedIDs.contains(app.id),
                            toggleSelected: { store.toggle(app) },
                            toggleExpanded: {
                                if expandedIDs.contains(app.id) {
                                    expandedIDs.remove(app.id)
                                } else {
                                    expandedIDs.insert(app.id)
                                }
                            }
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
            "确认卸载所选 App？",
            isPresented: $showingConfirm,
            titleVisibility: .visible
        ) {
            Button("移动到废纸篓", role: .destructive) {
                store.uninstallSelected()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将移动 \(store.selectedApps.count) 个 App 及匹配到的残留，约 \(store.selectedBytes.formattedBytes)。")
        }
    }
}

struct AppRow: View {
    let app: InstalledApp
    let isSelected: Bool
    let isExpanded: Bool
    let toggleSelected: () -> Void
    let toggleExpanded: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button(action: toggleSelected) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? .teal : .secondary)
                }
                .buttonStyle(.plain)

                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path.path))
                    .resizable()
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(app.name)
                            .font(.system(size: 14, weight: .semibold))
                        Text(app.version)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(app.bundleIdentifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(app.path.displayPath)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(app.totalSize.formattedBytes)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("App \(app.size.formattedBytes) · 残留 \(app.residues.reduce(0) { $0 + $1.size }.formattedBytes)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(action: toggleExpanded) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .buttonStyle(.plain)
                .disabled(app.residues.isEmpty)
            }

            if isExpanded {
                VStack(spacing: 6) {
                    if app.residues.isEmpty {
                        Text("未发现明显残留")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(app.residues) { residue in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(residue.title)
                                            .font(.caption.weight(.semibold))
                                        RiskBadge(risk: residue.risk)
                                    }
                                    Text(residue.path.displayPath)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Text(residue.size.formattedBytes)
                                    .font(.caption.weight(.bold))
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 5)
                        }
                    }
                }
                .padding(.leading, 66)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(isSelected ? Color.teal.opacity(0.08) : Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .animation(.snappy(duration: 0.22), value: isExpanded)
    }
}
