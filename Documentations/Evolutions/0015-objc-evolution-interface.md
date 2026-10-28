# 0015 - 带演进标注的合并 ObjC 头文件

- **状态**: Implemented
- **创建日期**: 2026-10-28
- **最后更新**: 2026-10-29
- **实现分支**: `feature/objc-evolution-interface`
- **配套文档**: [使用指南的库调用方一节](../Guides/ObjCSectionCommandLine.md#库调用方把-n-个版本合并成一份带演进标注的头文件)；
  [术语表的 evolution interface](../Glossary.md#evolution-interface演进合并头文件)
- **关联**: MachOSwiftSection 的 `Documentations/Evolutions/draft-objc-evolution-interface.md`
  （`swift-section objc evolution --interface` 的 CLI、SwiftSectionKit 请求、集成测试与文档由那边做）；
  Swift 一侧的同一种视图是 MachOSwiftSection 提案 0013（Swift evolution interface）

## 摘要

`ObjCAPIEvolutionBuilder` 只给出逐条 lineage（每个声明一条存在位图加事件列表），读 AppKit 这种有几千个类的框架时看不出全貌。
本提案在库里加一个渲染器：把 N 个版本的头文件按声明合并成一份，外观与 `objc dump` 相同（有参数名、ivar 块、分组），
在有变化的类、协议、分类及其方法、属性、ivar 上标出存在位图，以及在哪一版加入、删除或修改，
可选地补上 `API_AVAILABLE` / `API_OBSOLETED`。每条标注都对应 `ObjCAPIEvolution` 里的一条 lineage。
宿主一次交一个版本的索引器，库渲染完就不再引用它，51 个版本的 AppKit 不必同时留在内存里。

## 方案

### 接口（`ObjCInterface` 模块）

```swift
public struct ObjCEvolutionInterfaceBuilder {
    public init(cTypeReplacements: [ObjCPrimitiveTypePattern: String] = [:])
    /// Renders every declaration of this version and takes its snapshot. Holds
    /// no reference to `indexer` or `machO` once it returns.
    public mutating func addVersion<MachO: ObjCMetadataSource>(
        indexer: ObjCInterfaceIndexer<MachO>,   // prepared; the host passes its suppliedClasses
        machO: MachO,
        version: ObjCAPIVersionDescriptor
    )
    /// Throws `ObjCAPIEvolutionError.fewerThanTwoVersions` below two versions.
    public func build(availabilityPlatform: String? = nil) throws -> ObjCEvolutionInterface
}

public struct ObjCEvolutionInterface: Sendable {
    public let evolution: ObjCAPIEvolution   // hasBreakingChange, for --fail-on-breaking
    public let interface: SemanticString     // the annotated, merged header
}
```

- 调用顺序就是版本轴，旧的在前。快照用 `ObjCAPISnapshotBuilder`（与 `objc snapshot` 同一个），演进由
  `ObjCAPIEvolutionBuilder` 算，所以标注不会和报告、JSON 对不上。
- 内存：留下每个版本的快照（现有的 `objc evolution` 也把各版本快照留到最后），每个声明最新的渲染，以及渲染变过的那几版。
  `addVersion` 返回后，索引器和 MachO 就可以释放。
- `ObjCDeclarationRendering` 里单个方法、属性、ivar 的渲染函数改为 `package` 访问；类、协议、分类的头部行
  （`@interface X : S <P, …>` 等）抽成 `package` 函数，由 `objc dump` 和新渲染器共用。不扩大公开 API，`objc dump` 的输出逐字节不变。

### 合并与排序

- 用 `ObjCGenerationOptions.default` 渲染：不剥成员，也不加注释。被剥掉的成员没有行可以挂标注；地址、偏移注释每版都不同。
- 种类顺序与 `objc dump` 相同：类、协议、分类、C struct、union，同类按名字排序。没有 class object、由宿主补充的类照 `dump` 的样子在头部上方带一行说明。
- 容器内的分组与 `objc dump` 相同：ivar 块、类属性、属性、类方法、实例方法；协议另分 `@required` / `@optional`。
  组内按最新版本的顺序；删掉的成员插在它最后出现的那一版里紧挨在它前面的成员之后，前面没有成员时插在紧挨在它后面的成员之前。
  采纳的协议列表也这样合并；superclass 取最新版本。
- 同一个容器里 identity 相同的成员（类扩展重新声明的属性之类）只写第一条，与快照只比较第一条一致；其余的在文件末尾的
  identity key 冲突警告里列出。

### 标注

- 照 Swift 的写法：文件头两行写版本轴，以及位图每一位对应的版本；有事件的声明在行尾加 `// [●○●] added in X`、`removed in X` 或
  `modified in X: 旧 → 新`，多个事件用 ` · ` 连接。同一个容器里的标注按列对齐，列位置最多到 72，代码超过这一列时标注另起一行。
  没有标注就表示整条轴上都在、从没变过。加入或删掉的容器只在它那一行标注，成员不再各自标注：lineage 只在容器两边都在时
  比较成员，成员跟着容器存在。
- `modified` 的新旧两边是两个版本各自渲染出的那一行，多行的渲染（内联展开的匿名 struct）合成一行。两边渲染相同时只写 `modified in X`；
  协议成员只在 `@required` 与 `@optional` 之间移动时写 `@required → @optional`。
- superclass 和采纳的协议（`superclass`、`adopts:P` 两种 lineage）都在容器头部那一行上，所以各自写成头部上方的一行注释，
  例如 `// [●●○] adopts <NSFoo> removed in 14.0`、`// [●●●] superclass modified in 13.0: NSObject → NSResponder`；
  容器自己的标注仍挂在头部行末。
- 某个版本有 identity key 冲突时，文件末尾照 `ObjCAPIEvolutionReporter` 的措辞列出。

示意（不是真实输出）：

```objc
// ObjC API evolution across 3 versions: 12.0.1 → 13.0 → 14.0
// Bitmap positions: [1] 12.0.1  [2] 13.0  [3] 14.0
// API_AVAILABLE and API_OBSOLETED versions are axis points: … not necessarily the releases that really introduced or removed it.

// [●●○] adopts <NSFoo> removed in 14.0
@interface NSExampleView : NSView <NSAnimatablePropertyContainer, NSFoo> {
    struct __EVFlags _flags;            // [●●●] modified in 13.0
}

- (id)initWithFrame:(struct CGRect)frame;
- (void)reloadData API_AVAILABLE(macos(13.0));   // [○●●] added in 13.0
- (void)_legacyLayout;                // [●○○] removed in 13.0

@end

API_AVAILABLE(macos(13.0))
@interface NSComboButton : NSControl  // [○●●] added in 13.0
```

### 可用性（传入平台名才输出）

- 平台名原样写进宏（`macos`、`ios`……），由宿主从 `LC_BUILD_VERSION` 推出，或由用户指定。
- 只有引入：`API_AVAILABLE(macos(13.0))`。引入后又删掉：`API_OBSOLETED("Removed", macos(13.0, 14.0, 14.0))`。
  SDK 的这个宏要求引入、废弃、移除三个版本，废弃版本取移除版本，与 SDK 里 `macos(11.0, 27.0, 27.0)` 的写法一致。
- 都不写的情况：删了又加回的、只被修改过的、标签不是 1–3 段数字的，以及从轴起点就在、后来删掉的。最后一种与 Swift 不同：
  Swift 的 `@available(macOS, obsoleted:)` 可以不写引入版本，SDK 的宏不行，而版本轴不知道它是哪一版引入的。这些情况位图注释照样写。
- 位置照 SDK 头文件的习惯：类、协议、分类在头部上方单独一行；方法、属性插在结尾的 `;` 前。ivar、采纳的协议和 superclass 不写：
  SDK 从不给 ivar 标可用性，后两者不是独立的声明。
- 文件头加一行说明：宏里的版本是版本轴上的点，不一定是真正引入或移除它的系统版本。

### 交给本提案定的三件事

- **C struct 与 union**：放在分类之后，每个定义取自定义它的最新版本，不标注，这一节开头用一行注释说明它不参与追踪。
  成员只按名字引用有名字的 struct（只有匿名 struct 内联展开），不输出的话，私有 struct 的布局就从合并结果里消失了。
  struct 布局变了，引用它的成员的类型编码也会变，那个成员会标 `modified`。
- **前向声明**（`@class`、`@protocol` 的前向声明）：不输出，`objc dump` 也不输出。
- **组内排序**：按最新版本的顺序（见「合并与排序」），不改成按字母排。这样同一个镜像交两次时，正文就是 `objc dump` 的输出，只少了重复的成员。

### 不做

- objc-section CLI 不加这个选项：它要按提案 0010 移除，这个功能只在 `swift-section objc` 上提供。
- 不另给结构化调用方逐行的数据（Swift 一侧的 `EvolutionLine`）。有人要时再加。

### 测试与发布

- 纯值测试：位图、事件措辞、可用性规则、标注对齐。
- 进程内的 Foundation：同一个镜像交两次，正文与 `objc dump` 的输出逐行相同，没有任何标注；只少了重复的成员，
  条数等于冲突警告列出的条数。
- 归档 cache（卷不在时跳过）：AppKit 11.0.1 → 12.0.1 → 13.0。SDK 头文件标了 `API_AVAILABLE(macos(13.0))` 的类
  （`NSComboButton`）标 `added in 13.0`，开了可用性时写出同样的宏；每条有事件的 lineage 在正文里恰好对应一条标注；
  删掉的声明留在原处，从轴起点就在的不写宏，12.0.1 加入、13.0 删掉的写 `API_OBSOLETED`。
- 使用指南的库调用方一节补上这个接口和内存约定；术语表按需登记。发布为 0.8.203。

### 落地步骤

每一步都能单独构建、测试通过：

1. 渲染层开口：成员渲染函数改为 `package`，头部行抽成共用的 `package` 函数；`objc dump` 的输出不变，现有测试照常通过。（已完成）
2. 标注格式层：位图、事件措辞、可用性宏、列对齐、文件头与警告尾，配纯值测试。（已完成）
3. 合并渲染器：`ObjCEvolutionInterfaceBuilder` 与 `ObjCEvolutionInterface`；进程内 Foundation 交两次，正文与 `objc dump` 逐行相同（重复的成员除外）。（已完成）
4. 归档 cache 测试：AppKit 11.0.1 → 12.0.1 → 13.0，核对 SDK 标了 13.0 的类，以及 lineage 与标注一一对应。（已完成）
5. 文档：使用指南的库调用方一节、术语表、提案的收尾记录。（已完成）

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-28 | Created as Draft | MachOSwiftSection 要给 `swift-section objc evolution` 加 `--interface` 视图，合并与标注的渲染放在本库 |
| 2026-10-28 | 声明沿用 `objc dump` 的渲染；宿主一次交一个版本的索引器 | 用户在 MachOSwiftSection 一侧选定外观；单个 AppKit 快照进程峰值 185–300 MB，51 个版本的索引器同时留在内存里会超出 5 GB 的上限 |
| 2026-10-28 | C struct / union 取各自最新的定义、不标注；不输出前向声明；组内按最新版本的顺序 | MachOSwiftSection 一侧交给本提案定，理由见方案 |
| 2026-10-28 | 从轴起点就在、后来删掉的声明不写 `API_OBSOLETED` | SDK 的宏必须带引入版本，版本轴不知道它；位图注释照样写 |
| 2026-10-28 | 用户批准，开始实现；补上落地步骤 | 做完先在本地合进 next 给用户看，看过后再推送并发布 0.8.203 |
| 2026-10-28 | identity 相同的成员只写第一条，与 `objc dump` 不再逐字节相同 | 对照测试发现 Foundation 有 6 个类把同一个属性列了两次（头文件里只读、类扩展里可写）。快照只比较第一条，合并视图跟着只写第一条，每一行就都有确定的 lineage；丢掉的那条连同签名列在文件末尾的冲突警告里 |
| 2026-10-28 | 删掉的成员前面没有成员时，插在它后面那个成员之前 | 方案只说了「插在前一个成员之后」，没有覆盖它原本排在第一位的情况 |
| 2026-10-28 | 归档 cache 测试用 11.0.1 → 12.0.1 → 13.0 三个版本，不是方案写的两个 | 三个版本才有「中间版本加入又删掉」的生命周期，`API_OBSOLETED` 才测得到；这三个 cache 也正是现有测试用的三种方法列表布局 |
| 2026-10-28 | 实现完成，待用户看过后收尾 | 全量测试 245 个通过（原有 224 个加新增 21 个）；`objc dump` 对 macOS 27.2 的 AppKit、Foundation 输出与 0.8.202 逐字节相同；在 M3 Ultra 上合并 8 个 AppKit 版本，每版 6–8 秒，每加一版进程占用涨 25–35 MB，`build` 后共 451 MB，照此推算 51 个版本约 2 GB |
| 2026-10-28 | 文档：使用指南加库调用方一节，术语表登记 evolution interface，公开 README 补一段；不另写实现说明 | 调用方要遵守的约定（版本顺序、何时释放索引器、重复成员、可用性宏的条件）进使用指南；维护者要知道的取舍都在本提案的决策日志和代码注释里，单写一份实现说明只会复述它们 |
| 2026-10-29 | 落地为 0015，状态改 Implemented，随 0.8.203 发布 | 用户在 MachOSwiftSection 一侧验收了 `swift-section objc evolution --interface` 的输出，并在本仓库确认收尾发版；那边要等这个版本发出才能抬依赖下限。没有未完成的项 |
