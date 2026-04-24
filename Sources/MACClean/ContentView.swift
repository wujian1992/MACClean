import SwiftUI

struct ContentView: View {
    @State private var section: AppSection = .cleanup

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(section: $section)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color(red: 0.06, green: 0.11, blue: 0.13).opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                switch section {
                case .cleanup:
                    CleanupView()
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                case .apps:
                    AppsView()
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
        }
        .animation(.snappy(duration: 0.28), value: section)
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case cleanup = "电脑扫描"
    case apps = "App 卸载"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cleanup:
            return "sparkle.magnifyingglass"
        case .apps:
            return "app.badge"
        }
    }
}

struct SidebarView: View {
    @Binding var section: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.teal.gradient)
                    Image(systemName: "wind")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text("MACClean")
                        .font(.title3.weight(.bold))
                    Text("本机清理工具")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 26)

            VStack(spacing: 8) {
                ForEach(AppSection.allCases) { item in
                    Button {
                        section = item
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 22)
                            Text(item.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .foregroundStyle(section == item ? .white : .primary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(section == item ? Color.teal : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Label("所有清理动作都会进入废纸篓", systemImage: "trash")
                Label("卸载前会显示 App 残留", systemImage: "doc.text.magnifyingglass")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 18)
        .frame(width: 238)
        .background(.regularMaterial)
    }
}

