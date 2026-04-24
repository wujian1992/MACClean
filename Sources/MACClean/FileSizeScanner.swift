import Foundation

enum FileSizeScanner {
    static func directorySize(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        var total: Int64 = 0

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return singleItemSize(at: url)
        }

        for case let itemURL as URL in enumerator {
            autoreleasepool {
                if let values = try? itemURL.resourceValues(forKeys: keys),
                   values.isRegularFile == true {
                    total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                }
            }
        }

        return max(total, singleItemSize(at: url))
    }

    static func singleItemSize(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileAllocatedSizeKey, .totalFileAllocatedSizeKey]) else {
            return 0
        }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }

    static func largeFiles(in roots: [URL], minimumBytes: Int64) -> [CleanupCandidate] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        var candidates: [CleanupCandidate] = []

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                autoreleasepool {
                    guard let values = try? fileURL.resourceValues(forKeys: keys),
                          values.isRegularFile == true else {
                        return
                    }

                    let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                    guard size >= minimumBytes else {
                        return
                    }

                    candidates.append(
                        CleanupCandidate(
                            category: "大文件",
                            title: fileURL.lastPathComponent,
                            path: fileURL,
                            size: size,
                            risk: .review,
                            detail: "个人文件，需要确认用途后再清理",
                            children: []
                        )
                    )
                }
            }
        }

        return candidates
    }

    static func oldArchiveFiles(in roots: [URL], olderThanDays: Int, minimumBytes: Int64) -> [CleanupCandidate] {
        let archiveExtensions = Set(["dmg", "pkg", "mpkg", "zip", "rar", "7z", "tar", "gz", "tgz", "iso", "xz"])
        let cutoff = Date().addingTimeInterval(-Double(olderThanDays) * 24 * 60 * 60)
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey
        ]
        var candidates: [CleanupCandidate] = []

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                autoreleasepool {
                    guard archiveExtensions.contains(fileURL.pathExtension.lowercased()),
                          let values = try? fileURL.resourceValues(forKeys: keys),
                          values.isRegularFile == true else {
                        return
                    }

                    let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                    guard size >= minimumBytes,
                          let modified = values.contentModificationDate,
                          modified < cutoff else {
                        return
                    }

                    candidates.append(
                        CleanupCandidate(
                            category: "旧安装包",
                            title: fileURL.lastPathComponent,
                            path: fileURL,
                            size: size,
                            risk: .review,
                            detail: "专家模式发现的旧安装包或压缩包，确认不再需要后再清理",
                            children: []
                        )
                    )
                }
            }
        }

        return candidates
    }

    static func directoryTree(
        at url: URL,
        category: String,
        risk: CleanupRisk,
        detail: String,
        maxDepth: Int = 1,
        maxChildrenPerLevel: Int = 160
    ) -> [CleanupTreeNode] {
        guard maxDepth > 0,
              (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              let children = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isWritableKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let nodes = children.prefix(maxChildrenPerLevel).compactMap { child -> CleanupTreeNode? in
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isWritableKey])
            let isDirectory = values?.isDirectory == true
            let isRegularFile = values?.isRegularFile == true
            guard isDirectory || isRegularFile else { return nil }

            let size = isDirectory ? directorySize(at: child) : singleItemSize(at: child)
            guard size > 0 else { return nil }

            let childRisk: CleanupRisk = ((values?.isWritable) ?? false) ? risk : .admin
            let childDetail = isDirectory ? "子目录，可继续展开查看明细" : "文件，可单独选择清理"
            let grandchildren = isDirectory && maxDepth > 1
                ? directoryTree(
                    at: child,
                    category: category,
                    risk: childRisk,
                    detail: detail,
                    maxDepth: maxDepth - 1,
                    maxChildrenPerLevel: maxChildrenPerLevel
                )
                : []

            return CleanupTreeNode(
                category: category,
                title: child.lastPathComponent,
                path: child,
                size: size,
                risk: childRisk,
                detail: childDetail,
                isDirectory: isDirectory,
                children: grandchildren
            )
        }

        return nodes.sorted { $0.size > $1.size }
    }
}
