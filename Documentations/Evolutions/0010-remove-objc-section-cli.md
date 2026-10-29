# 0010 - 移除 objc-section 命令行（并入 swift-section）

- **状态**: Accepted
- **创建日期**: 2026-09-23
- **最后更新**: 2026-10-29

## 摘要

objc-section 并入 swift-section，成为 `swift-section objc` 子命令组（见 MachOSwiftSection 仓库的提案
[0036](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/blob/next/Documentations/Evolutions/0036-objc-subcommands.md)，
已合入 swift-section 的 `next`）。本仓库是 p-x9/MachOObjCSection 的 fork，带着一个 fork 独有的命令行和
一条发布流水线，同步上游的成本太高。等 swift-section 带着这组子命令发版之后，本仓库删除 objc-section
及其发布流水线，只保留 ObjC 的各个库。

其中发布流水线已于 2026-10-29 提前删除：objc-section 从那天起不再发布，库的新版本只推 tag（0.8.205 起，
做法见[文档索引的「发版」一节](../README.md#发版)）。剩下的命令行仍等前置条件满足再删。

## 方案

**前置条件**：swift-section 已经发布包含 `objc` 子命令的版本。在那之前，本仓库不删命令行。发布流水线不受这个
前提约束，已经提前删除（见决策日志 2026-10-29）。

**删除**：

- `Sources/objc-section/` 与 `Tests/ObjCSectionCommandTests/`。`Version.swift` 停在 0.8.204，随命令行一起删。
- `Package.swift` 里的 `objc-section` 可执行产品与目标、`ObjCSectionCommandTests` 测试目标，以及只有
  命令行用到的 swift-argument-parser 和 Rainbow 两个依赖。
- `.github/workflows/release.yml` 与 `version-check.yml`：已于 2026-10-29 删除。原先要求 `version-check.yml`
  和命令行在同一个提交里删，是怕先删了它读取的 `Version.swift`，让 main 上的版本检查报红；先删检查没有这个问题。

**改写**：

- README 的「Command Line」一节改成几行说明，指向 `swift-section objc`。（2026-10-29 已先改了安装那一段：
  不再发布，0.8.204 之后的版本从源码构建。）
- `Documentations/Guides/ObjCSectionCommandLine.md` 只删命令行部分（已搬到 swift-section 的
  `Documentations/ObjCCommandLine.md`）。写给库调用方的部分留下：泛型参数怎么推断、为什么不建议
  外部实现 `ObjCMetadataSource`、RW data 为什么不在泛型接口上、分析 cache 需要 MachOKit 0.52.101+。
  文件改成库的使用指南，文档索引同步更新。（2026-10-29 已先改了「安装与构建」一节。）
- 术语表 fork numbering 条目去掉 `release.yml` / `version-check.yml` 的部分（版本号形状仍用于库的 tag）。
  已于 2026-10-29 完成。
- 0009 的决策日志补一行：它建立的发布流水线由本提案退役。已于 2026-10-29 完成。

**保留**：`ci.yml`（库的构建与测试）；已发布的 0.8.106 到 0.8.204 各个 Release 及其中的 objc-section
二进制；历史提案 0002 / 0006 / 0007 / 0009 保持原样。

库的版本照常按 fork 版本号打 tag，从 0.8.205 起已经不再生成 GitHub Release。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-23 | Created as Draft | 用户原话：「我打算去掉objc-section集成到swift-section里面了，这个仓库是fork的，维护两边很麻烦」 |
| 2026-09-23 | 只搬命令行，ObjC 的库留在本仓库 | 用户选定 |
| 2026-09-23 | 等 swift-section 发版之后再删 | 用户选定；避免出现两边都拿不到新版 ObjC 命令的空窗 |
| 2026-09-23 | 使用指南不整份删除，只删命令行部分 | 写提案后发现指南里有一半是写给库调用方的（泛型参数、`ObjCMetadataSource`、RW data、MachOKit 版本下限），这些随库留下 |
| 2026-09-23 | Draft → Accepted，落地编号 0010 | 用户批准。本提案先合入记录决定；实现要等前置条件满足，即 swift-section 发布含 `objc` 子命令的版本（MachOSwiftSection 0036 已合入其 `next`） |
| 2026-10-29 | 发布流水线提前退役：删除 `release.yml` 与 `version-check.yml`，objc-section 不再发布，库的新版本只推 tag（0.8.205 起），做法写进文档索引的「发版」一节；README 与使用指南的安装段、术语表、0009 的决策日志同批改好；命令行本身仍等 swift-section 发版后再删 | 用户决定 objc-section 以后不再发布、新版本只推 tag。`version-check.yml` 只为发布流水线把关，先于命令行删除不会让检查报红。原方案说 0.8.106 是唯一的 objc-section 二进制，实际一直发到了 0.8.204，「保留」一条已订正 |
