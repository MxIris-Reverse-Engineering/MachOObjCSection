# Draft - 由宿主补充文件里没有 class object 的类

- **状态**: In Progress
- **创建日期**: 2026-10-27
- **最后更新**: 2026-10-27
- **关联**: MachOSwiftSection [issue #137](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/issues/137)
  （`swift-section objc dump` 漏掉 Swift 定义的两类 ObjC 类）；MachOSwiftSection 侧在
  `ObjCInterfaceSession.make` 里从 Swift metadata 算出补充类并传入
- **实现分支**: `feature/host-supplied-classes`
- **配套文档**: [使用指南的库调用方一节](../Guides/ObjCSectionCommandLine.md#库调用方没有-class-object-的类由宿主补充)；[泛型化到 MachOFile 的实现说明](../Internal/ObjCMetadataSourceGenericization.md)里核心 target 例外的补记

## 摘要

`ObjCInterfaceIndexer.prepare()` 只遍历 `__objc_classlist` 与 non-lazy 列表里的 class object。带 ObjC 祖先的
Swift 类里，有三种不在这些列表中：

| 种类 | 文件里有什么 | `class_ro_t` 在哪 |
|---|---|---|
| 泛型类（`MenuBarPanelWindow<A: View>: NSPanel`） | 只有 Swift 泛型 metadata pattern | pattern 的 extra-data 里的模板；模板的 `name` 为 NULL，ivar 偏移槽为空，都由运行时按特化填 |
| 超类在别的 resilience 域的非泛型类（`MenuBarLabelHostingView: NSHostingView<MenuBarLabel>`） | `__objc_stublist` 里的 class stub（`…CMs`），stub 不带 RO 指针 | `ResilientClassMetadataPattern.data` |
| 超类是泛型的非泛型类 | 同样只在 `__objc_stublist` | 它的静态 metadata 里 |

后两种的 stub 与 RO、第一种的全部信息，都只能从 Swift metadata（类型描述符、metadata pattern）找到。那是
MachOSwiftSection 的领域，本库不解析 Swift metadata。本提案加一个**由宿主补充**的接口：宿主给出每个类的
`class_ro_t` 偏移、名字、超类名与种类（有 stub 的再给 stub 偏移），索引器把它当作普通类索引——进 `classNames`、
发继承与协议采纳事件、能渲染 `@interface`，也进 `snapshot` / `diff` / `evolution`；挂在它 stub 上的 category 也归到
它名下。全部是新增 API，不传补充类时行为与输出逐字节不变。

## 方案

### API

```swift
// ObjCIndexing
public struct ObjCSuppliedClass: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case genericSwiftClass               // "Generic Swift class, instantiated at runtime"
        case swiftClassWithResilientAncestry // "Swift class with resilient ancestry, registered through __objc_stublist"
        case swiftClassWithGenericAncestry   // "Swift class with generic ancestry, registered through __objc_stublist"
    }
    public var name: String                        // 索引与渲染用的名字，宿主决定
    public var superClassName: String?             // 超类的 ObjC 名，宿主从 Swift metadata 读出
    public var readOnlyDataOffset: Int             // 实例 class_ro_t
    public var metaclassReadOnlyDataOffset: Int?   // 元类 class_ro_t；没有就没有类方法与类属性
    public var classStubOffset: Int?               // __objc_stublist 条目指向的 class stub；泛型类没有
    public var kind: Kind
}

public struct ObjCSuppliedClassGroup: Sendable {
    public let suppliedClass: ObjCSuppliedClass
    public let info: [ObjCClassInfo]               // 自己在前，其后是按名字在本索引里接上的超类链
    public let ivarNamesWithUnknownOffset: Set<String>
}

// ObjCInterfaceIndexer
public init(machO: MachO, imagePath: String, suppliedClasses: [ObjCSuppliedClass] = [],
            eventHandler: (@Sendable (ObjCIndexingEvent) -> Void)? = nil)
public func suppliedClassGroup(forName name: String) -> ObjCSuppliedClassGroup?
```

### 规则

- **偏移约定**与本库 `ObjCClassRODataProtocol.offset` 相同，也就是 MachOSwiftSection 的偏移：独立二进制是 slice
  内的文件偏移，dyld cache 里的镜像是「未滑动地址减 `sharedRegionStart`」，`MachOImage` 是到镜像 header 的距离。
  索引器自己读 RO，宿主不必用 `@_spi(Core)` 构造 `ObjCClassROData64`。32 位镜像读 `ObjCClassROData32`。
- **顺序**：补充类在 `__objc_classlist` 的类之后、按传入顺序索引。事件顺序保证随之扩展为「class phase 先走
  classlist，再走补充类」，不传补充类时事件流不变。
- **跳过**（不报错，`prepare()` 之后 `suppliedClassGroup(forName:)` 为 `nil` 即是）：名字为空；名字已被索引
  （class object 优先，补充类之间先到先得）；RO 读不出来（偏移越界或不在任何映射里）。
- **自身信息**：名字与超类名用宿主给的，从不读 RO 的 `name`（泛型模板里是 NULL）。协议、ivar、属性、方法读实例
  RO，类属性与类方法读元类 RO，`instanceSize` 取 RO 上的值。
- **偏移未知的 ivar**：偏移槽为空的 ivar 保留（`ObjCClassProtocol.info(in:)` 会把它们整个丢掉），`offset` 记 0，
  名字列进 `ivarNamesWithUnknownOffset`。打开 `addIvarOffsetComments` 时渲染成 `// offset: unknown`。
- **超类链**：从宿主给的超类名出发按名字在本索引里接：遇到有 class object 的类，接上它的整条链后结束；遇到补充类，
  接上它自己再继续；遇到不认识的名字或成环即停。链只服务 `stripOverrides` 与下游的祖先判断。
- **事件**：`progress` 的计数含补充类；`subclassIndexed` / `conformanceIndexed` 照发，`isSwiftStable` 为 `true`
  （三种都是稳定 ABI 的 Swift 类）。C struct / union 照样从补充类的类型编码里收集。
- **挂在 stub 上的 category**：同一镜像里给 stub 类写的 `@objc` 扩展，编译器把 category 的 `cls` 指向 class stub
  （`GenMeta.cpp` `emitClassMetadata` 的 Resilient 分支注释）。stub 没有 RO，今天的读取器读不出它的类名，只能退回
  查 `__CATEGORY_…` 本地符号，二进制 strip 过就整个丢掉这个 category。索引器在 category 阶段先看 `cls` 是否指向某个
  已索引补充类的 `classStubOffset`：是，就以补充类的名字建 category 信息（覆盖符号推出的名字，与类的索引键一致），
  `categoryConformanceIndexed` 的 `targetIsSwiftStable` 为 `true`；否则照旧。
- **查询**：`classNames` 含补充类；`classGroup(forName:)` 与 `ObjCClassGroup` 不变，对补充类返回 `nil`，补充类
  走 `suppliedClassGroup(forName:)`。
- **渲染**：`ObjCInterfaceBuilder.classInterface` / `markedClassInterface` 认补充类，在 `@interface` 上方加一行
  种类注释（总是输出，不设开关）；`ObjCRenderingContext` 新增 `ivarNamesWithUnknownOffset`。
  `ObjCAPISnapshotBuilder` 把补充类收进 module，`snapshot` / `diff` / `evolution` 因此都看得到它们。
- **实现位置**：核心 target `MachOObjCSection` **只追加不修改**——「按偏移读 RO」「只凭 RO 建 `ObjCClassInfo`」与
  「按给定类名建 `ObjCCategoryInfo`」追加在 `Support/ObjCDump.swift` 末尾，复用该文件的 `fileprivate` 辅助函数；
  `ObjCMetadataSource` 加相应的转发要求（另加一条取 category 所指 stub 的偏移）。没有现有代码行被改动。

### 不做

- 本库不解析 Swift metadata，找 RO、取名字、取超类名全归宿主。
- 不改 `ObjCClassGroup`、不改 `ObjCIndexingEvent` 的关联值、不加生成开关——三者都是破坏性改动。
- `objc-section` 命令行不接这个接口：它算不出 Swift metadata，而且按 0010 要移除。
- RuntimeViewer 用自己的索引器副本，不受影响。

### 测试

- **一致性**：Foundation 与测试 bundle 里每个 class object，「只凭它的 RO 与元类 RO 建出的信息」等于
  `ObjCClassProtocol.info(in:)` 的结果（ivar 全部有偏移时）；每个读得出类名的 category，「按该类名建出的信息」
  等于 `ObjCCategoryProtocol.info(in:)` 的结果。file / image 两种模式各一遍。它们同时钉住「追加的组装逻辑与上游
  原逻辑不漂移」。
- **stub 上的 category**：测试时用 swiftc 现编两个模块——一个开 library evolution、导出 `open class Base: NSObject`，
  另一个继承它并写一个 `@objc` 扩展——从符号表取 stub 偏移，验证 category 归到补充类名下、`targetIsSwiftStable`
  为 `true`，不传 `classStubOffset` 时行为不变。
- **索引器**：拿一个 classlist 类的 RO 当替身补充进来，验证 `classNames`、`suppliedClassGroup`、按名字接链（含
  补充类接补充类、成环终止）、跳过规则、事件顺序与 `isSwiftStable`；独立文件与 dyld cache 镜像两种偏移约定都测。
- **偏移未知与 NULL 名字**：测试时用 clang 现编一个手写 `class_ro_t` 的 fixture（同 `SelfBindFixture` 的做法），
  其 `name` 为 NULL、一个 ivar 的偏移槽为空。
- **渲染**：种类注释与 `offset: unknown`；补充类的标记渲染按各组开关投影后等于普通渲染（0011 的不变量）；
  snapshot 含补充类。
- **真实二进制**：`/Volumes/RE` 挂载时跑 Xcode 27.2 的 `Xcode Service`（thin arm64），未挂载则跳过。偏移由
  MachOSwiftSection 给出、对过 `dyld_info -fixups`：泛型类 `MenuBarPanelWindow`（超类 `NSPanel`）实例 RO
  `0x711F8`（name 槽为 NULL，方法表是 `0x59110` 的 relative method list，9 项）、元类 RO `0x71240`（无方法）；
  `MenuBarLabelHostingView` 实例 RO `0x7B248`（3 个方法：`layout`、`viewWillDraw`、`initWithCoder:`）、元类 RO
  `0x78CD0`、stub `0x7CF40`。这个二进制没有 `__objc_catlist`，stub 上的 category 只能靠上一条的现编 fixture。

### 文档

README 的库用法一节（英文）、使用指南里面向库的一半补一节契约（偏移约定、跳过规则、两个查询入口的分工、偏移未知
的 ivar、stub 上的 category），术语表登记「supplied class（补充类）」。不另写实现说明：核心 target 的例外补记进
《泛型化到 MachOFile 的实现说明》讲边界的那一节。

### 落地步骤

1. 核心 target 的追加 API 与一致性测试。（已完成）
2. `ObjCMetadataSource` 的新要求与两种模式的实现。（已完成）
3. 索引器：新类型、`init` 参数、`prepare()`（含 stub 上 category 的归属）、查询与文档注释，及其测试。（已完成）
4. 渲染层、builder、snapshot builder，及其测试。（已完成）
5. README、使用指南、术语表。（已完成）
6. 把分支告诉 MachOSwiftSection；拿到真实偏移后补上真实二进制测试。落地合入 `next` 后，发一个 fork 版本供
   MachOSwiftSection 依赖（发版由用户决定）。（分支已告知，真实二进制测试已随第 3 步落地；合并与发版待用户）

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-27 | Created as Draft | MachOSwiftSection 的会话为 issue #137 发来跨仓库请求：`swift-section objc dump` 看不到泛型 Swift 类与超类跨 resilience 域的 Swift 类，因为索引器只遍历 class object 列表；找它们的 RO 要解析 Swift metadata，归 MachOSwiftSection，本库只需提供补充入口。 |
| 2026-10-27 | 补充类走独立查询 `suppliedClassGroup(forName:)`，`classGroup(forName:)` 与 `ObjCClassGroup` 不变 | 把 `ObjCClassGroup.objcClass` 改成可选值也能装下补充类，但那是源码破坏性改动，而 fork 版本号的补丁位跟着上游走（术语表「fork numbering」），没有位置表达破坏性升级。已知下游都不读 `objcClass`，独立入口不损失什么。 |
| 2026-10-27 | 补充类经 `init` 参数传入，不做 provider 协议 | 宿主在构造索引器之前就能算出列表；provider 只是在 `prepare()` 里多一层回调，真需要时可以再加，不破坏现有签名。 |
| 2026-10-27 | 偏移沿用本库 `class_ro_t` 的偏移约定，由索引器自己读 RO | 与 MachOSwiftSection 的偏移约定一致——它的 `SwiftClassObjectIndex` 已经用自己的偏移构造 `ObjCClassROData64` 并调本库读名字——宿主不必换算，也不必依赖 `@_spi(Core)`。 |
| 2026-10-27 | 核心 target 只追加：读 RO 与只凭 RO 建类信息写在 `Support/ObjCDump.swift` 末尾 | 组装要用该文件的 `fileprivate` 辅助函数（relative list 解析、协议展开）与 internal 的 `objcImageIndex`、`fileHandleAndOffset(forOffset:)`；放进 fork 自己的 target 得把它们重写一遍。只追加不改现有行，合并上游时冲突面最小；与 `ObjCClassProtocol.info(in:)` 的一致性由测试钉住，上游改了那边，测试会先红。 |
| 2026-10-27 | 偏移未知的 ivar 保留，`offset` 记 0，另列 `ivarNamesWithUnknownOffset`，注释写 `offset: unknown` | 泛型类的字段偏移只存在于实例化后的 field offset vector，编译器给模板的 ivar 偏移槽填 NULL（swift `GenClass.cpp` `buildIvar` 的 `ConstantIndirect` 分支）；照搬 `ObjCIvarProtocol.info(in:)` 会把这些 ivar 全丢掉。`ObjCIvarInfo.offset` 是非可选 `Int`，改成可选是 swift-objc-dump 的破坏性改动。diff 本就不比较偏移。 |
| 2026-10-27 | 种类注释总是输出，不加生成开关 | 加开关要给 `VisibilityOption` 加 case，对下游的穷尽 `switch` 是破坏性改动；没有这行注释，读者会把一个运行时才生成的类当成普通 ObjC 类。 |
| 2026-10-27 | `Kind` 多列一个 `swiftClassWithGenericAncestry` | Swift 编译器里不进 `__objc_classlist` 的带 ObjC 祖先的类恰好三种（`ClassMetadataStrategy` 为 Resilient 的泛型类、Resilient 的非泛型类、Singleton），后两种的 stub 都进 `__objc_stublist`（`GenMeta.cpp` `emitClassMetadata`）。宿主遍历 stub list 时两种都会遇到；一次列全，免得以后加 case 破坏穷尽 `switch`。MachOSwiftSection 确认三种都会提供；同时具有 resilient 与泛型祖先的类（如超类为 `SwiftUI.NSHostingView<MenuBarLabel>`）走 Resilient 策略，归第二种。 |
| 2026-10-27 | 加 `classStubOffset`，把指向补充类 stub 的 category 归到补充类名下 | MachOSwiftSection 审阅接口时提出。stub 上的 category 今天在 strip 过的二进制里被整个丢掉，没 strip 时类名来自本地符号、可能与宿主给的名字对不上。只多一个可选字段，不传时行为不变。 |
| 2026-10-27 | 用户批准，开始实现 | 用户批准本提案，包括在上游文件 `Support/ObjCDump.swift` 末尾追加函数、以一致性测试钉住与原逻辑不漂移。 |
| 2026-10-27 | 读 RO 用 `ObjCClassRODataProtocol` 上的可失败构造器 `init?(offset:in:)`；只凭 RO 建类信息用 `classInfo(name:superClassName:metaclassData:in:options:)`，返回带标签的元组 `(info:ivarNamesWithUnknownOffset:)` | 上游文件里不新增类型；返回元组是该库已有的写法（`metaClass(in:)`、`stubClass(in:)`）。 |
| 2026-10-27 | category 所指 stub 的偏移由 `ObjCMetadataSource.objcCategoryTargetClassStubOffset(of:)` 用上游已公开的 `stubClass(in:)` 取，核心 target 不为此追加代码；镜像模式下 stub 不在本镜像时返回 `nil` | 镜像模式的偏移从各自镜像的 header 算起，别的镜像里的 stub 可能与本镜像某个 stub 偏移相同；文件模式下 dyld cache 的偏移从主 cache 起点算，不会相撞。 |
| 2026-10-27 | 只凭 RO 建出的 `version` 按 `ObjCClassProtocol.version(for:)` 的规则取（元类 7，其余 0），镜像模式的一致性测试不比较 `version` | 镜像模式下已实现的类的 `version` 来自运行时数据，由 `class_setVersion` 写入，`class_ro_t` 里没有这个值。 |
| 2026-10-27 | 补充类的测试放进 `ObjCMetadataSourceTests`，真实二进制测试随第 3 步提前落地 | 这些测试要现编 C 与 Swift fixture，还要用 builder 和 snapshot builder，这个 target 已经依赖这几个模块，也已有现编 fixture 的先例（`SelfBindFixture`）；Xcode Service 的偏移在开工前已经拿到。 |
| 2026-10-27 | 进度事件的总数在开始时去掉空名字与重名的补充类；名字被 class object 占用或 RO 读不出的补充类仍计入总数 | 这两种要走到它才知道；宿主按 Swift metadata 算出的补充类本不会撞上 class object，也都读得出，只有宿主出错时计数才到不了总数。 |
| 2026-10-27 | 偏移未知的 ivar 不交给 `ivarOffsetCommentBuilder`，一律写 `offset: unknown` | 这个闭包只接收一个 `Int`，表达不了「未知」；交给它就只能传 0，读者会把 0 当成真实偏移。 |
| 2026-10-27 | 不另写实现说明；核心 target 的例外补记进《泛型化到 MachOFile 的实现说明》，术语表登记「supplied class（补充类）」 | 维护者会踩到、代码里看不出的只有一件事：上游文件末尾那段是 fork 的、为什么放那里、靠什么防漂移，它属于那篇文档讲核心目录边界的一节。其余取舍都已在本提案的决策日志里。 |
| 2026-10-27 | 实现完成，待合并 | 第 1–5 步都已落在 `feature/host-supplied-classes`；`swift test --skip MachOObjCSectionTests`（与 CI 相同）220 个测试全部通过，退出码 0。合并、编号与 fork 发版留给用户。 |
