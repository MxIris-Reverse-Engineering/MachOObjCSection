# 0001 - ObjC 渲染层与索引层下沉，并抽出两库共用的公共底座

- **状态**: Draft
- **作者**: JH
- **创建日期**: 2026-08-09
- **最后更新**: 2026-08-09
- **所属愿景**: 无
- **关联提案**: [0002](0002-objc-machofile-genericization-and-cli.md)（后续，承接本篇的非目标）
- **实现分支 / PR**: 待定
- **配套文档**: 待定 —— 落地时登记实现说明 / 使用指南的链接

## 摘要

把 RuntimeViewerCore 里的 Objective-C 渲染层（`ObjCDump*Info` → `SemanticString`）与索引层
（类 / 协议 / 分类 / C struct / union 索引 + 继承与协议遵守反向表）下沉到 MachOObjCSection，
成为三个新 target：`ObjCDeclarationRendering`、`ObjCIndexing`、`ObjCInterface`。

为解开由此产生的循环依赖，同时做两件抽包：把 `MachOExtensions` 从 MachOSwiftSection 迁出为同名的
独立仓库，把 `OutputTransformer` 并入现有的 `swift-semantic-string` 作为第二个
target / product。RuntimeViewerCore 随后删除本地副本改为引用库版本。

本提案**不含** `objc-section` CLI，也**不含**把索引层泛型化到 `MachOFile`——两者是同一件事的
前后两步，留待后续提案。

## 动机

MachOObjCSection 目前只解析、不渲染。它把 Mach-O 里的 ObjC 元数据读成
`ObjCClassInfo` / `ObjCProtocolInfo` / `ObjCCategoryInfo`（`Sources/MachOObjCSection/Support/ObjCDump.swift`），
到此为止。想拿到一段人能读的 `@interface` 声明，调用方只有两个选择：

1. 用 `ObjCDump` 包自带的 `headerString` —— 纯文本，没有语义标注，无法着色、无法做 token 级替换、
   无法插入偏移 / IMP 地址注释；
2. 自己写一套渲染器。

RuntimeViewer 走了第 2 条路，写出了
`RuntimeViewerCore/Sources/RuntimeViewerCore/Utils/ObjCDump+SemanticString.swift`（896 行）
与 `RuntimeViewerCore/Sources/RuntimeViewerCore/Indexing/RuntimeObjCInterfaceIndexer.swift`（639 行）。
这两份代码没有任何 RuntimeViewer 专属逻辑——它们做的事是"把 ObjC 元数据渲染成带语义的声明"
和"把一个镜像的 ObjC 元数据建成可查询的索引"，任何一个 MachOObjCSection 的使用方都会需要，
却被锁在一个 GUI 应用的 Core 层里。

对照 Swift 一侧：MachOSwiftSection 有完整的 `SwiftDeclarationRendering` / `SwiftIndexing` /
`SwiftPrinting` / `SwiftInterface` 分层，外加 `swift-section` 命令行工具。ObjC 一侧一样都没有。
这个不对称的直接后果是：

- 想在命令行上 dump 一个二进制的 ObjC 头，没有工具可用；
- MachOSwiftSection 的 13 个 target 都依赖 MachOObjCSection，但只能拿到裸元数据，
  拿不到渲染结果；
- RuntimeViewer 之外的任何消费者都得把这 1500 行重写一遍。

同时，`OutputTransformer` 自己的文档注释（`Sources/OutputTransformer/Transformer.swift:12-16`）
已经把这件事记成待办：

> The ObjC-side modules (`CType`, `ObjCIvarOffset`) and the aggregate persistence `Configuration`
> currently remain in RuntimeViewerCore (declared as extensions of this namespace),
> **pending a library-side home for the ObjC rendering pipeline**.

本提案要建的就是那个 home。

## 前期调研

### 待搬运的代码及其规模

| 文件（RuntimeViewerCore 内） | 行数 | 性质 |
|---|---:|---|
| `Utils/ObjCDump+SemanticString.swift` | 896 | 渲染器 + `ObjCDumpContext` + `NamingIntelligent` 参数名推断 |
| `Indexing/RuntimeObjCInterfaceIndexer.swift` | 639 | 索引 + struct/union 采集 + 继承与遵守反向表 |
| `Utils/MachOImage+AddressFormatting.swift` | 44 | IMP 地址格式化与注释构造 |
| `Transformer/Transformer+CType.swift` | 210 | C 基本类型替换（`SemanticString → SemanticString`） |
| `Transformer/Transformer+ObjCIvarOffset.swift` | 87 | ivar 偏移注释模板 |
| `Transformer/Transformer.swift` | 54 | `ObjCConfiguration` + 聚合 `Configuration` |
| `Core/RuntimeObjCSection.swift` 中的 strip 逻辑 | ~250 | `ObjCGenerationOptions` 十个开关对应的成员过滤 |

`RuntimeObjCSection.swift` 全文 625 行，其中只有 strip 过滤与渲染编排要搬；
`RuntimeObject` / `RuntimeObjectInterface` 的包装留在 RuntimeViewer。

### 这两个文件挂着的依赖

| 用到的东西 | 来源 | 状态 |
|---|---|---|
| `Semantic`（`SemanticString` 及各 builder） | `swift-semantic-string`，零依赖，tag 0.2.0 | 新增包依赖，可直接加 |
| `ObjCDump` | `swift-objc-dump` | MachOObjCSection 已依赖 |
| `ObjCTypeDecodeKit` | `swift-objc-dump` | 无需处理，直接 `import`（见下） |
| `MachOExtensions`（仅用 `addressString(forOffset:)`） | MachOSwiftSection | **循环**，见下 |
| `Transformer.CType` / `.ObjCIvarOffset` | RuntimeViewerCore + `OutputTransformer` | **循环**，见下 |
| `@Mutex`、`uppercasedFirst`、`orEmpty`、`removingAll` | `FrameworkToolbox` / `SwiftStdlibToolbox` | 宏包，为几个小工具引入不划算 |
| `offsetEnumerated()` | MachOSwiftSection 的 `Utilities` | **循环** |
| `OrderedCollections` | `swift-collections` | 新增依赖 |
| `MemberwiseInit` | `swift-memberwise-init-macro` | 宏包，可去掉 |
| `RuntimeObjectsLoadingEvent` / `LoadingEventContinuation` | RuntimeViewerCore | RuntimeViewer 专属，需换成本地事件类型 |

### `ObjCTypeDecodeKit` 不需要额外处理

`swift-objc-dump` 只导出 `ObjCDump` 一个 product，`ObjCTypeDecodeKit` 是它的 target 依赖
（`Package.swift:100-112`）。`ObjCDump` 并未 `@_exported` 转发它，但两个 module 都会被构建到
同一个搜索路径下，因此依赖 `ObjCDump` product 后直接 `import ObjCTypeDecodeKit` 即可编译。

现成的证据：`RuntimeViewerCore/Package.swift` 里完全没有出现 `swift-objc-dump`
（`ObjCDump` 本身也是经 MachOObjCSection 传递而来），而
`Utils/ObjCDump+SemanticString.swift:5-6` 同时 `import ObjCDump` 与
`import ObjCTypeDecodeKit`，构建正常。

这依赖的是 SwiftPM 的隐式传递导入行为，并非显式契约；若将来 Swift 收紧这一点，
再回上游补一个 product 即可，不构成本提案的前置阻塞。

### 循环依赖的成因

MachOSwiftSection 的 `Package.swift:190-198` 声明了对 MachOObjCSection 的包依赖，
包内 13 个 target 通过 `.product(.MachOObjCSection)` 使用它。因此 MachOObjCSection
**不能反向依赖 MachOSwiftSection 的任何 target**，而 `MachOExtensions`、`OutputTransformer`、
`Utilities` 三者都在 MachOSwiftSection 包内。

这一点仓库里已有明确记载。`Sources/MachOObjCSection/Protocol/MachOObjCSectionRepresentable.swift:12-20`：

> The supertype is `MachORepresentable` rather than the stronger `MachORepresentableWithCache`
> (which lives in MachOSwiftSection's MachOExtensions module). Pulling MachOExtensions in here
> would create a package-level cycle […] so we trade the `cache` / `identifier` requirements
> for cycle-freedom.

也就是说，为了绕开这个环，MachOObjCSection 已经主动放弃了一部分能力。

### MachOExtensions 抽包的可行性

已查证：

- **19 个文件、958 行**。
- **源码里根本没有 `import Utilities`** —— `Package.swift:311-317` 里那条 `.target(.Utilities)`
  依赖是空挂的。实际外部依赖只有 `MachOKit`、`FoundationToolbox`、`AssociatedObject`。
- **53 个 `package` 级符号**。抽成独立包后，MachOSwiftSection 内那 13 个使用方变成跨包访问，
  这 53 个符号**必须全部提升为 `public`**，无法分批。
- **3 处 `@AssociatedObject`**（`MachOFile+.swift:62`、`MachOFile+.swift:106`、
  `MachORepresentableWithCache.swift:53`），底层是 `objc_setAssociatedObject`，**Linux 不可用**。
- 平台底线一致：MachOSwiftSection 是 `macOS 10.15 / iOS 13 / tvOS 13 / watchOS 6 / visionOS 1`，
  MachOObjCSection 是同样四项（无 visionOS），无冲突。

### OutputTransformer 抽包的可行性

已查证：

- **6 个文件、1566 行**，**全包只 `import Foundation`**，符号本来就全是 `public`，
  无需提升访问级别。
- 各模块的 `Input` 已经与领域类型完全解耦，全是扁平的 `Int` / `String`：

  | 模块 | `Input` |
  |---|---|
  | `SwiftFieldOffset` | `{ startOffset: Int, endOffset: Int? }` |
  | `SwiftMemberAddress` | `{ offset: Int }` |
  | `SwiftVTableOffset` | 同类，纯数值 |
  | `SwiftTypeLayout` | 同类，纯数值 |
  | `SwiftEnumLayout`（908 行） | 15 个字段，全为 `Int` / `String` |
  | `ObjCIvarOffset`（在 RuntimeViewerCore） | `{ offset: Int }` |
  | `CType`（在 RuntimeViewerCore） | `SemanticString → SemanticString` |

  即便是最复杂的 `SwiftEnumLayout`，也已把 `bitsNeededForTag`、`tagRegionBytesHex` 等
  拍扁成基本类型，不引用任何 Swift metadata 类型。本质上它是一个 **token 模板引擎**。
- `SwiftConfiguration` 已有把 `MetaCodable` 的 `@Default(ifMissing:)` 换成手写
  `init(from:)` 的先例（`Transformer.swift:71-80`），`ObjCIvarOffset` / `CType` 照做即可。

### Linux 现状

MachOObjCSection **已经支持 Linux**，且是活跃维护的：

- `Sources/MachOObjCSection/Util/WeakKeyStrongValueMap.swift:11` 的 `#if !canImport(ObjectiveC)`
  分支，正是为了在没有 ObjC runtime 的平台上替代 associated object；
- `Model/Method/ObjCMethod.swift:106`、`Protocol/Class/ObjCStubClassProtocol.swift:33`
  等处均有 `canImport(ObjectiveC)` 分叉；
- 最近的上游 commit `a1b3db8 Fix Objective-C stub APIs on Linux`。

MachOSwiftSection 的平台列表里没有 Linux，`MachOExtensions` 因此可以随意用
`@AssociatedObject`。抽包后若不处理，会让 MachOObjCSection 的 Linux 支持退化。

### 本仓库是 fork（关键约束）

`git remote -v` 显示 `upstream = https://github.com/p-x9/MachOObjCSection.git`，
本仓库是其 fork，且**仍在持续合并上游 tag**（`5b563cc Merge tag '0.8.1' from upstream`），
版本号走 `0.8.100` / `0.8.101` 这类 fork 专用编号。

这直接决定了改动的风险分级：

- **新增目录 + 改 `Package.swift`**：低风险。`Package.swift` 早已 fork 化
  （`localEnvironment` / `.package.env` 那套上游没有），合并冲突已是常态，多几行不改变性质。
- **修改 `Sources/MachOObjCSection/` 下的既有文件**：高风险。这些是上游文件，上游还在改，
  每次合并都要手工解冲突。

### 两侧已存在的重复代码

`Sources/MachOObjCSection/Extension/`（1394 行）与 `MachOExtensions`（958 行）已有实质重复：

| 文件 | 重复内容 |
|---|---|
| `LoadCommandsProtocol+.swift` | `text` / `text64` / `data` / `data64` / `dataConst` / `dataConst64` 六项完全重复；Swift 侧另有 `auth64` / `authConst64` / `buildVersionCommand` |
| `MachOFile+.swift` | `cache(for:)`、`cacheAndFileOffset(for:)`、`cacheAndFileOffset(fromStart:)`、`resolveRebase`、`isBind` 重复 |
| `DyldCache+.swift` | `fileStartOffset` 重复，其余各自特有 |
| `SegmentCommandProtocol+.swift` | 不重复。ObjC 侧是 `__objc_*` 具名封装，本可建在 Swift 侧通用的 `_section(for:in:)` 之上 |
| `MachORepresentable+.swift` | 基本不重复 |

抽包**使**去重成为可能，但由于上一条的 fork 约束，本提案**不做**去重（见非目标）。

## 提议方案

### 一、`MachOExtensions`（新建仓库）

把 MachOSwiftSection 的 `MachOExtensions` target 整体迁出为独立包。

- 仓库位置 `/Volumes/Repositories/Private/Org/MxIris-Reverse-Engineering/MachOExtensions`。
  仓库名、包名、target 名、product 名四者一致，均为 `MachOExtensions`，
  沿用 MachO 系仓库的 PascalCase 命名惯例（`MachOKit`、`MachOKitUI`、`MachOObjCSection`、
  `MachOSwiftSection`、`MachOViewer`）；`swift-*` 连字符形式只用于非 MachO 的通用包；
- `import MachOExtensions` 两侧一行不用改；
- 53 个 `package` 符号全部提升为 `public`；
- 3 处 `@AssociatedObject` 改用 MachOObjCSection 现成的 `WeakKeyStrongValueMap` 思路，
  平台列表加上 Linux；
- MachOSwiftSection 侧只改 `Package.swift`（删 target 定义、加包依赖、把
  `.target(.MachOExtensions)` 换成 `.product(...)`），**源码零改动**。

### 二、`OutputTransformer` 并入 `swift-semantic-string`

不新建仓库，在现有 `swift-semantic-string`（自有仓库、非 fork、tag 0.2.0、866 行）里
加第二个 target 与第二个 product：

```
swift-semantic-string
├── Semantic          （现有，零依赖，不变）
└── OutputTransformer （新，依赖 Semantic）
```

理由：`Transformer.CType` 的 `Input` / `Output` 就是 `SemanticString`，其余模块的产物是要塞进
`Comment(...)` 的字符串——`Transformer` 与 `Semantic` 是同一条渲染管线上前后相邻的两环，
依赖方向天然为 `Transformer → Semantic`，无环。做成独立 product，只要 `SemanticString`
的使用方不会被迫拉进模板引擎。

同时把 RuntimeViewerCore 的三个 ObjC 侧 transformer（`CType`、`ObjCIvarOffset`、
`ObjCConfiguration`）以及聚合 `Configuration` 一并迁入，`MetaCodable` 宏换成手写
`init(from:)`。至此 `Transformer` 命名空间在一个包内完整，RuntimeViewer 的 `Transformer/`
目录可整个删除，只留 settings UI。

### 三、MachOObjCSection 新增三个 target

```
MachOObjCSection            现有，纯解析，不动
        ↑
ObjCDeclarationRendering    ObjC*Info → SemanticString
        ↑
ObjCIndexing                索引 + 继承/遵守反向表
        ↑
ObjCInterface               strip 过滤 + 渲染编排入口
```

命名与 Swift 侧对齐（`SwiftDeclarationRendering` / `SwiftIndexing` / `SwiftInterface`），
下一轮加 CLI 时 `objc-section` 直接依赖 `ObjCInterface`。

新增包依赖：`swift-semantic-string`（`Semantic` + `OutputTransformer`）、
`MachOExtensions`、`swift-collections`。三者 MachOSwiftSection 均已依赖，
对下游不增加新的依赖负担。

`@Mutex` / `uppercasedFirst` / `orEmpty` / `removingAll` / `offsetEnumerated` 在
`ObjCIndexing` 的内部工具文件里自行实现（合计约 60 行），不引入 `FrameworkToolbox` 宏包。
注意平台底线是 macOS 10.15，用不了 `Synchronization.Mutex`（需 macOS 15），
锁要自己封 `os_unfair_lock` / `pthread_mutex`，并给非 Darwin 平台留分支。

### 四、RuntimeViewerCore 改为引用

删除本地副本，改 import。`RuntimeObjCSection` 退化为薄翻译层：
把 `ObjCInterface` 的产物包装成 `RuntimeObject` / `RuntimeObjectInterface`，
把 `ObjCIndexing` 的进度事件适配成 `RuntimeObjectsLoadingEvent`。

### 非目标

下面前两条已拆为 [0002](0002-objc-machofile-genericization-and-cli.md)，是确定要做的后续工作，
不是搁置。

- **不做 `objc-section` CLI**。它依赖下一条，见 0002。
- **不把索引层泛型化到 `MachOFile`**。现有实现只吃 `MachOImage`（进程内已加载镜像）；
  CLI 要读磁盘文件就必须泛型化。`MachOObjCSectionRepresentable` 已经为此铺好了路
  （`MachOFile` 与 `MachOImage` 均已符合），但 `info(in:)` / `name(in:)` / `superClass(in:)`
  目前是 `MachOFile` / `MachOImage` 两组并列重载而非泛型 requirement，需要新增一层
  shim 协议来收敛。这是独立且不小的工作量。
- **不删除 `Sources/MachOObjCSection/Extension/` 里与 `MachOExtensions` 重复的代码**。
  抽包让去重成为可能，但那些是上游文件，动它们会让每次上游合并都产生冲突。
  去重单独提案，并且应当先想清楚"改动上游文件"这件事在 fork 里的长期成本。
- **不抽 `MachOFoundation` 全栈**（`MachOReading` / `MachOPointers` / `MachOSymbols` /
  `MachOResolving` / `MachOSymbolPointers`）。本轮用不到，且 MachOSwiftSection 伤面过大。
- **不动 `MachOObjCSectionRepresentable` 的父类型**。即便 `MachOExtensions` 抽出后
  `MachORepresentableWithCache` 已经可用，把协议父类型换掉是破坏性改动，
  且属于上游文件，同样受 fork 约束。

## 详细设计

### `ObjCDeclarationRendering`

`ObjCDumpContext` 改名为 `ObjCRenderingContext`（`Dump` 与 `ObjCDump` 包重名易混），
并解除对 `Transformer` 的直接依赖，改为接收纯数据：

```swift
public final class ObjCRenderingContext {
    public var options: ObjCGenerationOptions
    public var cTypeReplacements: [ObjCPrimitiveTypePattern: String]
    public var ivarOffsetCommentBuilder: (@Sendable (Int) -> String)?
    public var isExpandHandler: @Sendable (_ name: String?, _ isStruct: Bool) -> Bool
    // …
}
```

`ObjCPrimitiveTypePattern` 是本地定义的枚举（`.char` / `.uchar` / `.int` / `.longLong` / …），
与 `Transformer.CType.Pattern` 同形。调用方若在用 `Transformer.CType`，在调用点转一次即可。
这样渲染层不依赖 `OutputTransformer`，纯库使用者也不必了解模板机制。

渲染入口保持现有形态（`SemanticStringBuilder` 方法）：

```swift
extension ObjCClassInfo {
    public func semanticString(using context: ObjCRenderingContext) -> SemanticString
}
extension ObjCProtocolInfo {
    public func semanticString(using context: ObjCRenderingContext) -> SemanticString
}
extension ObjCCategoryInfo {
    public func semanticString(using context: ObjCRenderingContext) -> SemanticString
}
```

`MachOImage+AddressFormatting.swift` 整体迁入，`addressString(forOffset:)` 此时来自
新的 `MachOExtensions`，不再需要本地重写。

### `ObjCIndexing`

`RuntimeObjCInterfaceIndexer` 改名 `ObjCInterfaceIndexer`，去掉 `Runtime` 前缀
（不再属于 RuntimeViewer）。进度事件从 RuntimeViewer 的
`AsyncThrowingStream<RuntimeObjectsLoadingEvent, Error>.Continuation` 换成本地类型：

```swift
public enum ObjCIndexingEvent: Sendable {
    case progress(phase: Phase, itemDescription: String, currentCount: Int, totalCount: Int)
    case subclassIndexed(className: String, superclass: String, imagePath: String)
    case conformanceIndexed(className: String, protocolName: String, imagePath: String)
    case categoryConformanceIndexed(targetClassName: String, protocolName: String, imagePath: String)

    public enum Phase: Sendable {
        case indexingSubclasses, loadingClasses, loadingProtocols
        case indexingConformances, loadingCategories
    }
}

public final class ObjCInterfaceIndexer: @unchecked Sendable {
    public init(machO: MachOImage, imagePath: String)
    public func prepare(eventHandler: (@Sendable (ObjCIndexingEvent) -> Void)? = nil) async throws
    // 查询接口维持原样
}
```

现有的 `RuntimeObjCInterfaceEvents` 与 `progressContinuation` 两条并行的事件通道合并成
这一条。RuntimeViewer 在外面把 `ObjCIndexingEvent` 适配回 `RuntimeObjectsLoadingEvent`。

### `ObjCInterface`

承接 `RuntimeObjCSection.interface(for:using:transformer:)` 里的 strip 过滤，
剥掉 `RuntimeObject` 包装：

```swift
public struct ObjCInterfaceBuilder: Sendable {
    public init(indexer: ObjCInterfaceIndexer, machO: MachOImage)

    public func classInterface(
        named name: String,
        options: ObjCGenerationOptions,
        cTypeReplacements: [ObjCPrimitiveTypePattern: String] = [:],
        ivarOffsetCommentBuilder: (@Sendable (Int) -> String)? = nil
    ) -> SemanticString?

    public func protocolInterface(named name: String, options: ObjCGenerationOptions, …) -> SemanticString?
    public func categoryInterface(uniqueName: String, options: ObjCGenerationOptions, …) -> SemanticString?
    public func structInterface(named name: String, …) -> SemanticString?
    public func unionInterface(named name: String, …) -> SemanticString?
}
```

`ObjCGenerationOptions` 从 RuntimeViewerCore 迁入本 target，十个开关原样保留，
去掉 `MetaCodable` 宏改为手写 `Codable`。

## 替代方案考量

### 把 ObjC 渲染 / 索引放进 MachOSwiftSection

基础设施全是现成的（`Semantic`、`MachOExtensions`、`OutputTransformer`、快照测试、CLI 骨架），
零循环依赖问题，`swift-section` 直接加一个 `objc` 子命令即可。

**否决理由**：仓库名与内容严重不符，ObjC 能力从此绑死在 Swift 仓库里；
MachOObjCSection 作为一个独立发布的库，仍然只能解析不能渲染。

### 只抽 `MachOExtensions` 中两库共用的子集

只抽地址计算、segment/section 定位、bind/rebase 解析、`LoadCommands` 便捷访问四块，
约 30 个符号，公开面比 53 个小。

**否决理由**：MachOSwiftSection 里会剩下一个残余的 `MachOExtensions` target，等于凭空多一个模块；
省下的 23 个符号不值这个复杂度。

### 不抽包，在 MachOObjCSection 里自行实现 `address(forOffset:)`

只有约 15 行，是本提案最初的方案。

**否决理由**：治标。`MachOExtensions` 与 MachOObjCSection 的 `Extension/` 已经实质重复
（见前期调研），继续各写各的只会让重复越积越多；且日后 ObjC 侧要做符号解析、指针追踪时，
同样的环会再撞一次。

### `OutputTransformer` 单独立包

新建 `swift-output-transformer`。

**否决理由**：它与 `Semantic` 是同一条渲染管线的相邻两环，`CType` 直接吃吐 `SemanticString`，
分成两个仓库要为一条天然的依赖边维护两套版本号与 CI。并进 `swift-semantic-string`
做独立 target / product，既避免新仓库，又保住"不想要模板引擎的人不用拉"。
代价是包名 `swift-semantic-string` 装 `OutputTransformer` 略不搭，在 README 里
把仓库定位重述为"渲染输出的语义化与后处理"即可。

### 把 `OutputTransformer` 并进 `Semantic` target 本身

**否决理由**：`SwiftEnumLayout`、`SwiftVTableOffset` 这些 token 名字带着强烈的 Swift 运行时
元数据语义（`bitsNeededForTag`、`payloadRegionBytesHex`）。类型上虽已解耦，语义上只对
MachOSwiftSection 有意义，塞进通用的 `Semantic` 会让它携带不属于自己的领域词汇表。

### 本轮一并做 `MachOFile` 泛型化与 CLI

**否决理由**：范围过大，且泛型化要新增 shim 协议来收敛 `MachOFile` / `MachOImage` 双重载，
是独立且不小的工作量。先把搬运做完、让 RuntimeViewer 切过去跑通，能立刻验证搬运本身是否正确；
泛型化建立在一份已经能跑的库代码上，比一次性做完更容易定位问题。

## 影响

### 源码兼容性（source compatibility）

**MachOObjCSection：纯新增。** 现有 `MachOObjCSection` target 一行不改，
三个新 target 是新增 product，既有调用点不受影响。

**`swift-semantic-string`：纯新增。** `Semantic` target 不变，新增一个 product。

**`MachOExtensions`：对 MachOSwiftSection 无源码破坏。** product 名与 target 名
均保持 `MachOExtensions`，`import MachOExtensions` 不变；53 个符号由 `package` 提升为
`public` 是放宽而非收紧，不破坏任何现有调用点。

**RuntimeViewerCore：有破坏，但都在本仓库内。** 涉及的重命名：

| 改前 | 改后 |
|---|---|
| `ObjCDumpContext` | `ObjCRenderingContext` |
| `RuntimeObjCInterfaceIndexer` | `ObjCInterfaceIndexer` |
| `RuntimeObjCInterfaceEvents.Event` | `ObjCIndexingEvent` |
| `Transformer.CType.Pattern` | `ObjCPrimitiveTypePattern`（渲染层入口处） |

这些类型目前都不是 RuntimeViewerCore 的 public API 表面（`ObjCDumpContext` 是
`internal final class`，indexer 的构造器是 `internal`），改名不外溢。
`Transformer.*` 是 public，但只是从 RuntimeViewerCore 换成从 `OutputTransformer` 导出，
`@_exported import` 已经在做同样的事，调用点无感。

### ABI 兼容性

不适用 —— 所有涉及的包均以 SPM 源码分发，未开启 library evolution，也无 `binaryTarget`，
使用方每次重新编译。

### 下游影响

**本仓库内**：`MachOObjCSection` target 不受影响；新增三个 target 与对应 product。

**跨仓库**：

- `MachOExtensions`（新）→ `MachOSwiftSection`、`MachOObjCSection`
- `swift-semantic-string` → `MachOSwiftSection`、`MachOObjCSection`（新）、`RuntimeViewer`
- `MachOObjCSection` → `MachOSwiftSection`（13 个 target 依赖它）、`RuntimeViewer`、`MachOKitUI`
- `MachOSwiftSection` → `RuntimeViewer`

`MachOSwiftSection` 需同步一次 `Package.swift`（换 `MachOExtensions` 与
`OutputTransformer` 的来源），源码零改动。
`MachOKitUI` 依赖 MachOObjCSection，但本提案对既有 target 无改动，不受影响。

**上游 fork 传导**：`Package.swift` 的改动会与上游合并冲突，但该文件早已 fork 化，
冲突处理已是既有流程的一部分。`Sources/MachOObjCSection/` 下不新增、不修改任何文件。

### 文档与示例

- `README.md`（英文）：新增三个 product 的说明与最小示例；
- 新建 `Documentations/README.md` 作为文档索引（本仓库此前没有 `Documentations/`）；
- `swift-semantic-string` 的 README 需重述仓库定位并说明新 product；
- `MachOExtensions` 需要一份 README 说明它从何而来、为什么独立。

## API 演进与废弃策略

- 本轮为纯新增，无 API 被替代，不需要 `@available(*, deprecated)`。
- `MachOExtensions` 首个 tag 建议 `0.1.0`；抽包后 `MachOExtensions` 首次拥有真正的
  对外契约，53 个新 `public` 符号中有一部分（`LocatableLayoutWrapper`、`RequiredNonOptional`
  等实现细节）未必想长期承诺，落地时应逐个过一遍，确认不想承诺的改标 `@_spi` 而非 `public`。
- `swift-semantic-string` 新增 product，minor 版本递增至 `0.3.0`。
- MachOObjCSection 新增 product，按 fork 编号规则递增（`0.8.10x`）。
- 均无需 semver major 跃迁。

## 落地步骤

1. **抽 `MachOExtensions`**：新建仓库，迁入 19 个文件，53 个符号提 `public`，
   3 处 `@AssociatedObject` 换成非 ObjC-runtime 实现，平台列表加 Linux。
   验收：新包在 macOS 与 Linux 上均 `swift build` 通过。
2. **MachOSwiftSection 换源**：删 `MachOExtensions` target 定义，加包依赖，
   13 处 `.target(.MachOExtensions)` 换成 `.product(...)`。源码零改动。
   验收：`swift build` 与既有测试全绿。
3. **`OutputTransformer` 迁入 `swift-semantic-string`**：新增 target 与 product，
   从 MachOSwiftSection 迁出 6 个文件，从 RuntimeViewerCore 迁入 3 个 ObjC 侧文件，
   `MetaCodable` 换手写 `Codable`。MachOSwiftSection 与 RuntimeViewer 同步换源。
   验收：三方 `swift build` 通过，`Transformer` 的既有测试（`TransformerTests`）全绿。
4. **MachOObjCSection 加 `ObjCDeclarationRendering`**：迁入渲染器与地址格式化，
   `ObjCDumpContext` → `ObjCRenderingContext`，解除 `Transformer` 直接依赖。
   验收：能对一个真实二进制渲染出 `@interface`，与 RuntimeViewer 现有输出逐字符一致。
5. **加 `ObjCIndexing`**：迁入索引器，事件通道统一，自实现锁与小工具。
   验收：索引结果（类 / 协议 / 分类 / struct / union 数量与反向表内容）与迁移前一致。
6. **加 `ObjCInterface`**：迁入 strip 逻辑与 `ObjCGenerationOptions`。
   验收：十个开关逐个开关，输出与 RuntimeViewer 现有输出一致。
7. **RuntimeViewerCore 切换**：删本地副本，改 import，`RuntimeObjCSection` 退化为翻译层。
   验收：RuntimeViewer 构建通过，`GenerationOptionsTests` / `TransformerTests` 全绿，
   手工比对若干个类的界面输出。
8. **文档收尾**：README、文档索引、新仓库 README。

第 1–3 步与第 4–6 步之间有硬依赖；第 4、5、6 步内部严格递进。每一步都能独立构建通过。

**收尾时必须判断两件事**（结论写进决策日志）：

- 要不要配套专题文章 —— 候选是一份实现说明，记录"为什么 fork 里不去重"
  以及"为什么渲染层不直接依赖 `OutputTransformer`"这两个从代码看不出来的决策。
- 有没有引入新术语 —— 候选：`ObjCRenderingContext`、`ObjCPrimitiveTypePattern`、
  以及 `Transformer.Module` 的"token 模板"概念。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-08-09 | Created as Draft | 起因是把 RuntimeViewerCore 的 `ObjCDump+SemanticString.swift` 与 `RuntimeObjCInterfaceIndexer.swift` 搬进 MachOObjCSection；调研中发现两者带着对 MachOSwiftSection 的循环依赖，遂扩展为连带抽出公共底座 |
| 2026-08-09 | 落点定为 MachOObjCSection | 备选是放进 MachOSwiftSection（基础设施现成）或先抽公共底座再搬。选前者以保住职责对称，代价是要自行解开循环依赖 |
| 2026-08-09 | 范围限定为渲染 + 索引 | CLI 与 `MachOFile` 泛型化拆到后续提案，先让搬运本身可验证 |
| 2026-08-09 | `MachOExtensions` 整包抽出，保住 Linux | 备选是只抽共用子集（省 23 个符号但多一个残余 target）或抽整个 `MachOFoundation` 栈（本轮用不到）。Linux 选择适配而非放弃，否则 MachOObjCSection 现有能力会退化 |
| 2026-08-09 | `OutputTransformer` 并入 `swift-semantic-string` 而非独立立包 | 查证其 `Input` 已与领域类型完全解耦、`CType` 直接吃吐 `SemanticString`，与 `Semantic` 是相邻两环。做独立 target / product 而非并进 `Semantic`，避免通用包携带 Swift 元数据词汇表 |
| 2026-08-09 | 新仓库定名 `MachOExtensions` | 仓库名与 target 名一致，沿用 MachO 系仓库的 PascalCase 惯例；起初拟名 `swift-macho-extensions`，与 `MachOKit` / `MachOObjCSection` / `MachOSwiftSection` 的既有命名不符，已改 |
| 2026-08-09 | `ObjCTypeDecodeKit` 无需上游改动 | 起初误判为需要在 `swift-objc-dump` 补一个 product。查证后确认：依赖 `ObjCDump` product 即可直接 `import ObjCTypeDecodeKit`，`RuntimeViewerCore` 现成代码已在这么用。前置阻塞项撤销 |
| 2026-08-09 | 去重降级为非目标 | 发现本仓库是 `p-x9/MachOObjCSection` 的 fork 且仍在合并上游 tag，改动 `Sources/MachOObjCSection/` 下的上游文件会让每次合并产生冲突。抽包仍做，因为它同时解开循环依赖并统一 MachOSwiftSection 侧的维护 |
