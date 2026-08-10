# 0002 - ObjC 索引层泛型化到 MachOFile，并提供 objc-section CLI

- **状态**: Draft
- **作者**: JH
- **创建日期**: 2026-08-09
- **最后更新**: 2026-08-09
- **所属愿景**: 无
- **关联提案**: [0001](0001-objc-rendering-and-indexing-downstreaming.md)（前置，必须先落地）
- **实现分支 / PR**: 待定
- **配套文档**: 待定 —— 落地时登记实现说明 / 使用指南的链接

## 摘要

把 0001 建立的 `ObjCIndexing` / `ObjCInterface` 从只吃 `MachOImage`（进程内已加载镜像）
泛型化到同时支持 `MachOFile`（磁盘上的二进制），做法是新增一个 `ObjCMetadataSource`
shim 协议，把现有的 `MachOFile` / `MachOImage` 两组并列重载收敛成单一泛型入口。

在此基础上新增可执行 target `objc-section`，对标 `swift-section`，提供 `dump` 与
`interface` 两个子命令，并补一套快照测试。

全部改动为**纯新增**：不修改 `Sources/MachOObjCSection/` 下任何既有文件，
因此不增加 fork 与上游合并的冲突面。

## 动机

0001 落地后，MachOObjCSection 能渲染 ObjC 声明了，但只能渲染**当前进程已经加载的镜像**。
`ObjCInterfaceIndexer.init(machO: MachOImage, imagePath: String)` 这个签名把能力锁死在
`dlopen` 得到的东西上，直接后果是下面这些场景一个都做不了：

- **分析别的架构**。手上一个 arm64e 的 dylib，在 x86_64 机器上无法加载，也就无法分析。
- **分析别的平台**。iOS / watchOS 的二进制在 macOS 上加载不了。
- **分析 dyld shared cache 里的镜像而不加载它**。cache 里有上千个镜像，为了看一个类的
  接口去把整个框架加载进当前进程，代价与副作用都不可接受。
- **分析根本加载不了的二进制**。签名不匹配、依赖缺失、故意损坏的样本。
- **任何非 GUI 的自动化**。CI 里跑接口 diff、批量导出头文件、生成 API 快照——这些都要求
  离线读文件，不能要求先把目标加载进进程。

最后一条就是 CLI 缺失的根源。MachOSwiftSection 的 `swift-section` 从第一天起就是
`MachOFile.load(options:)` 起手（`Sources/swift-section/Commands/DumpCommand.swift:87`），
所以它能 dump 任意架构、任意平台、cache 内外的二进制。ObjC 一侧因为索引层只认 `MachOImage`，
连 CLI 的第一行都写不出来。

换句话说：**泛型化不是 CLI 的一个前置优化，它就是 CLI 本身**。这也是本提案把两件事
放在一起、而不是拆成两篇的原因。

## 前期调研

### 现有的双重载分布

MachOObjCSection 的解析层对 `MachOFile` 与 `MachOImage` 一视同仁，但表达方式是**两组并列的
具名重载**，而非一个泛型 requirement。`Sources/MachOObjCSection/Protocol/Class/ObjCClassProtocol.swift:26-40`：

```swift
func metaClass(in machO: MachOFile) -> (MachOFile, Self)?
func superClass(in machO: MachOFile) -> (MachOFile, Self)?
func superClassName(in machO: MachOFile) -> String?
func classROData(in machO: MachOFile) -> ClassROData?

func hasRWPointer(in machO: MachOImage) -> Bool

func metaClass(in machO: MachOImage) -> (MachOImage, Self)?
func superClass(in machO: MachOImage) -> (MachOImage, Self)?
func superClassName(in machO: MachOImage) -> String?
func classROData(in machO: MachOImage) -> ClassROData?
func classRWData(in machO: MachOImage) -> ClassRWData?

func version(in machO: MachOFile) -> Int32
func version(in machO: MachOImage) -> Int32
```

`Support/ObjCDump.swift` 里的 `info(in:)` 同样成对出现：

| 类型 | `MachOFile` 版 | `MachOImage` 版 |
|---|---|---|
| `ObjCIvarProtocol.info` | :114 | :127 |
| `ObjCProtocolProtocol.info` | :170 | :226 |
| `ObjCClassProtocol.info` | :399 | :526 |
| `ObjCCategoryProtocol.info` | :608 | :656 |

泛型代码无法同时调到这两组：`func f<MachO: MachOObjCSectionRepresentable>(machO: MachO)`
里写 `objcClass.info(in: machO)` 不会编译，因为协议里没有以 `Self` 为参数的 requirement。

### 抽象基座已经就绪

`Sources/MachOObjCSection/Protocol/MachOObjCSectionRepresentable.swift` 已经把
「有 ObjC 段的 Mach-O」抽象出来，`MachOFile` 与 `MachOImage` 均已 conform：

```swift
public protocol MachOObjCSectionRepresentable: MachORepresentable {
    associatedtype ObjCSection: ObjCSectionRepresentable
    var objc: ObjCSection { get }
}
```

`ObjCSectionRepresentable` 覆盖了 `classes64/32`、`nonLazyClasses64/32`、`protocols64/32`、
`categories64/32`、`nonLazyCategories64/32`、`categories2_64/32`、`imageInfo`、`methods`。
**枚举各段这一步已经是泛型的**，缺的只是「拿到一条记录后怎么把它解成 `*Info`」。

### 语义上真正只属于 MachOImage 的部分

`classRWData(in:)` 与 `hasRWPointer(in:)` 只有 `MachOImage` 版本，这**不是遗漏而是正确的**：
RW data 是 ObjC runtime 在 realize class 时才写入的，磁盘上的文件里不存在。
泛型接口不应该假装它存在——这部分保持在 `MachOImage` 专属路径上。

`RuntimeObjCInterfaceIndexer` 现有实现没有用到 `classRWData` / `hasRWPointer`
（只用 `info(in:)` / `name(in:)` / `superClass(in:)` / `isSwiftStable`），
因此泛型化不会丢能力。

### 唯一的缺口：`name(in: MachOFile)`

`ObjCClassProtocol.name(in:)` 只有 `MachOImage` 版本
（`Support/ObjCDump.swift:483`，实现是 `data(in: machO)?.data.name(in: machO)`）。

但 `ObjCClassRODataProtocol.name(in: MachOFile)` 是存在的
（`Protocol/Class/RO/ObjCClassRODataProtocol.swift:89`），所以缺的那一半可以在**新文件**里补出来：

```swift
extension ObjCClassProtocol {
    public func name(in machO: MachOFile) -> String? {
        classROData(in: machO)?.name(in: machO)
    }
}
```

这一点决定了整个提案的风险等级：**不需要修改任何上游文件**。

其余需要泛型化的类型（`ObjCCategoryProtocol.name`、`ObjCIvarProtocol.name`）两版都齐全
（`ObjCCategoryProtocol.swift:28/38`、`ObjCIvarProtocol.swift:24/28`）。

### 地址注释在文件模式下的语义

0001 迁入的 `impAddressComment(label:rawValue:)` 用 `MachOImage.ptr` 作基址计算
IMP 的虚拟地址。文件模式下没有 `ptr`，必须改用 `MachOKitExtensions` 的
`address(forOffset:)`（`MachORepresentableWithCache.swift:118-127`），
它已经分别处理了三种情形：

- 已加载镜像且来自 cache —— 用 `ptr - slide`；
- 未加载但来自 cache —— 用 `sharedRegionStart + offset`；
- 独立文件 —— 用 `__TEXT` 段的 `virtualMemoryAddress + offset`。

这正是 0001 把 `MachOKitExtensions` 抽成独立包所换来的直接收益：泛型化时不必再为
文件模式重写一套地址计算。

### `swift-section` CLI 的结构（对标对象）

| 文件 | 行数 | 作用 |
|---|---:|---|
| `SwiftSectionCommand.swift` | 18 | `@main`，挂 6 个子命令，默认 `dump` |
| `Commands/DumpCommand.swift` | 311 | 主命令 |
| `Commands/InterfaceCommand.swift` | 109 | 单个声明的接口输出 |
| `Commands/DiffCommand.swift` | 233 | 两个二进制的接口 diff |
| `Commands/SnapshotCommand.swift` | 53 | ABI 快照 |
| `Commands/EvolutionCommand.swift` | 115 | ABI 演进比对 |
| `Commands/TransformerCommand.swift` | 275 | 注释模板管理 |
| `Models/MachOOptionGroup.swift` | 21 | 输入选项组，见下 |
| `Models/Architecture.swift` | 33 | 架构选择 |
| `Models/SemanticColorScheme.swift` | 7 | 着色方案 |
| `Models/TransformerOptionGroup.swift` | 313 | 注释模板选项组 |

`MachOOptionGroup` 是可以直接照搬的部分：

```swift
@Argument var filePath: String?
@Option(name: [.long, .customShort("p")]) var cacheImagePath: String?
@Option(name: [.long, .customShort("n")]) var cacheImageName: String?
@Flag(name: [.customLong("dyld-shared-cache")]) var isDyldSharedCache: Bool
@Flag var usesSystemDyldSharedCache: Bool
@Option(name: .shortAndLong) var architecture: Architecture?
```

依赖 `swift-argument-parser` 与 `Rainbow`（着色），两者 MachOSwiftSection 已在用。

## 提议方案

### 一、`ObjCMetadataSource` shim 协议

在新 target `ObjCMetadataSource` 里定义（也可并入 `ObjCIndexing`，见替代方案），
把双重载收敛成以 `Self` 为参数的泛型 requirement：

```swift
public protocol ObjCMetadataSource: MachOObjCSectionRepresentable {
    func objcClassInfo<Class: ObjCClassProtocol>(of objcClass: Class, options: ObjCInfoOptions) -> ObjCClassInfo?
    func objcClassName<Class: ObjCClassProtocol>(of objcClass: Class) -> String?
    func objcSuperClass<Class: ObjCClassProtocol>(of objcClass: Class) -> (Self, Class)?

    func objcProtocolInfo<Protocol: ObjCProtocolProtocol>(of objcProtocol: Protocol, options: ObjCProtocolInfoOptions) -> ObjCProtocolInfo?
    func objcCategoryInfo<Category: ObjCCategoryProtocol>(of objcCategory: Category, options: ObjCInfoOptions) -> ObjCCategoryInfo?
    func objcCategoryTargetClass<Category: ObjCCategoryProtocol>(of objcCategory: Category) -> (Self, Category.ObjCClass)?

    /// IMP 地址的解析基址；文件模式与镜像模式的算法不同。
    func objcResolvedAddress(forOffset offset: Int) -> UInt64
}

extension MachOFile: ObjCMetadataSource { /* 转发到既有的 MachOFile 重载 */ }
extension MachOImage: ObjCMetadataSource { /* 转发到既有的 MachOImage 重载 */ }
```

两个 conformance 都是纯转发，加上前述 `name(in: MachOFile)` 的补齐，合计约 120 行，
全部写在新文件里。

### 二、泛型化 `ObjCIndexing` 与 `ObjCInterface`

```swift
public final class ObjCInterfaceIndexer<MachO: ObjCMetadataSource>: @unchecked Sendable {
    public init(machO: MachO, imagePath: String)
    public func prepare(eventHandler: (@Sendable (ObjCIndexingEvent) -> Void)? = nil) async throws
    // 查询接口不变
}

public struct ObjCInterfaceBuilder<MachO: ObjCMetadataSource>: Sendable {
    public init(indexer: ObjCInterfaceIndexer<MachO>, machO: MachO)
    // 入口签名不变
}
```

`ObjCRenderingContext` 里的 `machO: MachOImage` 同步泛型化，
`impAddressComment` 改走 `objcResolvedAddress(forOffset:)`。

跨镜像的超类解析（`infoWithSuperclasses`）在文件模式下的行为与镜像模式不同：
`MachOFile.superClass(in:)` 只能在同一个 cache 内跨镜像走，独立文件里的超类若来自
别的二进制就解析不到，此时超类链在该处截断。这是文件模式的固有限制，
`stripOverrides` 在这种情况下会少剥一些成员——需在文档里写明，不做隐藏。

### 三、`objc-section` CLI

```
objc-section dump <file>          导出整个二进制的 ObjC 声明
objc-section interface <file>     导出单个类 / 协议 / 分类的接口
```

`dump` 的选项：

- **输入**：照搬 `MachOOptionGroup`（文件路径、cache 镜像路径 / 名称、
  `--dyld-shared-cache`、`--uses-system-dyld-shared-cache`、`--architecture`）；
- **筛选**：`--sections classes protocols categories structs unions`；
  `--filter <pattern>` 按名字过滤；
- **生成开关**：`ObjCGenerationOptions` 的十项各对应一个 flag
  （`--strip-protocol-conformance`、`--strip-overrides`、`--strip-synthesized-ivars`、
  `--strip-synthesized-methods`、`--strip-ctor-method`、`--strip-dtor-method`、
  `--emit-ivar-offsets`、`--emit-property-attributes`、`--emit-method-imp-addresses`、
  `--emit-property-accessor-addresses`）；
- **注释模板**：`--c-type-replacement double=CGFloat`（可重复）、`--ivar-offset-template`；
- **输出**：`--output-path`、`--color-scheme`。

`interface` 额外接一个声明名参数（类名 / 协议名 / `Class(Category)`）。

### 四、快照测试

新增 `ObjCSectionCommandTests`，对若干个固定的系统二进制跑 `dump`，
用 `swift-snapshot-testing` 固化输出。对标 MachOSwiftSection 的
`SwiftSectionCommandTests`（`Package.swift:895-903`）。

### 非目标

- **不做 `diff` / `snapshot` / `evolution` 子命令**。ObjC 一侧目前没有 ABI 快照的需求，
  且这三个在 Swift 侧都建立在 `SwiftDiffing` / `SwiftInterface` 之上，ObjC 侧对应的
  模块还不存在。等有实际需求再提。
- **不做 `TransformerCommand`**（模板的交互式管理）。ObjC 侧只有两个模板模块
  （`CType`、`ObjCIvarOffset`），用两个普通选项就够，不值得上一套 275 行的子命令。
- **不暴露 `classRWData` / `hasRWPointer` 到泛型接口**。它们语义上只存在于已加载镜像，
  泛型化会制造「文件模式下永远返回 nil」的假接口。需要它们的调用方继续走
  `MachOImage` 专属路径。
- **不修改 `Sources/MachOObjCSection/` 下的既有文件**。所有补齐都以扩展形式写在新文件里，
  理由与 0001 相同（fork 与上游合并）。
- **不实现「文件模式下跨二进制解析超类」**。需要一套镜像搜索与依赖解析机制，
  远超本提案范围；截断行为写进文档。

## 详细设计

### `ObjCMetadataSource` 的两个 conformance

```swift
extension MachOFile: ObjCMetadataSource {
    public func objcClassInfo<Class: ObjCClassProtocol>(
        of objcClass: Class,
        options: ObjCInfoOptions = .recursive
    ) -> ObjCClassInfo? {
        objcClass.info(in: self, options: options)
    }

    public func objcClassName<Class: ObjCClassProtocol>(of objcClass: Class) -> String? {
        objcClass.classROData(in: self)?.name(in: self)
    }

    public func objcSuperClass<Class: ObjCClassProtocol>(of objcClass: Class) -> (MachOFile, Class)? {
        objcClass.superClass(in: self)
    }

    public func objcResolvedAddress(forOffset offset: Int) -> UInt64 {
        address(forOffset: offset)   // 来自 MachOKitExtensions
    }
    // 其余同理
}
```

`MachOImage` 侧完全对称，`objcClassName` 直接转发既有的 `name(in: MachOImage)`。

### CLI 的 `dump` 主流程

```swift
mutating func run() async throws {
    let machOFile = try MachOFile.load(options: machOOptions)
    let indexer = ObjCInterfaceIndexer(machO: machOFile, imagePath: machOOptions.filePath ?? "")
    try await indexer.prepare()

    let builder = ObjCInterfaceBuilder(indexer: indexer, machO: machOFile)
    let options = generationOptions.build()

    for name in indexer.classNames.sorted() where matchesFilter(name) {
        guard let interface = builder.classInterface(
            named: name,
            options: options,
            cTypeReplacements: transformerOptions.cTypeReplacements,
            ivarOffsetCommentBuilder: transformerOptions.ivarOffsetCommentBuilder
        ) else { continue }
        emit(interface.string(with: colorScheme))
    }
    // protocols / categories / structs / unions 同理
}
```

`MachOFile.load(options:)` 需要在 `objc-section` 里重新实现一份——它现在是
`swift-section` 的私有扩展（`Sources/swift-section/Utilities/Extensions.swift`），
不在任何 product 里。约 40 行，照搬即可；若日后两个 CLI 的输入处理继续趋同，
再考虑把它下沉到 `MachOKitExtensions`。

## 替代方案考量

### 把 `ObjCMetadataSource` 直接加进 `MachOObjCSection` 核心 target

技术上更自然——抽象应该和被抽象的东西住在一起。

**否决理由**：核心 target 是上游文件的领地，新增文件虽然不直接冲突，
但会让「这个目录里哪些是 fork 加的」变得模糊，日后上游若自己加了同名抽象会撞车。
放在新 target 里，边界清晰，且随时可以在上游接受同等抽象后原样删掉。

### 用两份非泛型实现（`ObjCFileIndexer` + `ObjCImageIndexer`）

不引入 shim 协议，直接把索引器复制成两份，各自吃一种输入。

**否决理由**：639 行的索引逻辑复制两份，此后每个 bug 要修两遍。
shim 协议的成本只有约 120 行的纯转发代码，一次性付清。

### 在 `MachOObjCSectionRepresentable` 上直接加泛型 requirement

改现有协议，让 `MachOFile` / `MachOImage` 提供以 `Self` 为参数的方法。

**否决理由**：`MachOObjCSectionRepresentable` 是上游文件，改它就是改上游文件；
且这会让所有既有 conformer 被迫实现新 requirement，是破坏性改动。

### 先只做泛型化，CLI 再拆一篇

**否决理由**：泛型化本身没有可交付的用户价值，它的唯一目的就是让 CLI 成为可能。
拆开会让第一篇变成一个无法独立验证的纯重构——CLI 恰恰是验证泛型化是否真的够用的
最好手段（能对一个从没加载过的 iOS 二进制 dump 出正确的头，就说明泛型化成立）。

### 复用 `swift-section`，加一个 `objc` 子命令

`swift-section objc dump ...`。基础设施全现成，`MachOOptionGroup` / `Architecture` /
`SemanticColorScheme` 一行都不用写。

**否决理由**：MachOObjCSection 是可以独立使用的库，它的 CLI 不该住在 MachOSwiftSection 里
（依赖方向也不允许——MachOSwiftSection 依赖 MachOObjCSection）。
用户只想 dump ObjC 头时不该被迫装一个 Swift 反射工具。

## 影响

### 源码兼容性（source compatibility）

**纯新增，且不修改任何既有文件。** 新增一个 `ObjCMetadataSource` target、
一个 `objc-section` executable target，以及若干补齐用的扩展文件。

唯一的形式变化是 0001 引入的两个类型获得泛型参数：

| 改前（0001） | 改后（0002） |
|---|---|
| `ObjCInterfaceIndexer` | `ObjCInterfaceIndexer<MachO: ObjCMetadataSource>` |
| `ObjCInterfaceBuilder` | `ObjCInterfaceBuilder<MachO: ObjCMetadataSource>` |

由于泛型参数可由构造器实参推断，`ObjCInterfaceIndexer(machO: image, imagePath: path)`
这样的调用点无需改写。若 0001 与 0002 在同一个发布周期内落地，
对外根本不存在「非泛型版本」，这一栏可视为无影响。

`ObjCClassProtocol.name(in: MachOFile)` 是新增重载，不与既有 `name(in: MachOImage)` 冲突。

### ABI 兼容性

不适用 —— 以 SPM 源码分发，未开启 library evolution，无 `binaryTarget`。

### 下游影响

- **新增依赖**：`swift-argument-parser`、`Rainbow`（仅 `objc-section` executable target 需要，
  库 target 不受影响）；`swift-snapshot-testing`（仅测试 target）。
  三者 MachOSwiftSection 均已在用。
- **`MachOSwiftSection`**：不受影响。它消费的是库 product，不是 CLI。
- **`RuntimeViewer`**：不受影响。它继续走 `MachOImage` 路径，泛型参数由实参推断。
- **`MachOKitUI`**：不受影响。
- **上游 fork**：仅新增目录与 `Package.swift` 改动，与 0001 同级的低风险。

### 文档与示例

- `README.md`（英文）：新增 CLI 的安装与用法章节，附 `dump` / `interface` 的实例输出；
- 需要一份使用指南（`Documentations/Guides/`），至少覆盖两条从 API 签名看不出来的契约：
  文件模式下超类链会在跨二进制处截断，以及 `classRWData` / `hasRWPointer`
  不在泛型接口上、需要走 `MachOImage` 专属路径；
- `Documentations/README.md` 与 `Evolutions/README.md` 同步登记。

## API 演进与废弃策略

- 纯新增，无 API 被替代，不需要 `@available(*, deprecated)`。
- `ObjCMetadataSource` 是本提案唯一新增的公开协议。它的 requirement 集合日后若要扩充
  （例如加入 `objcMethodInfo`），对外部 conformer 是破坏性的；但预期的 conformer 只有
  `MachOFile` 与 `MachOImage` 两个，且都由本库提供，因此不额外做 `@_spi` 隔离，
  只在文档里注明「不建议外部类型 conform」。
- CLI 的命令行接口即用户契约：子命令名与 flag 名一经发布，重命名等同破坏性变更。
  第一版发布前应把十个生成开关的命名一次定好。
- 按 fork 编号规则递增（`0.8.10x`），无需 semver major 跃迁。

## 落地步骤

1. **补齐 `name(in: MachOFile)`**，新文件，纯扩展。
   验收：能对一个磁盘上的二进制取到类名。
2. **`ObjCMetadataSource` 协议与两个 conformance**，纯转发。
   验收：泛型函数 `func f<M: ObjCMetadataSource>(machO: M)` 能同时接受
   `MachOFile` 与 `MachOImage` 并取到 `ObjCClassInfo`。
3. **泛型化 `ObjCRenderingContext`**，`impAddressComment` 改走
   `objcResolvedAddress(forOffset:)`。
   验收：`MachOImage` 路径的渲染输出与 0001 落地时逐字符一致（回归保护）。
4. **泛型化 `ObjCIndexing`**。
   验收：同一个镜像分别以 `MachOFile` 与 `MachOImage` 索引，
   类 / 协议 / 分类数量一致；超类链在文件模式下的截断点符合预期。
5. **泛型化 `ObjCInterface`**。
   验收：十个生成开关逐个开关，两种模式输出一致（超类截断导致的
   `stripOverrides` 差异除外，需在测试里显式标注）。
6. **`objc-section` CLI**：`MachOOptionGroup` + `dump` 子命令。
   验收：能对一个从未加载过的 iOS 二进制 dump 出正确的头。
7. **`interface` 子命令 + 快照测试**。
   验收：快照全绿。
8. **文档收尾**：README、使用指南、索引。

第 1–5 步严格递进；第 6、7 步依赖前五步全部完成。每一步都能独立构建通过。

**收尾时必须判断两件事**（结论写进决策日志）：

- 要不要配套专题文章 —— 使用指南基本确定要写（两条隐藏契约，见「文档与示例」）；
  实现说明的候选是「为什么 shim 协议不放进核心 target」。
- 有没有引入新术语 —— 候选：`ObjCMetadataSource`、「文件模式 / 镜像模式」这对说法
  （下沉到术语表，避免后续文档各叫各的）。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-08-09 | Created as Draft | 从 0001 拆出。0001 讨论时曾将两者列为非目标并注明「留待后续提案」，本篇即该提案 |
| 2026-08-09 | 泛型化与 CLI 合为一篇 | 泛型化本身无可交付价值，唯一目的就是让 CLI 成为可能；且 CLI 是验证泛型化是否够用的最好手段。拆开会让第一篇变成无法独立验证的纯重构 |
| 2026-08-09 | 确认可做成纯新增 | 查证 `ObjCClassRODataProtocol.name(in: MachOFile)` 已存在，缺失的 `ObjCClassProtocol.name(in: MachOFile)` 可用它在新文件里补出。因此无需修改任何上游文件，fork 冲突风险与 0001 同级 |
| 2026-08-09 | `classRWData` / `hasRWPointer` 排除在泛型接口外 | 它们是 runtime realize class 后才存在的数据，磁盘文件里没有。泛型化会制造「文件模式下永远返回 nil」的假接口。查证现有索引器未使用它们，排除不丢能力 |
