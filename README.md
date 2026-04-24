# MACClean

MACClean 是一个使用 SwiftUI 开发的开源 macOS 清理工具。它偏向“专家模式”：扫描本机可清理项目，展示目录树和文件占用，让用户确认后再把所选项目移动到 macOS 废纸篓。

![专家模式扫描](docs/images/expert-cleanup.png)

![专家 App 卸载](docs/images/expert-app-uninstall.png)

## 功能特性

- 专家模式电脑扫描：缓存、日志、App Support、沙盒容器、浏览器数据、开发环境缓存、备份、旧安装包和大文件。
- 懒加载目录树：大目录可以逐层展开查看，不会因为一次性渲染所有子目录而卡住界面。
- App 卸载扫描：扫描 `/Applications` 和 `~/Applications`。
- App 残留识别：按 bundle id 和 App 名称匹配用户级、系统级残留。
- 支持识别 LaunchAgents、LaunchDaemons、PrivilegedHelperTools、Receipts、Homebrew Cask 数据。
- 扫描、清理、卸载、搜索都有动态状态反馈。
- 风险标签：`可清理`、`需确认`、`需管理员`。
- 安全清理：所选文件移动到废纸篓，不做永久删除。

## 安全策略

MACClean 不会自动清理任何内容。

- 必须由用户手动勾选项目。
- 清理和卸载前必须二次确认。
- 文件会移动到 macOS 废纸篓。
- 标记为 `需确认` 的项目可能包含用户数据，需要人工检查。
- 标记为 `需管理员` 的项目会在专家模式中展示，但没有权限时可能无法移动。

## 环境要求

- macOS 14 或更高版本
- Xcode Command Line Tools
- 兼容 Swift 6 的工具链

## 运行

```sh
git clone https://github.com/wujian1992/MACClean.git
cd MACClean
swift run MACClean
```

如果是在当前本机目录运行：

```sh
cd /Users/reyeah/Documents/MACClean
swift run MACClean
```

## 构建

```sh
swift build
```

## 项目结构

```text
Package.swift
Sources/MACClean/
  MACCleanApp.swift
  ContentView.swift
  CleanupView.swift
  AppsView.swift
  CleanupStore.swift
  AppsStore.swift
  FileSizeScanner.swift
  Models.swift
  SharedViews.swift
docs/images/
scan_mac_junk.zsh
```

## 说明

当前版本刻意保持保守：它使用普通用户权限，不包含特权 helper。专家模式会展示系统级路径，但如果 macOS 拒绝访问，移动到废纸篓可能失败，这是预期行为。

## 许可证

MIT
