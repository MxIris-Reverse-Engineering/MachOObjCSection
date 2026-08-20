# 文档索引

MachOObjCSection 的内部文档。新增或重命名任何文档都必须同步更新这份索引。

面向公众的文档（`README.md`、`LICENSE`）不在此目录，仍在仓库根目录，且使用英文。

## 目录

- [Evolutions/](Evolutions/README.md) —— 变更提案。一次实质改动一份，从调研到落地全生命周期。
- [Guides/](#使用指南) —— 使用指南。面向调用方，记录怎么用、必须遵守什么契约、有什么坑。
- [Internal/](#实现说明) —— 实现说明。面向维护者，记录最终怎么实现、为什么这么实现、有什么降级。
- [Glossary.md](Glossary.md) —— 项目术语表。本项目自造词与约定用法；跨项目通用术语在全局术语表。

## 提案

| # | 标题 | 状态 |
|---|------|------|
| [0001](Evolutions/0001-objc-rendering-and-indexing-downstreaming.md) | ObjC 渲染层与索引层下沉，并抽出两库共用的公共底座 | Implemented |
| [0002](Evolutions/0002-objc-machofile-genericization-and-cli.md) | ObjC 索引层泛型化到 MachOFile，并提供 objc-section CLI | Implemented |
| [0003](Evolutions/0003-objc-relationship-tables-return-to-application.md) | ObjC 关系反向表移出索引层，归还应用 | Implemented |
| [0004](Evolutions/0004-strip-synthesized-setter-selector-fix.md) | 修正 stripSynthesizedMethods 漏剥 setter 的选择器拼写 | Implemented |
| [0005](Evolutions/0005-adopt-frameworktoolbox-utilities.md) | 改用 FrameworkToolbox 的 Mutex 与字符串工具，删掉本地手搓的副本 | Implemented |
| [0006](Evolutions/0006-objc-api-diff-and-evolution.md) | ObjC API Diff 与多版本 Evolution 追踪 | Implemented |

## 使用指南

| 文档 | 说明 |
|---|---|
| [objc-section 使用指南](Guides/ObjCSectionCommandLine.md) | 0002 与 0006 的配套。命令行用法（含 snapshot / diff / evolution），以及五条从签名和帮助文本里看不出来的契约：文件模式超类链截断、RW data 不在泛型接口上、分析 cache 需要 MachOKit 0.52.101+、纯 Swift 类的 ivar 记录对不上、baseline 的 formatVersion 契约 |

## 实现说明

| 文档 | 说明 |
|---|---|
| [ObjC 渲染层与索引层的实现说明](Internal/ObjCRenderingAndIndexingImplementation.md) | 0001 的配套，已按 0005 订正。三个新 target 的分层与依赖方向、Linux 为什么其实早就断了、锁为什么改用 `@Mutex`、事件通道合并，以及与提案不一致之处 |
| [泛型化到 MachOFile 的实现说明](Internal/ObjCMetadataSourceGenericization.md) | 0002 的配套。`ResolvedSource` 这个 associatedtype 为什么是被逼出来的、IMP 地址抽象边界为何前移、渲染层为何选泛型而非 existential，以及落地时发现的两个上游缺陷 |
| [ObjC API Diff — 设计与已知局限](Internal/ObjCAPIDiffDesignAndLimitations.md) | 0006 的配套。双键设计与键格局（即持久化格式）、与 SwiftDiffing 的五处有意语义差异（method 换签名报 modified、superclass 伪成员等）、六条已知局限（无访问控制之别、ivar 布局变化不可见等） |
