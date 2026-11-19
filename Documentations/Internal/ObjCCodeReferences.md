# ObjCCodeReferences

MachOSwiftSection 交叉引用分析的 Objective-C 层：经 `objc_msgSend`、selector 桩或 libobjc 专用入口的消息发送与 `super` 发送、发送的接收者、classref / superref / 类对象引用、经 `__objc_ivar` 偏移变量的 ivar 读写，ObjC 方法列表给出的函数名（`ObjCMethodNames`），按 selector 与按类的预筛，以及 libobjc 的运行时辅助函数名单（`ObjCRuntimeHelperNames`）。以识别器（`ObjCCodeReferenceRecognizer` 与它为每次扫描建的会话）接进 MachOKitExtensions 的 `MachOCodeReferences` 的扫描。

- 来历：MachOSwiftSection 提案 0097 在那边把交叉引用拆成三层，ObjC 层叫 `CrossReferenceObjC`；提案 [0098 move-cross-reference-layers](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/blob/next/Documentations/Evolutions/0098-move-cross-reference-layers.md) 把它搬来本库，改名 `ObjCCodeReferences`，随 0.8.207 发布。发送入口的来历见那边的提案 0076（libobjc 的专用发送入口）。
- 单独一个 target：上游的 `MachOObjCSection` target 不碰，fork 的新增放在自己的 target 里，合上游时不冲突（见 [ObjCMetadataSourceGenericization.md](ObjCMetadataSourceGenericization.md)）。它读类对象要用 `@_spi(Core)` 的 `ObjCClass64(layout:offset:)`，现在是包内调用。
- 依赖：MachOKit、`MachOObjCSection`、MachOKitExtensions 的 `MachOCodeReferences`。因为后者是 MachOKitExtensions 2.0.0 才有的，本库 0.8.207 起要求 MachOKitExtensions `"2.0.0"..<"3.0.0"`，不能再与 MachOSwiftSection 0.24.0 及更早的版本同时解析（它们要 MachOKitExtensions 1.x）。
- 使用方：只有 MachOSwiftSection 的 `CrossReferenceAnalysis`，它把三层拼成对外的分析器 `CrossReferenceAnalyzer`。

## 接口只给 MachOSwiftSection 用

- 接口都是 `@_spi(Internals) public`：搬来之前它们是 MachOSwiftSection 包内的 `package`，跨包之后只能用 SPI。SPI 不承诺稳定，随时可能改，不算破坏性变更。
- 真正公开的只有 `ReceiverClassHint`（发送的接收者是哪一种：类字面量、方法的 `self`、不知道），它经 MachOSwiftSection 的 `CrossReferenceAnalysis` 重导出，是那边公开 API 的一部分，照常守 semver。

## 源码规则

- 只经 `CrossReferenceMemory` 读镜像内存，自己不把地址变成指针，这样从文件建的镜像集永远不会读到本进程的内存（`SourceScanTests.objectiveCLayerReadsMemoryOnlyThroughCrossReferenceMemory`）。
- 不写 `swift_` 开头的字符串字面量：Swift 运行时的名单属于 MachOSwiftSection 的 Swift 层（`objectiveCLayerSpellsNoSwiftRuntimeName`）。
- 进程内与文件两种读取器的差别经 `asMachOImage` / `asMachOFile` 分两条路读（方法的 `imp` 在文件里是读取器 offset，在进程内是运行时地址；类在文件里从不 realize）。

## 怎么工作

识别器接进扫描的五个时机、发送入口、类引用、ivar、预筛与吞吐，写在 MachOSwiftSection 的 [Modules/CrossReferenceAnalysis.md](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/blob/next/Documentations/Internal/Modules/CrossReferenceAnalysis.md)：三层的代码一起演进，那份文档是它们的总说明，这里不重复。

## 测试

`ObjCCodeReferencesTests` 只有上面两条源码扫描。ObjC 层的行为测试都要经分析器建镜像集、跑扫描，留在 MachOSwiftSection 的 `CrossReferenceAnalysisTests`（发送入口、类引用、方法名回退、文件模式等）。
