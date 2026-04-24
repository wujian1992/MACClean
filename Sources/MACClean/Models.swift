import Foundation
import SwiftUI

enum CleanupRisk: String, CaseIterable, Identifiable, Sendable {
    case safe = "可清理"
    case review = "需确认"
    case admin = "需管理员"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .safe:
            return .green
        case .review:
            return .orange
        case .admin:
            return .red
        }
    }
}

struct CleanupCandidate: Identifiable, Hashable, Sendable {
    let id = UUID()
    let category: String
    let title: String
    let path: URL
    let size: Int64
    let risk: CleanupRisk
    let detail: String
    let children: [CleanupTreeNode]
}

struct CleanupTreeNode: Identifiable, Hashable, Sendable {
    let id: String
    let category: String
    let title: String
    let path: URL
    let size: Int64
    let risk: CleanupRisk
    let detail: String
    let isDirectory: Bool
    let children: [CleanupTreeNode]

    init(
        category: String,
        title: String,
        path: URL,
        size: Int64,
        risk: CleanupRisk,
        detail: String,
        isDirectory: Bool,
        children: [CleanupTreeNode] = []
    ) {
        self.id = path.standardizedFileURL.path
        self.category = category
        self.title = title
        self.path = path
        self.size = size
        self.risk = risk
        self.detail = detail
        self.isDirectory = isDirectory
        self.children = children
    }
}

extension CleanupCandidate {
    var selectionKey: String {
        path.standardizedFileURL.path
    }

    var asTreeNode: CleanupTreeNode {
        CleanupTreeNode(
            category: category,
            title: title,
            path: path,
            size: size,
            risk: risk,
            detail: detail,
            isDirectory: path.isDirectory,
            children: children
        )
    }
}

extension CleanupTreeNode {
    var selectionKey: String {
        path.standardizedFileURL.path
    }

    var flattened: [CleanupTreeNode] {
        [self] + children.flatMap(\.flattened)
    }
}

struct AppResidue: Identifiable, Hashable, Sendable {
    let id = UUID()
    let title: String
    let path: URL
    let size: Int64
    let risk: CleanupRisk
    let detail: String
}

struct InstalledApp: Identifiable, Hashable, Sendable {
    let id = UUID()
    let name: String
    let path: URL
    let bundleIdentifier: String
    let version: String
    let size: Int64
    let residues: [AppResidue]

    var totalSize: Int64 {
        size + residues.reduce(0) { $0 + $1.size }
    }
}

struct ScanSummary: Sendable {
    var totalBytes: Int64 = 0
    var itemCount: Int = 0
    var scannedAt = Date()
}

enum WorkMode: String, Sendable {
    case idle
    case scanning
    case cleaning
    case uninstalling
    case completed

    var displayTitle: String {
        switch self {
        case .idle:
            return "准备就绪"
        case .scanning:
            return "正在扫描"
        case .cleaning:
            return "正在清理"
        case .uninstalling:
            return "正在卸载"
        case .completed:
            return "已完成"
        }
    }

    var symbolName: String {
        switch self {
        case .idle:
            return "sparkles"
        case .scanning:
            return "magnifyingglass"
        case .cleaning:
            return "trash"
        case .uninstalling:
            return "app.badge.checkmark"
        case .completed:
            return "checkmark"
        }
    }
}

struct ActivityLine: Identifiable, Hashable, Sendable {
    let id = UUID()
    let title: String
    let detail: String
    let timestamp = Date()
}

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension URL {
    var displayPath: String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var isDirectory: Bool {
        var isDirectory = ObjCBool(false)
        FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }
}
