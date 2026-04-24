import Foundation
import SwiftUI

@MainActor
final class CleanupStore: ObservableObject {
    @Published var candidates: [CleanupCandidate] = []
    @Published var selectedIDs: Set<String> = []
    @Published var isScanning = false
    @Published var status = "等待扫描"
    @Published var lastError: String?
    @Published var summary = ScanSummary()
    @Published var workMode: WorkMode = .idle
    @Published var activeTitle = "等待开始"
    @Published var activeDetail = "点击开始扫描后会逐项检查缓存、日志和大文件"
    @Published var progress = 0.0
    @Published var recentActivity: [ActivityLine] = []
    @Published var childCache: [String: [CleanupTreeNode]] = [:]
    @Published var loadingNodeIDs: Set<String> = []

    var selectedCandidates: [CleanupTreeNode] {
        let nodeMap = knownNodeMap()
        let selected = selectedIDs.compactMap { nodeMap[$0] }
        .sorted { $0.selectionKey.count < $1.selectionKey.count }

        var normalized: [CleanupTreeNode] = []
        for item in selected {
            let path = item.selectionKey
            let hasSelectedAncestor = normalized.contains { ancestor in
                path.hasPrefix(ancestor.selectionKey + "/")
            }
            if !hasSelectedAncestor {
                normalized.append(item)
            }
        }
        return normalized
    }

    var selectedBytes: Int64 {
        selectedCandidates.reduce(0) { $0 + $1.size }
    }

    func scan() {
        isScanning = true
        status = "专家模式正在深度扫描"
        workMode = .scanning
        activeTitle = "准备扫描"
        activeDetail = "正在建立缓存、日志、App 数据、旧文件和残留索引"
        progress = 0.02
        recentActivity = []
        lastError = nil
        candidates = []
        selectedIDs = []
        childCache = [:]
        loadingNodeIDs = []

        Task.detached(priority: .userInitiated) {
            let scanned = CleanupScanner.scan { title, detail, progress in
                Task { @MainActor in
                    self.activeTitle = title
                    self.activeDetail = detail
                    self.progress = progress
                    self.pushActivity(title: title, detail: detail)
                }
            }
            await MainActor.run {
                self.candidates = scanned.sorted { $0.size > $1.size }
                self.rebuildInitialChildCache(from: self.candidates)
                self.selectedIDs = Set(scanned.filter { $0.risk == .safe }.map(\.selectionKey))
                self.summary = ScanSummary(
                    totalBytes: scanned.reduce(0) { $0 + $1.size },
                    itemCount: scanned.count,
                    scannedAt: Date()
                )
                self.status = "扫描完成"
                self.workMode = .completed
                self.activeTitle = "扫描完成"
                self.activeDetail = "发现 \(scanned.count) 个可检查项目，总计 \(scanned.reduce(0) { $0 + $1.size }.formattedBytes)"
                self.progress = 1
                self.isScanning = false
            }
        }
    }

    func toggle(_ candidate: CleanupCandidate) {
        toggle(key: candidate.selectionKey)
    }

    func toggle(_ node: CleanupTreeNode) {
        toggle(key: node.selectionKey)
    }

    private func toggle(key: String) {
        if selectedIDs.contains(key) {
            selectedIDs.remove(key)
        } else {
            selectedIDs.insert(key)
        }
    }

    func cleanSelected() {
        let targets = selectedCandidates
        guard !targets.isEmpty else { return }

        isScanning = true
        status = "正在移动到废纸篓"
        workMode = .cleaning
        activeTitle = "准备清理"
        activeDetail = "将所选项目移动到废纸篓"
        progress = 0.02
        recentActivity = []
        lastError = nil

        Task.detached(priority: .userInitiated) {
            var failures: [String] = []
            let total = max(targets.count, 1)

            for (index, target) in targets.enumerated() {
                await MainActor.run {
                    self.activeTitle = "正在清理 \(target.title)"
                    self.activeDetail = target.path.displayPath
                    self.progress = Double(index) / Double(total)
                    self.pushActivity(title: target.title, detail: target.size.formattedBytes)
                }
                do {
                    try TrashService.trashContentsOrItem(target.path, preserveContainer: target.category != "大文件" && !target.children.isEmpty)
                } catch {
                    failures.append("\(target.path.displayPath): \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                self.activeTitle = "正在刷新扫描结果"
                self.activeDetail = "重新统计剩余项目"
                self.progress = 0.96
            }
            let rescanned = CleanupScanner.scan()
            await MainActor.run {
                self.candidates = rescanned.sorted { $0.size > $1.size }
                self.rebuildInitialChildCache(from: self.candidates)
                self.selectedIDs = Set(rescanned.filter { $0.risk == .safe }.map(\.selectionKey))
                self.summary = ScanSummary(
                    totalBytes: rescanned.reduce(0) { $0 + $1.size },
                    itemCount: rescanned.count,
                    scannedAt: Date()
                )
                self.status = failures.isEmpty ? "清理完成" : "部分项目未能清理"
                self.lastError = failures.isEmpty ? nil : failures.prefix(4).joined(separator: "\n")
                self.workMode = .completed
                self.activeTitle = failures.isEmpty ? "清理完成" : "清理完成，有项目被跳过"
                self.activeDetail = failures.isEmpty ? "所选项目已移动到废纸篓" : "无权限或正在使用的项目已保留"
                self.progress = 1
                self.isScanning = false
            }
        }
    }

    func children(for node: CleanupTreeNode) -> [CleanupTreeNode] {
        childCache[node.selectionKey] ?? node.children
    }

    func isLoadingChildren(for node: CleanupTreeNode) -> Bool {
        loadingNodeIDs.contains(node.selectionKey)
    }

    func loadChildrenIfNeeded(for node: CleanupTreeNode) {
        guard node.isDirectory,
              childCache[node.selectionKey] == nil,
              !loadingNodeIDs.contains(node.selectionKey) else {
            return
        }

        loadingNodeIDs.insert(node.selectionKey)
        let key = node.selectionKey
        let url = node.path
        let category = node.category
        let risk = node.risk
        let detail = node.detail

        Task.detached(priority: .userInitiated) {
            let children = FileSizeScanner.directoryTree(
                at: url,
                category: category,
                risk: risk,
                detail: detail,
                maxDepth: 1
            )

            await MainActor.run {
                self.childCache[key] = children
                self.loadingNodeIDs.remove(key)
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

    private func rebuildInitialChildCache(from candidates: [CleanupCandidate]) {
        var cache: [String: [CleanupTreeNode]] = [:]
        for candidate in candidates {
            cache[candidate.selectionKey] = candidate.children
        }
        childCache = cache
        loadingNodeIDs = []
    }

    private func knownNodeMap() -> [String: CleanupTreeNode] {
        var map: [String: CleanupTreeNode] = [:]
        for candidate in candidates {
            let root = candidate.asTreeNode
            map[root.selectionKey] = root
        }
        for nodes in childCache.values {
            for node in nodes {
                map[node.selectionKey] = node
            }
        }
        return map
    }
}

enum CleanupScanner {
    typealias ProgressHandler = (_ title: String, _ detail: String, _ progress: Double) -> Void

    static func scan(progress progressHandler: ProgressHandler? = nil) -> [CleanupCandidate] {
        var results: [CleanupCandidate] = []
        var seen = Set<String>()

        func add(_ candidate: CleanupCandidate) {
            let key = candidate.path.standardizedFileURL.path
            guard !seen.contains(key), FileManager.default.fileExists(atPath: key) else { return }
            seen.insert(key)
            results.append(candidate)
        }

        let specs = cleanupSpecs()
        let baseUnit = 0.22 / Double(max(specs.count, 1))

        for (index, spec) in specs.enumerated() {
            let url = URL(fileURLWithPath: NSString(string: spec.path).expandingTildeInPath)
            progressHandler?("专家扫描 \(spec.title)", url.displayPath, 0.04 + Double(index) * baseUnit)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let size = FileSizeScanner.directorySize(at: url)
            guard size > 0 else { continue }
            let children = FileSizeScanner.directoryTree(
                at: url,
                category: spec.category,
                risk: spec.risk,
                detail: spec.detail
            )

            add(
                CleanupCandidate(
                    category: spec.category,
                    title: spec.title,
                    path: url,
                    size: size,
                    risk: spec.risk,
                    detail: spec.detail,
                    children: children
                )
            )
        }

        let childSpecs = expertChildSpecs()
        let childSpan = 0.46 / Double(max(childSpecs.count, 1))
        for (index, spec) in childSpecs.enumerated() {
            addChildren(
                in: URL(fileURLWithPath: NSString(string: spec.path).expandingTildeInPath),
                category: spec.category,
                titlePrefix: spec.titlePrefix,
                safeRisk: spec.safeRisk,
                safeDetail: spec.safeDetail,
                protectedDetail: spec.protectedDetail,
                progressStart: 0.28 + Double(index) * childSpan,
                progressSpan: childSpan,
                progressHandler: progressHandler,
                add: add
            )
        }

        let largeRoots = [
            URL(fileURLWithPath: "\(NSHomeDirectory())/Downloads"),
            URL(fileURLWithPath: "\(NSHomeDirectory())/Desktop"),
            URL(fileURLWithPath: "\(NSHomeDirectory())/Documents"),
            URL(fileURLWithPath: "\(NSHomeDirectory())/Movies"),
            URL(fileURLWithPath: "\(NSHomeDirectory())/Pictures"),
            URL(fileURLWithPath: "\(NSHomeDirectory())/Public")
        ]
        for (index, root) in largeRoots.enumerated() {
            progressHandler?("专家扫描大文件", root.displayPath, 0.76 + Double(index) * 0.025)
            for item in FileSizeScanner.largeFiles(in: [root], minimumBytes: 200 * 1024 * 1024) {
                add(item)
            }
        }

        for (index, root) in largeRoots.prefix(4).enumerated() {
            progressHandler?("扫描旧安装包", root.displayPath, 0.91 + Double(index) * 0.016)
            for item in FileSizeScanner.oldArchiveFiles(in: [root], olderThanDays: 30, minimumBytes: 50 * 1024 * 1024) {
                add(item)
            }
        }

        progressHandler?("整理扫描结果", "按容量排序并生成清理建议", 0.98)
        return results
    }

    private static func addChildren(
        in directory: URL,
        category: String,
        titlePrefix: String,
        safeRisk: CleanupRisk,
        safeDetail: String,
        protectedDetail: String,
        progressStart: Double,
        progressSpan: Double,
        progressHandler: ProgressHandler?,
        add: (CleanupCandidate) -> Void
    ) {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isWritableKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let total = max(children.count, 1)
        for (index, child) in children.enumerated() {
            progressHandler?(
                "扫描 \(titlePrefix): \(child.lastPathComponent)",
                child.displayPath,
                progressStart + progressSpan * (Double(index) / Double(total))
            )
            let size = FileSizeScanner.directorySize(at: child)
            guard size > 0 else { continue }

            let isWritable = (try? child.resourceValues(forKeys: [.isWritableKey]).isWritable) ?? false
            let childRisk: CleanupRisk = isWritable ? safeRisk : .admin
            let detail = isWritable ? safeDetail : protectedDetail
            let children = FileSizeScanner.directoryTree(
                at: child,
                category: category,
                risk: childRisk,
                detail: detail
            )
            add(
                CleanupCandidate(
                    category: category,
                    title: "\(titlePrefix): \(child.lastPathComponent)",
                    path: child,
                    size: size,
                    risk: childRisk,
                    detail: detail,
                    children: children
                )
            )
        }
    }

    private static func expertChildSpecs() -> [(path: String, category: String, titlePrefix: String, safeRisk: CleanupRisk, safeDetail: String, protectedDetail: String)] {
        [
            ("~/Library/Caches", "缓存", "缓存", .safe, "应用缓存，清理后应用首次启动可能变慢", "系统或 App 保护的缓存，当前用户可能无权限清理"),
            ("~/Library/Logs", "日志", "日志", .safe, "诊断日志，通常可清理", "系统或 App 保护的日志，当前用户可能无权限清理"),
            ("~/Library/Application Support", "App 数据", "App Support", .review, "专家模式列出的 App 支持数据，可能包含账号、数据库或项目数据", "受保护的 App 支持数据"),
            ("~/Library/Containers", "容器", "容器", .review, "沙盒 App 容器，可能包含个人数据和设置", "受保护的沙盒容器"),
            ("~/Library/Group Containers", "容器", "共享容器", .review, "App 组共享数据，删除可能影响多个 App", "受保护的共享容器"),
            ("~/Library/HTTPStorages", "网络缓存", "HTTP Storage", .review, "网络缓存和 cookie 存储，清理可能导致重新登录", "受保护的网络存储"),
            ("~/Library/WebKit", "浏览器数据", "WebKit", .review, "WebKit 应用数据，可能包含登录态或离线数据", "受保护的 WebKit 数据"),
            ("~/Library/Mail", "邮件", "Mail", .review, "邮件本地数据和附件索引，谨慎清理", "受保护的邮件数据"),
            ("~/Library/Developer", "开发", "Developer", .review, "开发工具数据，可能包含模拟器、归档或构建缓存", "受保护的开发工具数据")
        ]
    }

    private static func cleanupSpecs() -> [(path: String, category: String, title: String, risk: CleanupRisk, detail: String)] {
        [
            ("~/Library/Containers/com.apple.CoreDevice.CoreDeviceService/Data/Library/Caches", "缓存", "CoreDeviceService 缓存", .safe, "连接设备和 Xcode 相关缓存，可重新生成"),
            ("~/.cache", "缓存", "Unix 用户缓存", .safe, "命令行工具和开发工具缓存"),
            ("~/Library/Application Support/Code/Cache", "开发", "VS Code Cache", .safe, "VS Code 缓存"),
            ("~/Library/Application Support/Code/CachedData", "开发", "VS Code CachedData", .safe, "VS Code 扩展和运行缓存"),
            ("~/Library/Application Support/Google/Chrome/Default/Cache", "浏览器缓存", "Chrome 默认缓存", .safe, "Chrome 网页缓存，清理后网站首次加载可能变慢"),
            ("~/Library/Application Support/Google/Chrome/Default/Code Cache", "浏览器缓存", "Chrome Code Cache", .safe, "Chrome JS/WASM 缓存"),
            ("~/Library/Application Support/Microsoft Edge/Default/Cache", "浏览器缓存", "Edge 默认缓存", .safe, "Edge 网页缓存"),
            ("~/Library/Application Support/Firefox/Profiles", "浏览器数据", "Firefox Profiles", .review, "Firefox 配置和缓存，可能包含登录态、历史和扩展数据"),
            ("~/Library/Saved Application State", "状态", "应用保存状态", .safe, "窗口和会话恢复状态"),
            ("~/Library/Application Support/CrashReporter", "日志", "崩溃报告", .safe, "旧崩溃报告"),
            ("~/Library/Developer/Xcode/DerivedData", "开发", "Xcode DerivedData", .safe, "构建产物和索引，可重新生成"),
            ("~/Library/Developer/Xcode/iOS DeviceSupport", "开发", "Xcode DeviceSupport", .safe, "设备符号缓存，可重新生成"),
            ("~/Library/Developer/Xcode/UserData/Previews", "开发", "Xcode Previews", .safe, "SwiftUI 预览缓存"),
            ("~/Library/Developer/Xcode/Archives", "开发", "Xcode Archives", .review, "发布归档，可能需要保留用于回溯或重新上传"),
            ("~/Library/Developer/CoreSimulator/Caches", "开发", "模拟器缓存", .safe, "iOS 模拟器缓存"),
            ("~/Library/Developer/CoreSimulator/Devices", "开发", "模拟器设备数据", .review, "包含模拟器应用和数据，删除会重置模拟器"),
            ("~/Library/Caches/Homebrew", "开发", "Homebrew 缓存", .safe, "brew 下载缓存"),
            ("~/.npm/_cacache", "开发", "npm 缓存", .safe, "npm 包缓存"),
            ("~/Library/pnpm/store", "开发", "pnpm store", .safe, "pnpm 包缓存"),
            ("~/Library/Caches/Yarn", "开发", "Yarn 缓存", .safe, "Yarn 包缓存"),
            ("~/Library/Caches/pip", "开发", "pip 缓存", .safe, "Python 包缓存"),
            ("~/.gradle/caches", "开发", "Gradle 缓存", .safe, "Gradle 依赖缓存"),
            ("~/.cargo/registry/cache", "开发", "Cargo registry cache", .safe, "Rust crate 下载缓存"),
            ("~/Library/Caches/go-build", "开发", "Go build cache", .safe, "Go 编译缓存"),
            ("~/Library/Caches/ms-playwright", "开发", "Playwright browsers", .safe, "Playwright 浏览器缓存，可重新安装"),
            ("~/Library/Application Support/MobileSync/Backup", "备份", "iPhone/iPad 备份", .review, "个人设备备份，确认后再删除"),
            ("~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads", "邮件", "Mail Downloads", .review, "邮件下载附件，可能包含个人文件"),
            ("~/Library/Messages/Attachments", "附件", "信息附件", .review, "个人聊天附件"),
            ("~/.Trash", "废纸篓", "用户废纸篓", .review, "已删除但尚未清空的文件"),
            ("/Library/Caches", "系统缓存", "系统缓存", .admin, "系统级缓存，可能需要管理员权限"),
            ("/Library/Logs", "系统日志", "系统日志", .admin, "系统级日志，可能需要管理员权限"),
            ("/private/var/tmp", "临时文件", "var tmp", .review, "系统临时文件，避免清理正在使用的文件"),
            ("/tmp", "临时文件", "tmp", .review, "临时文件，避免清理正在使用的文件")
        ]
    }
}

enum TrashService {
    static func trashContentsOrItem(_ url: URL, preserveContainer: Bool) throws {
        let fileManager = FileManager.default

        if preserveContainer,
           (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
           let children = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            var failures: [String] = []
            for child in children {
                do {
                    var resultingURL: NSURL?
                    try fileManager.trashItem(at: child, resultingItemURL: &resultingURL)
                } catch {
                    failures.append("\(child.lastPathComponent): \(error.localizedDescription)")
                }
            }

            if !failures.isEmpty {
                throw NSError(
                    domain: "MACClean.TrashService",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: failures.prefix(6).joined(separator: "\n")]
                )
            }
        } else {
            var resultingURL: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
        }
    }
}
