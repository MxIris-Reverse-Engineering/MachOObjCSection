# Evolution 提案

- **项目类型**: 库（源码分发）

本目录记录 MachOObjCSection 的所有实质性变更提案。一次改动一份文件，从前期调研到最终落地
都在同一份里原地更新，不另起 design / plan / report。

被否决的提案保留不删 —— 它是「当初为什么没这么做」的唯一记录。

## 状态说明

| 状态 | 含义 |
|---|---|
| `Draft` | 撰写中，尚未提交评审 |
| `In Review` | 开放讨论中 |
| `Accepted` | 已批准，可以开始实现 |
| `In Progress` | 实现进行中 |
| `Implemented` | 实现完成并已合并 |
| `Rejected` | 已否决（保留存档） |
| `Deferred` | 方向成立但延后 |
| `Withdrawn` | 作者撤回 |

## 提案列表

| # | 标题 | 状态 |
|---|------|------|
| [0001](0001-objc-rendering-and-indexing-downstreaming.md) | ObjC 渲染层与索引层下沉，并抽出两库共用的公共底座 | Implemented |
| [0002](0002-objc-machofile-genericization-and-cli.md) | ObjC 索引层泛型化到 MachOFile，并提供 objc-section CLI | Implemented |
| [0003](0003-objc-relationship-tables-return-to-application.md) | ObjC 关系反向表移出索引层，归还应用 | Implemented |
| [0004](0004-strip-synthesized-setter-selector-fix.md) | 修正 stripSynthesizedMethods 漏剥 setter 的选择器拼写 | Implemented |
| [0005](0005-adopt-frameworktoolbox-utilities.md) | 改用 FrameworkToolbox 的 Mutex 与字符串工具，删掉本地手搓的副本 | Implemented |
| [0006](0006-objc-api-diff-and-evolution.md) | ObjC API Diff 与多版本 Evolution 追踪 | Implemented |
| [0007](0007-dump-sections-spelling-and-empty-diagnostics.md) | 修正 dump 的 `--sections` 写法，并让空结果不再无声 | Implemented |
| [0008](0008-objc-export-status.md) | ObjC 类与实例变量的导出状态查询 | Implemented |
| [0009](0009-objc-section-release-automation.md) | 推版本 tag 即自动发布 objc-section | Implemented |
| [0010](0010-remove-objc-section-cli.md) | 移除 objc-section 命令行（并入 swift-section） | Accepted |
| [0011](0011-visibility-regions.md) | 标记模式：一次渲染全量声明，并标出每段内容受哪个开关控制 | Implemented |
| [0012](0012-strip-protocol-conformance-members.md) | stripProtocolConformance 剥掉协议声明的全部成员，保留遵循列表 | Implemented |
| [0013](0013-protocol-adoption-compatibility.md) | 协议新采纳另一个协议时按破坏性改动判定 | Implemented |
| [0014](0014-host-supplied-classes.md) | 由宿主补充文件里没有 class object 的类 | Implemented |
| [0015](0015-objc-evolution-interface.md) | 带演进标注的合并 ObjC 头文件 | Implemented |
| [0016](0016-objc-evolution-image-groups.md) | ObjC 演进按 image 组比较，并报出搬家 | Implemented |
| [0017](0017-objc-duplicate-member-selection.md) | 同一容器里的重复成员按来源取舍，内容相同的不再告警 | Implemented |
| [0018](0018-objc-exported-declarations-only.md) | 只打印导出的 ObjC 声明，导出判断改按地址 | Implemented |
| [draft](draft-objc-comment-structure-marking.md) | 给 ObjC 注释标出种类和各段的角色 | In Progress |
| [cross-repository MachOSwiftSection 0088](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/blob/next/Documentations/Evolutions/0088-machofile-performance.md) | 离线读取追平进程内：由 MachOSwiftSection 维护唯一提案；本库的部分是 dyld cache 里按地址、按 header 序号找镜像，每个 cache 只建一次表 | Implemented |
| [cross-repository MachOSwiftSection 0096](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/blob/next/Documentations/Evolutions/0096-swift-first-imported-declarations.md) | Swift 实现的类，导入声明以 Swift 一侧为准：由 MachOSwiftSection 维护唯一提案；本库的部分是头文件按宿主给的 Swift 导入标注（`ObjCSwiftImportNotes`）打出 `NS_REFINED_FOR_SWIFT` | Implemented |
| [cross-repository MachOSwiftSection 0105](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/blob/next/Documentations/Evolutions/0105-swift-type-indexing-package.md) | 类型索引独立成 swift-type-indexing 包：由 MachOSwiftSection 维护唯一提案；本库的部分是新 target `ObjCTypeIndexing`（`ObjCDeclaredTypeNames` 给 `TypeDatabase` 当私有类型的归属来源，SDK 的 API notes 转成 `ObjCSwiftImportNotes`），`ObjCSwiftImportNotes` 加 `NS_SWIFT_NAME` 与类、协议本身的标注，协议与 category 入口也接标注；两个宏改打成 swift-semantic-string 0.7.0 的 `Macro`，用 Xcode 的宏色。随 0.8.209 发布 | Implemented |
| [cross-repository MachOSwiftSection 0098](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/blob/next/Documentations/Evolutions/0098-move-cross-reference-layers.md) | 交叉引用的核心层与 ObjC 层迁出 MachOSwiftSection：由 MachOSwiftSection 维护唯一提案；本库的部分是新 target `ObjCCodeReferences`（原 MachOSwiftSection 的 `CrossReferenceObjC`，层间接口是 `@_spi(Internals)`），MachOKitExtensions 的下限抬到 2.0.0，随 0.8.207 发布 | Implemented |
| [cross-repository MachOKitExtensions 0004](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Evolutions/0004-split-symbol-language.md) | 符号语言的判断归各自的包：由 MachOKitExtensions 维护唯一提案；本库的部分是在这里定义 `SymbolLanguage.objectiveC` 与 Objective-C 符号名的判断，镜像加载时由 `MachOObjCSectionC` 的 constructor 注册；MachOKitExtensions 的范围改为 3.x，随 0.8.208 发布 | Implemented |
| [cross-repository MachOSwiftSection 0101](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/blob/next/Documentations/Evolutions/0101-swift6-mode-and-upcoming-features.md) | MachO 系列库统一 Swift 6 语言模式并开启三项 upcoming feature：由 MachOSwiftSection 维护唯一提案；本库的部分是每个 Swift target 开启 `ExistentialAny`、`MemberImportVisibility`、`InferIsolatedConformances`，并按 fix-it 补 import 与 `any`（`FileIO`、`MachOKitExtensions` 沿用本库已有的 `internal import`） | Implemented |

0002 以 0001 为前置，两者共同构成「让 MachOObjCSection 具备与 MachOSwiftSection 对等的
渲染 / 索引 / 命令行能力」这一条完整路线。

0003 修订 0001 的范围判断（0001 保持原貌不改），并应先于 0002 落地 —— 它删掉的正是泛型化里
最麻烦的那部分，先删能让 0002 的面积小一圈。实际落地顺序即 **0001 → 0003 → 0002**，
这条路线到 0002 为止已经走完。
