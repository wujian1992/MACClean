import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppsStore: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var selectedIDs: Set<InstalledApp.ID> = []
    @Published var isScanning = false
    @Published var status = "等待扫描"
    @Published var lastError: String?
    @Published var searchText = ""
    @Published var workMode: WorkMode = .idle
    @Published var activeTitle = "等待开始"
    @Published var activeDetail = "点击扫描 App 后会统计应用和残留文件"
    @Published var progress = 0.0
    @Published var recentActivity: [ActivityLine] = []

    var filteredApps: [InstalledApp] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return apps
        }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    var selectedApps: [InstalledApp] {
        apps.filter { selectedIDs.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selectedApps.reduce(0) { $0 + $1.totalSize }
    }

    func scan() {
        isScanning = true
        status = "正在扫描本机 App 和残留数据"
        workMode = .scanning
        activeTitle = "准备扫描"
        activeDetail = "正在读取 Applications 目录"
        progress = 0.02
        recentActivity = []
        lastError = nil
        apps = []
        selectedIDs = []

        Task.detached(priority: .userInitiated) {
            let scanned = AppScanner.scanInstalledApps { title, detail, progress in
                Task { @MainActor in
                    self.activeTitle = title
                    self.activeDetail = detail
                    self.progress = progress
                    self.pushActivity(title: title, detail: detail)
                }
            }
            await MainActor.run {
                self.apps = scanned.sorted { $0.totalSize > $1.totalSize }
                self.status = "扫描完成"
                self.workMode = .completed
                self.activeTitle = "App 扫描完成"
                self.activeDetail = "发现 \(scanned.count) 个 App，已统计可匹配残留"
                self.progress = 1
                self.isScanning = false
            }
        }
    }

    func toggle(_ app: InstalledApp) {
        if selectedIDs.contains(app.id) {
            selectedIDs.remove(app.id)
        } else {
            selectedIDs.insert(app.id)
        }
    }

    func uninstallSelected() {
        let targets = selectedApps
        guard !targets.isEmpty else { return }

        isScanning = true
        status = "正在移动 App 和残留到废纸篓"
        workMode = .uninstalling
        activeTitle = "准备卸载"
        activeDetail = "将所选 App 和残留移动到废纸篓"
        progress = 0.02
        recentActivity = []
        lastError = nil

        Task.detached(priority: .userInitiated) {
            var failures: [String] = []
            let total = max(targets.count, 1)

            for (index, app) in targets.enumerated() {
                await MainActor.run {
                    self.activeTitle = "正在卸载 \(app.name)"
                    self.activeDetail = "\(app.residues.count) 个残留项目 · \(app.totalSize.formattedBytes)"
                    self.progress = Double(index) / Double(total)
                    self.pushActivity(title: app.name, detail: app.bundleIdentifier)
                }
                let urls = [app.path] + app.residues.map(\.path)
                for url in urls {
                    do {
                        try TrashService.trashContentsOrItem(url, preserveContainer: false)
                    } catch {
                        failures.append("\(url.displayPath): \(error.localizedDescription)")
                    }
                }
            }

            await MainActor.run {
                self.activeTitle = "正在刷新 App 列表"
                self.activeDetail = "重新扫描剩余应用"
                self.progress = 0.96
            }
            let rescanned = AppScanner.scanInstalledApps()
            await MainActor.run {
                self.apps = rescanned.sorted { $0.totalSize > $1.totalSize }
                self.selectedIDs = []
                self.status = failures.isEmpty ? "卸载完成" : "部分项目未能卸载"
                self.lastError = failures.isEmpty ? nil : failures.prefix(4).joined(separator: "\n")
                self.workMode = .completed
                self.activeTitle = failures.isEmpty ? "卸载完成" : "卸载完成，有项目被跳过"
                self.activeDetail = failures.isEmpty ? "所选 App 和残留已移动到废纸篓" : "无权限或正在使用的项目已保留"
                self.progress = 1
                self.isScanning = false
            }
        }
    }

    private func pushActivity(title: String, detail: String) {
        let line = ActivityLine(title: title, detail: detail)
        recentActivity.insert(line, at: 0)
        if recentActivity.count > 6 {
            recentActivity.removeLast(recentActivity.count - 6)
        }
    }
}

enum AppScanner {
    typealias ProgressHandler = (_ title: String, _ detail: String, _ progress: Double) -> Void

    static func scanInstalledApps(progress progressHandler: ProgressHandler? = nil) -> [InstalledApp] {
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "\(NSHomeDirectory())/Applications")
        ]
        var seen = Set<String>()
        var appURLs: [URL] = []

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            progressHandler?("读取 App 目录", root.displayPath, 0.04)
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else {
                continue
            }

            for case let url as URL in enumerator where url.pathExtension == "app" {
                let appPath = url.standardizedFileURL.path
                guard !seen.contains(appPath) else { continue }
                seen.insert(appPath)
                enumerator.skipDescendants()
                appURLs.append(url)
            }
        }

        var apps: [InstalledApp] = []
        let total = max(appURLs.count, 1)

        for (index, url) in appURLs.enumerated() {
            guard let bundle = Bundle(url: url) else { continue }
            let name = displayName(for: bundle, fallback: url.deletingPathExtension().lastPathComponent)
            let bundleID = bundle.bundleIdentifier ?? url.deletingPathExtension().lastPathComponent
            progressHandler?("扫描 \(name)", bundleID, 0.10 + 0.84 * (Double(index) / Double(total)))

            let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                ?? "未知"
            let appSize = FileSizeScanner.directorySize(at: url)
            let residues = findResidues(bundleID: bundleID, appName: name)

            apps.append(
                InstalledApp(
                    name: name,
                    path: url,
                    bundleIdentifier: bundleID,
                    version: version,
                    size: appSize,
                    residues: residues
                )
            )
        }

        progressHandler?("整理 App 结果", "按总体占用排序", 0.98)
        return apps
    }

    private static func displayName(for bundle: Bundle, fallback: String) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? fallback
    }

    private static func findResidues(bundleID: String, appName: String) -> [AppResidue] {
        let home = NSHomeDirectory()
        let cleanName = appName.replacingOccurrences(of: ".app", with: "")
        let caskName = cleanName.lowercased().replacingOccurrences(of: " ", with: "-")
        let exactPaths = [
            ("\(home)/Library/Application Support/\(bundleID)", CleanupRisk.review, "按 bundle id 匹配的用户级 App 支持数据"),
            ("\(home)/Library/Application Support/\(cleanName)", CleanupRisk.review, "按 App 名称匹配的用户级 App 支持数据"),
            ("\(home)/Library/Caches/\(bundleID)", CleanupRisk.safe, "按 bundle id 匹配的用户级缓存"),
            ("\(home)/Library/Caches/\(cleanName)", CleanupRisk.safe, "按 App 名称匹配的用户级缓存"),
            ("\(home)/Library/Preferences/\(bundleID).plist", CleanupRisk.safe, "偏好设置文件"),
            ("\(home)/Library/HTTPStorages/\(bundleID)", CleanupRisk.safe, "HTTP 缓存和存储"),
            ("\(home)/Library/Saved Application State/\(bundleID).savedState", CleanupRisk.safe, "保存的窗口和会话状态"),
            ("\(home)/Library/WebKit/\(bundleID)", CleanupRisk.review, "WebKit 数据，可能包含登录态或离线数据"),
            ("\(home)/Library/Logs/\(bundleID)", CleanupRisk.safe, "用户级日志"),
            ("\(home)/Library/Containers/\(bundleID)", CleanupRisk.review, "沙盒容器，可能包含个人数据"),
            ("\(home)/Library/Group Containers/\(bundleID)", CleanupRisk.review, "共享容器，可能影响多个相关 App"),
            ("\(home)/Library/LaunchAgents/\(bundleID).plist", CleanupRisk.review, "用户启动项"),
            ("/Library/Application Support/\(bundleID)", CleanupRisk.admin, "系统级 App 支持数据，通常需要管理员权限"),
            ("/Library/Application Support/\(cleanName)", CleanupRisk.admin, "系统级 App 支持数据，通常需要管理员权限"),
            ("/Library/Caches/\(bundleID)", CleanupRisk.admin, "系统级缓存，通常需要管理员权限"),
            ("/Library/Preferences/\(bundleID).plist", CleanupRisk.admin, "系统级偏好设置，通常需要管理员权限"),
            ("/Library/LaunchAgents/\(bundleID).plist", CleanupRisk.admin, "系统级 LaunchAgent"),
            ("/Library/LaunchDaemons/\(bundleID).plist", CleanupRisk.admin, "系统级 LaunchDaemon"),
            ("/Library/PrivilegedHelperTools/\(bundleID)", CleanupRisk.admin, "特权 helper 工具"),
            ("/Library/Receipts/\(bundleID).bom", CleanupRisk.admin, "安装收据"),
            ("/Library/Receipts/\(bundleID).plist", CleanupRisk.admin, "安装收据"),
            ("/opt/homebrew/Caskroom/\(caskName)", CleanupRisk.review, "Homebrew Cask 安装缓存"),
            ("/usr/local/Caskroom/\(caskName)", CleanupRisk.review, "Homebrew Cask 安装缓存")
        ]

        var residues: [AppResidue] = []
        var seen = Set<String>()

        func add(_ path: String, title: String, risk: CleanupRisk, detail: String) {
            let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            let key = url.standardizedFileURL.path
            guard !seen.contains(key), FileManager.default.fileExists(atPath: key) else { return }
            seen.insert(key)
            let size = FileSizeScanner.directorySize(at: url)
            residues.append(AppResidue(title: title, path: url, size: size, risk: risk, detail: detail))
        }

        for item in exactPaths {
            add(item.0, title: URL(fileURLWithPath: item.0).lastPathComponent, risk: item.1, detail: item.2)
        }

        let wildcardRoots = [
            ("\(home)/Library/Application Support", CleanupRisk.review, "名称近似匹配的用户级支持数据"),
            ("\(home)/Library/Caches", CleanupRisk.safe, "名称近似匹配的用户级缓存"),
            ("\(home)/Library/Preferences", CleanupRisk.safe, "名称近似匹配的偏好设置"),
            ("\(home)/Library/Logs", CleanupRisk.safe, "名称近似匹配的日志"),
            ("\(home)/Library/LaunchAgents", CleanupRisk.review, "名称近似匹配的用户启动项"),
            ("\(home)/Library/Containers", CleanupRisk.review, "名称近似匹配的沙盒容器"),
            ("\(home)/Library/Group Containers", CleanupRisk.review, "名称近似匹配的共享容器"),
            ("/Library/Application Support", CleanupRisk.admin, "名称近似匹配的系统级支持数据"),
            ("/Library/Caches", CleanupRisk.admin, "名称近似匹配的系统级缓存"),
            ("/Library/Preferences", CleanupRisk.admin, "名称近似匹配的系统级偏好设置"),
            ("/Library/LaunchAgents", CleanupRisk.admin, "名称近似匹配的系统级 LaunchAgent"),
            ("/Library/LaunchDaemons", CleanupRisk.admin, "名称近似匹配的系统级 LaunchDaemon"),
            ("/Library/PrivilegedHelperTools", CleanupRisk.admin, "名称近似匹配的特权 helper"),
            ("/Library/Receipts", CleanupRisk.admin, "名称近似匹配的安装收据"),
            ("/opt/homebrew/Caskroom", CleanupRisk.review, "名称近似匹配的 Homebrew Cask 数据"),
            ("/usr/local/Caskroom", CleanupRisk.review, "名称近似匹配的 Homebrew Cask 数据")
        ]
        let bundleParts = bundleID.split(separator: ".").map(String.init)
        let tokens = Set(([bundleID, cleanName, caskName] + bundleParts)
            .filter { $0.count >= 3 }
            .map { $0.lowercased() })

        for root in wildcardRoots {
            guard let children = try? FileManager.default.contentsOfDirectory(atPath: root.0) else { continue }
            for child in children {
                let lower = child.lowercased()
                guard tokens.contains(where: { lower.contains($0) }) else { continue }
                add("\(root.0)/\(child)", title: child, risk: root.1, detail: root.2)
            }
        }

        return residues.sorted { $0.size > $1.size }
    }
}
