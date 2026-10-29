# 文档索引

MachOObjCSection 的内部文档。新增或重命名任何文档都必须同步更新这份索引。

面向公众的文档（`README.md`、`LICENSE`、`Changelogs/<版本>.md`）不在此目录，仍在仓库根目录，且使用英文。
`Changelogs/<版本>.md` 是 0.8.204 及之前各版 GitHub Release 的正文；之后的版本只有 tag，不再写（见[发版](#发版)）。

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
| [0007](Evolutions/0007-dump-sections-spelling-and-empty-diagnostics.md) | 修正 dump 的 `--sections` 写法，并让空结果不再无声 | Implemented |
| [0008](Evolutions/0008-objc-export-status.md) | ObjC 类与实例变量的导出状态查询 | Implemented |
| [0009](Evolutions/0009-objc-section-release-automation.md) | 推版本 tag 即自动发布 objc-section | Implemented |
| [0010](Evolutions/0010-remove-objc-section-cli.md) | 移除 objc-section 命令行（并入 swift-section） | Accepted |
| [0011](Evolutions/0011-visibility-regions.md) | 标记模式：一次渲染全量声明，并标出每段内容受哪个开关控制 | Implemented |
| [0012](Evolutions/0012-strip-protocol-conformance-members.md) | stripProtocolConformance 剥掉协议声明的全部成员，保留遵循列表 | Implemented |
| [0013](Evolutions/0013-protocol-adoption-compatibility.md) | 协议新采纳另一个协议时按破坏性改动判定 | Implemented |
| [0014](Evolutions/0014-host-supplied-classes.md) | 由宿主补充文件里没有 class object 的类 | Implemented |
| [0015](Evolutions/0015-objc-evolution-interface.md) | 带演进标注的合并 ObjC 头文件 | Implemented |
| [0016](Evolutions/0016-objc-evolution-image-groups.md) | ObjC 演进按 image 组比较，并报出搬家 | Implemented |
| [draft](Evolutions/draft-objc-duplicate-member-selection.md) | 同一容器里的重复成员按来源取舍，内容相同的不再告警 | In Progress |

## 使用指南

| 文档 | 说明 |
|---|---|
| [objc-section 使用指南](Guides/ObjCSectionCommandLine.md) | 0002、0006、0007、0014、0015 与 0016 的配套。安装（0.8.204 及之前 Releases 上的预编译二进制，之后的版本从源码构建）与命令行用法（含 snapshot / diff / evolution），以及六条从签名和帮助文本里看不出来的契约：文件模式超类链截断、RW data 不在泛型接口上、分析 cache 需要 MachOKit 0.52.101+、纯 Swift 类的 ivar 记录对不上、baseline 的 formatVersion 契约、dump 的空结果只写 stderr 不改退出码。库调用方另有两节：由宿主补充的类的偏移约定、跳过规则、两个查询入口的分工、偏移未知的 ivar，以及经 stub 注册的两种类的 category 各怎么归位；把 N 个版本合并成带演进标注的头文件时的版本顺序、索引器何时可以释放与实测内存、没有标注的含义、重复成员只写比较的那一条（协议副本让位给类自己的声明），以及可用性宏什么时候写；把每个版本的一组 image 当作一个 API 面时，image 名谁给、组的顺序与中途加入、一个版本内怎么合并、搬家什么时候记、为什么不影响判定，以及两种 `addVersion` 不能混用 |

## 实现说明

| 文档 | 说明 |
|---|---|
| [ObjC 渲染层与索引层的实现说明](Internal/ObjCRenderingAndIndexingImplementation.md) | 0001 的配套，已按 0005 订正。三个新 target 的分层与依赖方向、Linux 为什么其实早就断了、锁为什么改用 `@Mutex`、事件通道合并，以及与提案不一致之处 |
| [泛型化到 MachOFile 的实现说明](Internal/ObjCMetadataSourceGenericization.md) | 0002 的配套。`ResolvedSource` 这个 associatedtype 为什么是被逼出来的、IMP 地址抽象边界为何前移、渲染层为何选泛型而非 existential，以及落地时发现的两个上游缺陷。2026-10-27 补记核心 target 唯一的例外：0014 的补充类读取追加在上游文件 `Support/ObjCDump.swift` 末尾 |
| [ObjC API Diff — 设计与已知局限](Internal/ObjCAPIDiffDesignAndLimitations.md) | 0006 的配套。双键设计与键格局（即持久化格式）、与 SwiftDiffing 的六处有意语义差异（method 换签名报 modified、superclass 伪成员等）、六条已知局限（无访问控制之别、ivar 布局变化不可见等）；0016 的配套部分：一个版本的几个 image 怎么合并（同名类、同名 category、各 image 自带的 protocol 副本）、搬家怎么记、为什么不影响判定；[重复成员提案](Evolutions/draft-objc-duplicate-member-selection.md)的配套部分：链接器并进类的 category 为什么让一个类里同一个属性有好几份、取哪份、何时告警 |
| [ObjC 导出状态的判定 — 判据、边界与实测](Internal/ObjCExportStatusResolution.md) | 0008 的配套。为什么只有类和 ivar 能判（协议符号一律 private extern，分类无符号）、三处反直觉边界（per-image 语义与 NSArray、零导出算「无信息」、不用前缀搜索的正确性理由），以及建索引占 `prepare()` 0.085% 的实测数据 |
| [dyld cache 里的指针槽位必须先解码](Internal/DyldCachePointerSlotDecoding.md) | 一次 bug 修复的记录，没有提案。cache 里的指针槽位存的是 slide info 编码（v5 起是相对 cache 起点的偏移，不是地址），必须先经 `resolveRebase` 解码。内容包括：macOS 14.4–15.3.2 上 `objc` 命令 SIGTRAP、11.x–14.3.1 上协议方法丢名的根因，各版本受影响的范围，为什么 CI 上测不到，以及验证数据 |
| [指向本镜像导出符号的 bind 槽位](Internal/SelfBindPointerSlots.md) | 一次 bug 修复的记录，没有提案。用 `-interposable` 链接的 dylib（模拟器 runtime 的框架）以 bind 指向自己导出的类、metaclass 与 ivar offset，读取器原来只解 rebase，iOS 18.5 模拟器 UIKitCore 的 classlist 里 1,586 个条目因此丢失或读错。内容包括：`resolveRebase` 对四种槽位的答法与不要先判 `isBind` / 原值的规则，各版本模拟器的数量，修复前的症状与对 MachOSwiftSection 布局的影响，验证数据 |
| [相对方法列表的选择器引用也是指针槽位](Internal/RelativeMethodListSelectorReferences.md) | 一次 bug 修复的记录，没有提案。磁盘上的相对方法列表里，方法名是到选择器引用槽位的偏移，槽位存的是链式修复编码，要按指针宽度读出再经 `resolveRebase` 解码。内容包括：arm64_32 镜像的方法名为什么全部读成空、64 位为什么只是碰巧读对、来历，以及钉住它的两个小样本 |
| [代码审查的已裁决清单](Internal/CodeReviewAdjudications.md) | 审查报出、判定为不修或误报的问题，连同理由与推翻条件。每次审查先对照它，已裁决且理由仍成立的直接跳过 |
| [relative list of lists 的列表不一定和镜像 header 在同一个文件](Internal/RelativeListsAcrossSubCacheFiles.md) | 一次 bug 修复的记录，没有提案，移植自上游 `10b3dd5`。macOS 26.4 起 cache 把每组镜像的数据单独放进 `.dylddata` 文件，类的属性表、协议表与 header 不在同一个文件；读取器只在 header 所在文件里找，离线读时被别的镜像加过 category 的类（NSView、NSWindow、NSString 等）丢掉全部实例属性和协议列表。内容包括：各版本 cache 的布局与修复前后的数字、受影响的范围、同 PR 的 `ff936fa`（同一镜像的多张列表全部读入）为什么当时没移植、后来随上游 0.8.2 合入（0.8.200），以及验证与耗时数据 |
| [dyld cache 里相对方法名的起算点随版本而变](Internal/DyldCacheRelativeMethodNameBase.md) | 一次 bug 修复的记录，没有提案。cache builder 写的相对方法列表（flag `0x40000000`）里，方法名在 macOS 12 起从选择器基址 `@selector(🤯)` 算起，在 macOS 11 从字段自身算起；macOS 11 的 cache（`objc_opt_t` v15）不记基址，读取器原来就从 cache 开头算，11.x 上类和分类的方法名全部读成乱码。内容包括：按 objc 优化数据的版本而不是「有没有基址」判定、读不到时留空不猜、进程内按运行时版本判定，Apple 源码与 cache 实测的证据，受影响的范围，来历，以及验证数据 |

## 发版

objc-section 不再单独发布：它已并入 MachOSwiftSection，成为 `swift-section objc`。最后一个带预编译二进制的
GitHub Release 是 0.8.204。从 0.8.205 起，库的新版本只推一个 tag：

1. 版本号按 [fork numbering](Glossary.md#fork-numberingfork-版本号) 把第三段的后两位加一。
2. 先推 `next`，再把 `main` 快进到要发布的提交（`git push origin next:main`）。推 `main` 会触发 `ci.yml`（只改了文档时不触发），
   等它通过再打 tag。
3. 在这个提交上打 annotated tag，说明写成 `<版本> — <一句话概括>`，与之前的 tag 一致，然后推送 tag。

不改 `Sources/objc-section/Version.swift`（停在 0.8.204），不写 `Changelogs/<版本>.md`，不建 GitHub Release。
推 tag 不会触发任何工作流：发布用的 `release.yml` 和给它把关的 `version-check.yml` 已经删除，它们由
[0009](Evolutions/0009-objc-section-release-automation.md) 建立，按 [0010](Evolutions/0010-remove-objc-section-cli.md)
退役。命令行本身仍按 0010 的原计划，等 swift-section 发版之后再删。
