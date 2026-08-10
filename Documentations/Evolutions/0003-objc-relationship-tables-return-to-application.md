# 0003 - ObjC 关系反向表移出索引层，归还应用

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-08-10
- **最后更新**: 2026-08-10
- **所属愿景**: 无
- **关联提案**:
  - [0001](0001-objc-rendering-and-indexing-downstreaming.md)（**部分修订其范围判断**，0001 保持 `Implemented` 原貌不动）
  - [0002](0002-objc-machofile-genericization-and-cli.md)（**本提案应先于 0002 落地**，理由见「与 0002 的先后」）
- **实现分支 / PR**: 待定
- **配套文档**: [ObjC 渲染层与索引层的实现说明](../Internal/ObjCRenderingAndIndexingImplementation.md)（已更新：分层图，以及「事件通道」一节里被本提案推翻的那段结论）

## 摘要

把 `ObjCInterfaceIndexer` 里的**继承 / 协议遵守反向表**从库中移除：删掉两张表的存储、
两个查询方法、`ObjCClassReference` 类型，以及只为这两个查询服务的整套聚合机制
（`addSubIndexer(_:)` 与 `subIndexers`）。

**三个关系事件保留**，并给它们的 payload 补上 `isSwiftStable`。库从此只负责解析并把发现
如实广播出去；要不要把这些发现攒成表、攒成什么形状的表，交给消费者决定。

`ObjCIndexing` 的职责收敛为「解析一个 image 的 ObjC 元数据并提供按名查询」。

## 动机

### 一、eager O(N) 的代价强加给了所有消费者

两张反向表是在 `prepare()` 的走查里**同步、无条件**建起来的
（`Sources/ObjCIndexing/ObjCInterfaceIndexer.swift:288-294` 与 `:374-379`）。每个 class
记录都要构造一个 `ObjCClassReference`、对超类做一次加锁写入、对每个 inline 采纳的协议再各做
一次；每个 category 对每个采纳协议同样各做一次。这是随 image 里 class 与 category 数量线性
增长的时间与内存开销，且**没有任何开关可以关掉**。

而这两张表服务的是一个具体的产品功能 —— RuntimeViewer 的 Relationships 标签页。一个只想
渲染某个类接口的调用方（`ObjCInterface` 的典型用法，也是 README 里的首个示例），不会碰这两张
表一次，却要为它们付全额的构建成本。

### 二、聚合机制在唯一消费者那里是纯死重

`addSubIndexer(_:)` 与 `subIndexers` 存在的唯一目的，是让 `subclasses(of:)` /
`conformingClasses(toProtocol:)` 跨 image 扇出（`ObjCInterfaceIndexer.swift:591-620`）。

**但 RuntimeViewer 从来没有读过这个聚合。** 经 RuntimeViewer 侧核实：
`RuntimeObjCSectionFactory` 确实持有一个聚合实例并在建 section 时 `addSubIndexer` 注册进去，
但全仓库对该聚合的引用只有四处 —— 声明、构造、两处 `addSubIndexer`，**没有任何一处读它**。
真正的跨 image 合并是 `RuntimeRelationshipsResolver` 在调用点自己做的：遍历已索引的
image 路径，逐个取该 image 自己的 indexer 查表。

也就是说库里这套 fan-out 是只写不读的纯开销。它同时还是下面第三条的病灶。

### 三、它顺带解掉一个已经埋下的跨分支冲突

RuntimeViewer 的 feeder 分支 `feature/node-store-adoption`（同时在 `next` 上）有一个
commit `f41648a`，"release per-image index state instead of pinning it for the engine's
lifetime"，修的正是**聚合造成的内存泄漏**：`addSubIndexer` 没有逆操作，聚合活得和 engine
一样长，用户浏览过的每个 image 的索引状态因此永远释放不掉。它的修法是给本地的
`RuntimeObjCInterfaceIndexer` / `RuntimeSwiftInterfaceIndexer` 各加一个 `removeSubIndexer(_:)`。

而 main 上的 `889f1bd`（消费本库）已经把 `RuntimeObjCInterfaceIndexer` 整个删掉了，
本库的 `ObjCInterfaceIndexer` 也**没有** `removeSubIndexer`（已在 `Sources/` 全文搜索确认）。
两条线迟早要撞：那个内存修复的 ObjC 那一半，要打补丁的对象已经不存在，而顶替它的库类型没有
对应 API。

按常规做法，这时候该回头给库补一个 `removeSubIndexer`。**但既然聚合在 ObjC 侧是只写不读的，
正确解法是删掉聚合本身** —— 泄漏源没了，逆操作自然不需要。本提案一并完成这件事。

（说明：main 上目前不存在这个泄漏的修复，也谈不上回归 —— main 从来没有过那段代码。
是 feeder 分支带着修复、main 带着重构，两边各自往前走。）

### 四、0001 是整体搬运，没有单独审视过关系表的归属

0001 把 `RuntimeObjCInterfaceIndexer.swift` 整个文件搬进库
（0001「待搬运的代码及其规模」表里记的是「索引 + struct/union 采集 + 继承与遵守反向表」，
639 行作为一个整体）。当时的判断单位是**文件**，反向表是搭着索引器一起过来的，没有被单独
拿出来问过「它该不该属于库」。

本提案就是补做这次审视，结论是不该。**0001 保持 `Implemented` 原貌不修改** —— 它是当时的
决策快照；范围判断的修订记录留在本篇。

### 五、Swift 侧不动，而且两边并不对称

RuntimeViewer 侧的 `RuntimeSwiftInterfaceIndexer` 是包在 `SwiftDeclarationIndexer`
外面的一层壳，只加三张关系反向表。曾经考虑过的反向做法 —— 把 Swift 那三张表也推进库、
两边对齐 —— 本提案不采纳，理由见「替代方案考量」。

需要指出的是，两边的聚合地位并不相同：Swift 侧的 `factory.indexer` 是**真被读的**
（`GenericSpecializer` / `IndexerConformanceProvider` 走 `factory.indexer.upstream`，
泛型特化还要查 `allAllTypeDefinitions`），所以那边的聚合是承重结构。ObjC 侧不是。
这也是「ObjC 搬回去、Swift 不动」在结构上站得住的原因，而不只是工作量取舍。

## 前期调研

### 库内消费者：除索引器自身与一个测试文件外，没有别的

在 `Sources/`、`Tests/`、`Benchmarks/` 全文搜索 `ObjCClassReference`、`subclasses(of`、
`conformingClasses`、`addSubIndexer`、`subIndexer` 及三个关系事件 case，命中如下：

| 位置 | 性质 |
|---|---|
| `Sources/ObjCIndexing/ObjCInterfaceIndexer.swift` | 索引器自身 |
| `Sources/ObjCIndexing/ObjCIndexingEvent.swift:19-25` | 三个事件 case 的声明 |
| `Tests/ObjCIndexingTests/ObjCIndexingTests.swift` | 74 / 82 / 114 / 116 / 137 / 139 / 140 |

`ObjCInterface` target 不碰关系表；`ObjCOutputTransformer`、`ObjCDeclarationRendering`
与 `MachOObjCSection` 本体均无引用。**爆炸半径限于 `ObjCIndexing` 一个 target。**

### 应用侧消费点：只有一处

RuntimeViewer 的 `RuntimeRelationshipsResolver.swift:85`。（由 RuntimeViewer 侧核实）

### 事件流足以重建两张表 —— 但 payload 缺一位

现有三个事件（`ObjCIndexingEvent.swift:19-25`）覆盖了两张表的**全部**写入点：
`indexClass` 的超类记录与 inline 协议记录、`indexCategory` 的 category 协议记录，
三者一一对应，没有第四条写入路径。

**但 payload 里没有 `isSwiftStable`。** 三个 case 目前都只带 `className` / `superclass` /
`protocolName` / `imagePath`。消费者靠现有事件流建表，会缺这一位。

### `isSwiftStable` 应用侧能否自算 —— 能，但 category 那条路很贵

- **class 侧便宜**：`isSwiftStable` 定义在 `ObjCClassProtocol` 的 public extension
  （`Sources/MachOObjCSection/Protocol/Class/ObjCClassProtocol.swift:66`），只读
  `layout.dataVMAddrAndFastFlags`，不需要 `machO`。消费者拿
  `classGroup(forName:)?.objcClass.isSwiftStable` 即可。
- **category 侧很贵**：`indexCategory` 的 `targetIsSwiftStable` 来自
  `objcCategory.class(in: machO)`（`ObjCCategoryProtocol.swift:162`，public），
  那是**跨 image 的 bind/rebase 解析**。category 的典型场景就是给别的框架的类加方法，
  target class 常常不在本 image —— 这也意味着本 indexer 的 `classGroup(forName:)` 对它
  会返回 `nil`，自算这条路走不通，只能重做 `class(in:)`。

而库在 `prepare()` 里**已经解析过一次**。让消费者再解析一遍，等于把「不必重新走查」省下的
成本又还回去。结论：`isSwiftStable` 进 payload。

### 「消费者重新走查 public 面」这条路：可行，但会丢掉顺序稳定性

先说结论：**不需要为此新增任何 public 面**，现有接口拿得全。

- class 侧：`classNames` + `classGroup(forName:)` → `info.first.superClassName`、
  `info.first.protocols`、`objcClass.isSwiftStable`，齐了。
- category 侧：`categoryNames` + `categoryGroup(forName:)` → `info.className`（target）、
  `info.protocols`；target 的 `isSwiftStable` 靠消费者自己那份 `MachOImage` 调
  `objcCategory.class(in: machO)`，也齐了。

**但它有个硬伤：顺序不再稳定。** `classNames` 是 `Array(classes.keys)`
（`ObjCInterfaceIndexer.swift:542-544`），Swift `Dictionary` 的迭代顺序随每个进程的
hash seed 变化。而现在的反向表用 `OrderedSet`，doc comment（`:588-590`）与
`subclasses(of:)` 的 doc comment 明确承诺「单 image 内保留插入顺序」，那个顺序就是 `__objc_classlist`
的顺序。改走查等于把 Relationships 里的子类列表变成每次启动顺序都不同 —— 用户可见的回归。

事件流按走查顺序到达，保序是免费的。这是「保留事件」相对「让消费者重新走查」的决定性优势。

### 事件回调的成本是平移，不是新增

事件是 `prepare()` 走查循环里的同步 `@Sendable` 回调。消费者在 handler 里写表，等于在解析
热路径上加锁 —— 而库现在的 `indexClass` / `indexCategory` **就在同一位置做同样的加锁写入**
（`:464-466`、`:477-479`、`:508-510`）。所以成本是从库内平移到消费者，总量不变。

消费者甚至可以做得更省：`prepare()` 的走查是单线程的，handler 里可以往一个无锁本地数组
append，`prepare()` 返回后一次性合并建表，省掉现在每条记录一次 `Mutex.withLock` 的开销。

### `OrderedCollections` 在本 target 只被关系表使用

`ObjCIndexing` 里 `OrderedSet` 的全部出现都在两张表及其查询上
（`ObjCInterfaceIndexer.swift:150-160`、`:592`、`:605`）。`ObjCInterface` 不使用。
删表后 `Package.swift:168` 的 `OrderedCollections` 依赖可以摘掉。

### 一个容易在搬迁中被改错的语义

`indexCategory` 传入的 `imagePath` 是 `self.imagePath`，即 **category 所在的 image**，
而非 target class 所在的 image（`ObjCInterfaceIndexer.swift:378`）。因此 category 产生的
`ObjCClassReference` 里，`className` 与 `imagePath` 并不属于同一个 image。

`indexClass` 没有这个不对称 —— class 就在本 image。

这是既有行为。消费者在应用侧重建表时应**原样保留**；按 `imagePath` 去定位那个类会找不到。
想改成「target class 真正所在的 image」属于行为变更，应另开提案并配回归测试
（与 0001 决策日志里「保留 setter 选择器缺冒号的既有行为」同一处理方式）。

## 提议方案

### 一、删除：关系反向表及其全部附属

| 删除对象 | 位置 |
|---|---|
| `ObjCClassReference`（public struct） | `ObjCInterfaceIndexer.swift:10-28` |
| `_subclassesByClassName` / `subclassesByClassName` | `:150-154` |
| `_conformingClassesByProtocolName` / `conformingClassesByProtocolName` | `:156-160` |
| `_subIndexers` / `subIndexers` | `:162-166` |
| `indexClass(className:superClassName:...)` | `:436-488` |
| `indexCategory(targetClassName:...)` | `:490-519` |
| `subclasses(of:)`（public） | `:584-599` |
| `conformingClasses(toProtocol:)`（public） | `:601-612` |
| `addSubIndexer(_:)`（public） | `:614-620` |
| `import OrderedCollections` | `:7` |

`prepare()` 里对 `indexClass` / `indexCategory` 的两处调用（`:288-294`、`:374-379`）随之
删除；`:367-373` 计算 `targetIsSwiftStable` 的那段**不删**，改为供事件 payload 使用（见下）。

### 二、保留并增强：三个关系事件

三个 case 全部保留，各补一位 `isSwiftStable`。两个一次性 phase 标记事件
（`.indexingSubclasses` / `.indexingConformances`，`:265-270`、`:343-348`）也保留 ——
它们是进度指示，与表无关。

### 三、职责边界

库给**结构信号**（`class_t` 记录上的 `FAST_IS_SWIFT_STABLE` 位），消费者做**领域判断**
（要不要把它物化成 Swift 类）。`ObjCClassReference` 这个类型承载的是「关系表条目」的语汇，
表走了它就该走；事件带平铺字段即可。

### 非目标

- **不动 Swift 侧。** `RuntimeSwiftInterfaceIndexer` 及其三张表留在 RuntimeViewer，
  本提案不涉及 MachOSwiftSection。
- **不给库加 `removeSubIndexer`。** 那是在给一个即将删除的机制补 API，见动机第三条。
- **不修改 category 的 `imagePath` 语义。** 原样保留，见前期调研末节。
- **不做 `MachOFile` 泛型化。** 那是 0002。
- **不新增替代性的关系查询 API。** 不做 `relationshipSnapshot()` 之类的「表还在只是换个门」
  的折中，那等于没搬。
- **不碰 `ObjCInterface` / `ObjCDeclarationRendering` / `ObjCOutputTransformer`。**

## 详细设计

### `ObjCIndexingEvent` 的新形状

```swift
public enum ObjCIndexingEvent: Sendable {
    case progress(phase: Phase, itemDescription: String, currentCount: Int, totalCount: Int)

    /// A class was found to subclass `superclass`.
    ///
    /// `isSwiftStable` is read off the subclassing class' own `class_t` record:
    /// `__objc_classlist` carries a record for every Swift class with an
    /// Objective-C ancestor, so a consumer can label the reference as Swift
    /// without any string-name bridging.
    case subclassIndexed(
        className: String,
        superclass: String,
        imagePath: String,
        isSwiftStable: Bool
    )

    /// A class was found to adopt `protocolName` inline.
    case conformanceIndexed(
        className: String,
        protocolName: String,
        imagePath: String,
        isSwiftStable: Bool
    )

    /// A category made its target class adopt `protocolName`.
    ///
    /// `imagePath` is the image declaring the *category*, which for a category
    /// on another framework's class is not the image declaring
    /// `targetClassName`. `targetIsSwiftStable` is resolved through the target
    /// class record across image boundaries.
    case categoryConformanceIndexed(
        targetClassName: String,
        protocolName: String,
        imagePath: String,
        targetIsSwiftStable: Bool
    )

    public enum Phase: String, Sendable, Codable, CaseIterable {
        case indexingSubclasses
        case loadingClasses
        case loadingProtocols
        case indexingConformances
        case loadingCategories
    }
}
```

### `prepare()` 里的发射点

class 走查（原 `:288-294` 的 `indexClass` 调用位置）改为直接发射：

```swift
if let superClassName = objcClassInfo.superClassName, !superClassName.isEmpty {
    eventHandler?(
        .subclassIndexed(
            className: objcClassInfo.name,
            superclass: superClassName,
            imagePath: imagePath,
            isSwiftStable: objcClass.isSwiftStable
        )
    )
}

for adoptedProtocol in objcClassInfo.protocols {
    eventHandler?(
        .conformanceIndexed(
            className: objcClassInfo.name,
            protocolName: adoptedProtocol.name,
            imagePath: imagePath,
            isSwiftStable: objcClass.isSwiftStable
        )
    )
}
```

`superClassName` 非空判断与协议遍历顺序均按原 `indexClass` 原样保留，发射顺序即原写表顺序。

category 走查（原 `:367-379`）保留 `targetIsSwiftStable` 的解析，改为：

```swift
let targetIsSwiftStable: Bool
if let (_, targetClass) = objcCategory.class(in: machO) {
    targetIsSwiftStable = targetClass.isSwiftStable
} else {
    targetIsSwiftStable = false
}

for adoptedProtocol in objcCategoryInfo.protocols {
    eventHandler?(
        .categoryConformanceIndexed(
            targetClassName: objcCategoryInfo.className,
            protocolName: adoptedProtocol.name,
            imagePath: imagePath,
            targetIsSwiftStable: targetIsSwiftStable
        )
    )
}
```

### 索引器的类文档

`:30-47` 的类文档要重写：删掉「plus the class-inheritance and protocol-adoption reverse
tables」以及整段聚合说明（`:39-42`）。`prepare()` 的文档（`:182-193`）同样删掉反向表相关
表述，改为说明它发射哪些事件。`@unchecked Sendable` 的理由段落保留 —— 剩下的五张字典仍是
mutex 守护的。

**并补上后面「本提案新引入的五条调用方契约」**：契约一、四写进
`init(machO:imagePath:eventHandler:)` 的 `eventHandler` 参数文档（那里是调用方唯一会看到
它的地方），契约二、三、五写进 `prepare()` 的文档。这五条都是编译器捕获不到的，doc comment 是
唯一能拦住人的位置。

契约五还要**同时**落到 `ObjCIndexingEvent` 本身的类型文档 —— 顺序是这个 enum 作为数据流的
性质，而不只是 `prepare()` 的性质；只写在 `prepare()` 上，读事件定义的人看不到。

### 消费者侧的等价重建（供 RuntimeViewer 参考，不属本提案实现范围）

```swift
// prepare 期间纯靠事件流建表，不重新走查。
let indexer = ObjCInterfaceIndexer(machO: machO, imagePath: imagePath) { event in
    switch event {
    case .subclassIndexed(let className, let superclass, let imagePath, let isSwiftStable):
        collector.recordSubclass(...)
    case .conformanceIndexed(let className, let protocolName, let imagePath, let isSwiftStable):
        collector.recordConformance(...)
    case .categoryConformanceIndexed(let targetClassName, let protocolName, let imagePath, let targetIsSwiftStable):
        collector.recordConformance(...)
    case .progress:
        break
    }
}
try await indexer.prepare()
```

### 本提案新引入的五条调用方契约

这五条在改动前都不存在、不重要，或挂在别处（契约五），且**都不会被编译器捕获** —— 违反的
症状是数据静默为空、重复、顺序改变，或在未来某个版本才浮现的数据竞争，不是编译错误。
它们必须同时写进 `init(machO:imagePath:eventHandler:)` 与 `prepare()` 的 doc comment，
而不只是留在本提案里。

**契约一：关系数据只通过 `eventHandler` 送出。**

> 未安装 `eventHandler` 的 indexer 不会以任何形式保留继承 / 遵守关系 —— 这不是降级，
> 是本库自 0003 起的既定边界。需要关系数据的调用方必须在**构造时**安装 handler，
> 且不得指望 `prepare()` 之后再补装。

改动前 `eventHandler` 是纯观察性的：不装也不影响任何功能，表照建，查询照用。改动后它是
关系数据的**唯一出口**。这个语义翻转是本提案最危险的一处，因为调用方代码不改也照样编译通过，
只是关系数据从此为空。

这不是理论风险。RuntimeViewer 侧现在创建 ObjC section 的 7 处调用点里**只有 1 处**传了
progress continuation，其 handler 又是「没有 continuation 就返回 `nil`」的条件构造 ——
其中 `RuntimeEngine+BackgroundIndexing.swift:62` 正是后台批量索引，绝大多数 image 由它带进来。
若照原样落地，结果是几乎所有 image 的关系表都为空，只有用户手动触发的那一次带进度加载是好的，
且全程静默，症状看起来是「这个类确实没有子类」。（由 RuntimeViewer 侧核实并计入其下游提案。）

**契约二：事件按 `prepare()` 的调用次数重放。**

> `prepare()` 没有幂等守卫。重复调用会把同一批关系事件再发一遍；消费者需自行去重，
> 或保证每个 indexer 只 `prepare()` 一次。

改动前重复 `prepare()` 是安全的，但那个安全性是 `OrderedSet.append` 白送的去重，不是设计
出来的（五张主表走 `classes = classByName` 的替换语义，两张反向表则直接 append 不重置）。
表移出后这层保护随之消失 —— 尤其是消费者若采纳前述「无锁数组 append + 事后合并」的优化，
重复 `prepare()` 会直接产生重复条目。

**契约三：关系数据的生命周期与 `prepare()` 绑定。**

> 表不再「已经在那儿」，而是「正在被填」。消费者若有 image 是懒加载 / 延后 `prepare()` 的，
> 关系查询必须排在对应 image 的 `prepare()` 完成之后。

**契约四：本库不承诺 `eventHandler` 的执行上下文，消费者必须自行同步。**

> 事件目前在 `prepare()` 的执行上下文中同步发出，走查是单线程的。**但这是当前实现，不是
> 契约。** handler 的类型是 `@Sendable` 正因为本库保留将来并行化走查的余地
> （0002 的 `MachOFile` 泛型化之后，按 image 或按 section 并行是自然的下一步优化）。
> 消费者在 handler 里写自己的数据结构时必须自带同步，不得因为「当前实现是单线程」而省掉它。

这条单独列出来，是因为它**已经被误读过一次**：0003 讨论过程中给出的「走查是单线程的，所以
消费者可以在 handler 里往无锁本地数组 append」这个优化建议，在下游被理解成了「锁只为满足
`@Sendable` 类型检查，不是为了防竞争」。前半句是当前实现的事实，后半句是把实现细节当成了
API 契约。

**这个优化本身仍然成立**（同步累积、`prepare()` 返回后一次性建表，锁内工作量确实更小），
成立的理由是「当前实现下无竞争，锁的成本接近零」，而不是「锁可以去掉」。锁要留着。

**契约五：事件的相对发射顺序是确定的，消费者可以依赖它。**

> 同一个 image、同一个库版本，两次 `prepare()` 产生**完全相同的事件序列**。当前顺序为：
> class 阶段的全部事件先于 category 阶段；class 阶段内按 `__objc_classlist` 的走查顺序，
> 每个 class 先发 `.subclassIndexed`、再按声明顺序发 `.conformanceIndexed`；category 阶段
> 按 category 列表走查顺序，每个 category 按声明顺序发 `.categoryConformanceIndexed`。
>
> **改变这个顺序算破坏性变更，须走提案。** 若将来并行化走查（契约四允许），必须保持有序
> 发射或按确定顺序归并 —— 顺序是一个要显式维护的性质，不是实现的副作用。

契约四与契约五**是可分的两件事，必须分开写**：不承诺执行上下文（线程 / 队列 / 并发性），
但承诺相对顺序。只写契约四会连带把顺序一起放掉，而顺序是承重的。

**这不是新增承诺，是承诺的转移。** 顺序保证今天已经存在，只是挂在别处：反向表用 `OrderedSet`
存储，查询按插入顺序返回，`subclasses(of:)` 的 doc comment（`ObjCInterfaceIndexer.swift:588-590`）
明确写了「单 image 内保留插入顺序」。表一旦移出，这个承诺的载体就没了 ——
不把它转移到事件上，等于**静默地丢掉一个已经对外给出的保证**。

而且不给这个承诺会让本提案自相矛盾：0003 否决「让消费者重新走查」的决定性理由，正是走查依赖
`Dictionary` 迭代顺序、会丢掉 `__objc_classlist` 顺序这个已承诺的稳定性（见「替代方案考量」）。
如果事件流本身也不保序，那条否决理由就塌掉一半 —— 两个方案在顺序上没有区别，而本提案已经
基于这个区别做出了选择。

代价评估：承诺顺序对将来并行化的实际约束很小。并行化的收益在解析（`info(in:)` 的解码），
发射本身是廉价的，「并行解析 + 有序发射 / 确定顺序归并」是并行归并的标准形状。用这点约束
换掉一个「今天碰巧成立、将来某天碰巧失效」的静默行为变更，是划算的。

## 替代方案考量

### 把 Swift 侧那三张表也推进库，两边对齐

**是什么**：反向做法 —— `RuntimeSwiftInterfaceIndexer` 的三张表（父类→子类、
mangled name→TypeName / ProtocolName）推进 MachOSwiftSection，ObjC 侧维持现状。

**为什么否**：它把本提案动机第一条的问题**扩大**而非解决 —— 让 MachOSwiftSection 的所有
消费者也开始付这笔 eager 代价。而且 Swift 侧那个实现还要额外做 O(N) 的 demangle + remangle
往返，代价比 ObjC 侧更高。方向上也说不通：Relationships 是 RuntimeViewer 的产品功能，
不会因为两个库都实现了它就变成库的职责。

### 加一个 `buildsRelationshipTables` 开关

**是什么**：表留在库里，构造时用一个 `Bool` 决定建不建。

**为什么否**：这个开关的存在本身就是在承认这东西不属于库 —— 一个只有单一外部功能需要、
默认还得关掉的子系统，正确归属是那个功能所在的地方。而且它并不省事：表、查询、聚合、
`ObjCClassReference` 全都要继续维护，还多一条「关掉时查询返回什么」的语义分支和对应测试矩阵。

### 连事件一起删，消费者重新走查 `classes` / `categories`

**是什么**：库彻底退出关系这件事，消费者在 `prepare()` 之后自己遍历 public 面重建。

**为什么否**：现有 public 面确实拿得全（见前期调研），但它多一遍完整走查，且
`classNames` 走 `Dictionary` 迭代顺序，会把 `__objc_classlist` 顺序这个已承诺的稳定性丢掉，
造成 Relationships 列表每次启动顺序不同的用户可见回归。事件零存储成本、天然保序，没有理由删。

### 给库补 `removeSubIndexer(_:)`，配合 feeder 分支的内存修复

**是什么**：保留聚合，补上缺失的逆操作，让 `f41648a` 的 ObjC 那一半能落到库类型上。

**为什么否**：聚合在唯一消费者那里只写不读（动机第二条）。给一个死机制补 API 来修它造成的
泄漏，不如把机制删掉 —— 泄漏源随之消失，逆操作也就不需要了。

### 保留 `ObjCClassReference` 让事件直接带 reference

**是什么**：三个事件的 payload 带 `ObjCClassReference` 而非平铺字段，类型留在库里。

**为什么否（弱否决）**：少一次结构重复，成本上没有区别，是个合理选项。不采纳的理由是这个
类型的语义 —— 它的 doc comment 写的是「被发现 subclass 了另一个类或采纳了协议的引用」，
那是关系表的语汇；表移出后库里不再有「关系」这个概念，留一个以它命名的 public 类型会让边界
重新模糊。**若评审倾向保留，本提案不反对**，这不是关键分歧。

## 影响

### 源码兼容性（source compatibility）

**有破坏。** `ObjCIndexing` 的 public 表面变化：

| 改动 | 对象 |
|---|---|
| 删除 public 类型 | `ObjCClassReference` |
| 删除 public 方法 | `subclasses(of:)`、`conformingClasses(toProtocol:)`、`addSubIndexer(_:)` |
| enum case 增加 associated value | `.subclassIndexed`、`.conformanceIndexed`、`.categoryConformanceIndexed` |

改前 / 改后对照：

```swift
// 改前 —— 库建表，调用方查表
let aggregate = ObjCInterfaceIndexer(machO: machO, imagePath: machO.imagePath)
aggregate.addSubIndexer(foundationIndexer)
aggregate.addSubIndexer(appKitIndexer)
let subclasses = aggregate.subclasses(of: "NSString")

// 改后 —— 调用方在 prepare 期间靠事件建自己的表
let collector = RelationshipCollector()
let indexer = ObjCInterfaceIndexer(machO: machO, imagePath: machO.imagePath) { event in
    collector.record(event)
}
try await indexer.prepare()
let subclasses = collector.subclasses(of: "NSString")   // 调用方自己的表
```

**不提供 `@available(*, deprecated, renamed:)` 过渡**：这三个 API 没有等价替代品可以
`renamed:` 过去，语义是「这件事不再由本库做」。用 `message:` 挂一个版本的废弃期也无实益 ——
唯一的外部消费者是 RuntimeViewer，而它的适配与本次发版是同批次协调的（见「落地步骤」）。

enum case 加 associated value 对 `switch` 里用 `case .subclassIndexed:`（不绑定值）的写法
不破坏；绑定值的写法需要补一个绑定。

**还有一处编译器捕获不到的破坏，危险性高于上表全部三项。** 删掉的三个 API 会让调用点直接
编译失败，那是好事 —— 编译器逼人去看。但 `eventHandler` 从「纯观察，不装也没关系」变成
「关系数据的唯一出口」这件事，**不改一行调用方代码也照样编译通过**，只是关系数据从此静默为空。
一个今天传 `nil` handler 的调用方，升级后不会收到任何信号。

这是本提案唯一一处需要靠文档而非类型系统兜住的变更，详见「本提案新引入的三条调用方契约」的
契约一。落地时必须写进 `eventHandler` 参数的 doc comment，并在 README 的事件示例里点明。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，未开启 library evolution，也无 `binaryTarget`，
使用方每次重新编译。

### 下游影响

**本仓库内**：只有 `ObjCIndexing` target 与 `ObjCIndexingTests`。`ObjCInterface`、
`ObjCDeclarationRendering`、`ObjCOutputTransformer`、`MachOObjCSection` 均不受影响
（已全文搜索确认无引用）。

**跨仓库**：

- **RuntimeViewer** —— 唯一的实际消费者。消费点是 `RuntimeRelationshipsResolver.swift:85`，
  需要在应用侧重建两张表并改由事件流填充。RuntimeViewer 侧登记独立的下游适配提案。
- **MachOSwiftSection**（13 个 target 依赖本库）—— 不受影响，不使用 `ObjCIndexing`。
- **MachOKitUI** —— 不受影响，同上。

**上游 fork 传导**：改动全部在 `Sources/ObjCIndexing/`（0001 新增的 target），
`Sources/MachOObjCSection/` 一行不改，不增加与上游合并的冲突面。

### 文档与示例

- `README.md`：
  - `:491` 分层图里 `ObjCIndexing  per-image index + inheritance / conformance reverse tables`
    的说明要改；
  - `:545-562` 的 ObjCIndexing 章节 —— `subclasses(of:)` / `conformingClasses(toProtocol:)`
    两行示例删除，整个 aggregate 示例段落（`:558-562`）**删除而非改写**（机制没了）；
  - 事件示例段落保留，补一句说明关系事件供调用方自行建表，并**把顺序承诺写进 README** ——
    它是契约五对外的载体。原以为 README 里已有这句，落地时核实**并没有**，唯一的载体是
    `subclasses(of:)` 的 doc comment（随该方法一并删除）。这让转移更必要而非更不必要：
    不主动补进 README，这个承诺就随方法一起消失了。
- `Documentations/Internal/ObjCRenderingAndIndexingImplementation.md`：
  - `:152-153` 那句「关系事件不需要转发 —— 它们的结果已经落在索引器自己的反向表里，
    `RuntimeRelationshipsResolver` 直接查表」在本提案后**完全反转**，必须改写；
  - `:16` 的分层图说明同步。
- `Documentations/Evolutions/README.md` 与 `Documentations/README.md`：登记 0003。
- `Documentations/Evolutions/0002-*.md`：补一句说明关系表已由 0003 移出，其泛型化不再涉及。

## API 演进与废弃策略

- 三个被删的 public API 直接删除，不设废弃期，理由见「源码兼容性」。
- 版本号按 fork 编号规则递增至 `0.8.103`。**不做 semver major 跃迁** —— 本库处于 `0.x`，
  且 fork 编号规则已与上游 tag 绑定，major 跃迁会破坏该规则；破坏性变更靠与唯一消费者的
  同批次协调管理。
- RuntimeViewer 当前 pin 的是 `exact: "0.8.102"`，适配代码与 pin bump 同批次落地。

## 与 0002 的先后

**本提案应先于 0002 落地。**

0002 要把 `ObjCInterfaceIndexer` 从只吃 `MachOImage` 泛型化到同时支持 `MachOFile`。
关系表这块恰好是泛型化里最麻烦的部分之一：`ObjCClassReference` 的 `imagePath` 在
`MachOFile` 下语义要重新定义，而 `indexCategory` 里那个 `objcCategory.class(in: machO)`
正是 0002 前期调研中点名的 `MachOFile` / `MachOImage` 双重载之一。先删掉，0002 的泛型化
面积小一圈，也不必为一段马上要删的代码设计 shim。

0002 目前是 `Draft`，尚未开始实现，因此不存在返工成本。

## 落地步骤

1. **改 `ObjCIndexingEvent` 与 `ObjCInterfaceIndexer`（一步做完）**：三个关系 case 各加一位
   `isSwiftStable` / `targetIsSwiftStable`；删掉「删除」表里的十项；`prepare()` 的两处调用
   改为直接发射事件（保持原有的顺序与非空判断），保留 category 的 `targetIsSwiftStable` 解析。
   验收：`swift build` 通过。

   *（这两件事不拆成两步：只改 enum 会让索引器内部的发射点因缺参数编译失败，一个「预期会失败」
   的验收标准等于没有验收标准。）*
2. **摘 `OrderedCollections`**：删 `import`（`:7`）与 `Package.swift:168`。
   验收：`swift build` 通过 —— 若失败说明还有未清理的 `OrderedSet` 使用。
3. **写 doc comment 契约**：五条契约分别落到 `eventHandler` 参数、`prepare()` 与
   `ObjCIndexingEvent` 的文档，见「索引器的类文档」。这一步不产生编译产物变化，但
   **不允许留到最后补** —— 契约一是本提案唯一靠文档兜住的破坏，契约五是从 `OrderedSet`
   查询结果转移过来的既有承诺，漏写等于静默撤销它。
4. **改测试**：删 `reverseTableRecordsSubclasses`（`:70-76`）、
   `reverseTableRecordsConformances`（`:78-84`）、`aggregateFansOutToSubIndexers`
   （`:129-141`，整个用例）。

   `emitsUnifiedEvents`（`:99-127`）保留并**加强**：断言事件 payload 携带 `isSwiftStable`，
   且至少存在一个 `isSwiftStable == true` 的 `.subclassIndexed`（Foundation 里有 Swift 类）。

   **新增用例一 —— 从事件流重建子类表**：断言 `NSString` 的子类里有 `NSMutableString`，
   即原 `reverseTableRecordsSubclasses` 的断言改由消费者侧路径达成，证明能力没有丢失。

   **新增用例二 —— category 路径**：断言存在 `.categoryConformanceIndexed` 事件，且能从事件流
   重建出 category 贡献的 conformer。category 是三条发射路径里**唯一做跨 image 解析**的
   （`objcCategory.class(in: machO)`），也因此是重构中最容易改错的一条，值得单独钉住。

   **不要依赖 Apple 二进制里碰巧有什么 —— 让测试自己造 fixture。** 起初设想的断言是
   「Foundation 里存在 `targetIsSwiftStable == true` 的 `.categoryConformanceIndexed`」，
   但 Foundation 与 libswiftFoundation 都在 dyld shared cache 里、磁盘上没有独立二进制，
   要确认得为 shared cache 单建 probe，成本远超这条断言的价值（由 RuntimeViewer 侧实测确认
   `otool` 直接报 "can't open file"）。而且赌 Apple 某个版本编了什么，本身就是把测试的成立
   条件交给外部。

   fixture 路线的不确定性方向是**安全**的：fixture 若没产出预期的 category，测试失败在
   「找不到 fixture category」上，是响亮的 fixture 问题，而不是静默的错误断言。

   > **待验证（落地时实测，不要凭推测写断言）**
   >
   > **fixture 的形状要选对。** 同模块内为 Swift 类写 extension，Swift 通常把 `@objc` 成员
   > 直接并进该类的 method list，**不**产出 `__objc_catlist` 条目 —— 编译器完全掌控自己模块里
   > 的类，没有理由绕 category。可靠地产出 category 记录的是**跨模块** extension：为别的模块
   > 已经定型的 ObjC 类添加成员，编译器只能走 category。所以 fixture 应当形如
   >
   > ```swift
   > @objc protocol ObjCIndexingFixtureProtocol { func fixtureMethod() }
   >
   > @objc extension NSString: ObjCIndexingFixtureProtocol {
   >     func fixtureMethod() {}
   > }
   > ```
   >
   > 索引测试 bundle 自己的 image，即可断言存在
   > `.categoryConformanceIndexed(targetClassName: "NSString", protocolName: "ObjCIndexingFixtureProtocol", …)`。
   >
   > **这个 fixture 能钉住两件事**：category 发射路径被走到；且其 `imagePath` 是**测试 bundle**
   > 而非 Foundation —— 正好把前期调研末节那个「category 的 `imagePath` 不是 target class 所在
   > image」的语义坑变成可执行的断言，比原计划更有价值。
   >
   > **它钉不住的**：`targetIsSwiftStable == true`（NSString 不是 Swift 类），以及「跨 image
   > 解析是否成功」—— `targetIsSwiftStable` 为 `false` 时无法区分「解析成功且目标非 Swift」与
   > 「解析失败兜底」，这两种情况在 payload 上同形。想同时满足「必然产出 category」和
   > 「target 是 Swift-stable 类」需要 target 类与 category 分处两个模块，得为测试新增一个
   > fixture target，成本另计，落地时按需决定。
   >
   > **落地时的执行顺序**：先确认 fixture 真的产出了 catlist 条目，再定断言；若 Swift 版本行为
   > 与上述判断不符，退化为「断言任意 `.categoryConformanceIndexed` 存在且能重建 conformer」，
   > 并在测试注释里写明为什么不能断言更强的东西。

   **新增用例三 —— 发射顺序（钉住契约五）**：契约承诺了就必须有测试，否则它只是一句愿望。
   两条断言：

   - **确定性**：对同一个 image 跑两次 `prepare()`，两次收集到的事件序列**完全相同**
     （逐条比较，含顺序）。这条不依赖任何具体的走查顺序，因此不会随实现调整而变脆，
     却能立刻抓住「并行化之后发射顺序不再确定」这个契约五要防的情况。
   - **阶段分界**：class 阶段的全部事件先于 category 阶段 —— 即最后一条 `.subclassIndexed` /
     `.conformanceIndexed` 的下标小于第一条 `.categoryConformanceIndexed` 的下标。
     这是下游逐条等价所依赖的性质里唯一一条跨阶段的，值得单独钉。

   *不*断言完整的 `__objc_classlist` 顺序：那要把二进制里的具体类顺序写进测试，会随 SDK 版本
   变化而无谓地红。确定性 + 阶段分界已经覆盖契约五的实际风险面。

   验收：`swift test` **退出码为 0**（不看 xcsift 摘要 —— 它会把失败的 swift-testing 报成 success）。
5. **改文档**：README 三处（含在事件示例里点明契约一）、
   `ObjCRenderingAndIndexingImplementation.md` 两处、两份索引登记 0003、0002 补一句。
6. **发版 `0.8.103`**，通知 RuntimeViewer 侧适配 + pin bump。

**收尾时必须判断两件事**（结果写进决策日志）：

- **要不要配套专题文章** —— 初步判断：不新写实现说明，而是**更新** 0001 的那篇
  （`ObjCRenderingAndIndexingImplementation.md`）。理由：实现说明描述的是「最终怎么实现的」，
  是活文档，实现变了它就该跟着变；本次没有引入新的「代码看不出来的决策」，只是推翻了旧的一条。
  落地时复核。
- **有没有引入新术语** —— 初步判断：没有。本提案不引入自造词，`isSwiftStable` 是
  `objc4` 的既有概念（`FAST_IS_SWIFT_STABLE`）。落地时复核。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-08-10 | Created as Draft | 起因是 0001 落地后暴露的两边不对称：ObjC 的关系反向表进了库，Swift 的还在 RuntimeViewer。用户定方向为「把 ObjC 搬回应用，Swift 不动」 |
| 2026-08-10 | 保留事件、只删存储与查询 | 备选是连事件一起删、让消费者重新走查。否决理由是走查依赖 `Dictionary` 迭代顺序，会丢掉 `__objc_classlist` 顺序这个已承诺的稳定性，造成用户可见回归；事件零存储成本且天然保序 |
| 2026-08-10 | `isSwiftStable` 进事件 payload | 消费者理论上能自算，但 category 的 target class 常在别的 image，自算要重做一遍跨 image 的 `class(in:)` 解析 —— 库已经做过一次。加一个 `Bool` 到 enum payload 零成本 |
| 2026-08-10 | `ObjCClassReference` 跟着表走，事件带平铺字段 | 弱决策。保留类型让事件带 reference 也成立，成本无差别；选平铺是因为该类型承载的是关系表语汇，表移出后留着会让边界重新模糊。评审倾向保留则不反对 |
| 2026-08-10 | **聚合机制一并删除，不给库补 `removeSubIndexer`** | 原判断是「RuntimeViewer 大概率在用 aggregate，跨 image 合并逻辑要整体搬过去，影响比表本身大」。经 RuntimeViewer 侧核实**判断有误**：该聚合只写不读（四处引用全是声明/构造/注册），跨 image 合并是 `RuntimeRelationshipsResolver` 在调用点自己做的。故聚合是纯死重，直接删，应用侧对象图零改动。同时这解掉了 feeder 分支 `f41648a`（修聚合内存泄漏）与 main 上 `889f1bd`（删掉被打补丁的类型）之间已埋下的冲突 |
| 2026-08-10 | 0001 不修改，修订记录留在本篇 | 0001 是 `Implemented` 的决策快照。当时的判断单位是文件，反向表搭着 639 行的索引器整体搬运，未被单独审视。本篇补做审视并记录结论 |
| 2026-08-10 | 提案落在 MachOObjCSection 而非 RuntimeViewer | 改的是本库的 public 表面，破坏性变更归属被改的库；且它修订 0001 的范围判断，修订记录须与被修订对象同仓才查得到。RuntimeViewer 侧登记独立的下游适配提案回指本篇 |
| 2026-08-10 | 排在 0002 之前 | 用户拍板。0003 先落地可缩小 0002 的泛型化面积（`ObjCClassReference` 的 `imagePath` 语义、`class(in:)` 双重载），且 0002 尚是 `Draft`、未开始实现，无返工成本 |
| 2026-08-10 | 不做 semver major 跃迁 | 本库在 `0.x` 且 fork 编号规则与上游 tag 绑定，major 跃迁会破坏该规则。破坏性变更靠与唯一消费者 RuntimeViewer 的同批次协调管理，递增至 `0.8.103` |
| 2026-08-10 | **补入三条调用方契约，其中契约一升级为本提案最危险的一处** | RuntimeViewer 侧评审指出：`eventHandler` 从「纯观察」变成「关系数据唯一出口」是不会被编译器捕获的破坏。其后核实的调用点数据把严重性又抬了一级 —— 该侧 7 处创建 section 的调用点只有 1 处装了 handler，且 `RuntimeEngine+BackgroundIndexing.swift:62`（后台批量索引，绝大多数 image 的来源）不在其中。若照原样落地，症状是几乎所有 image 关系表静默为空且看起来像「这个类确实没有子类」。故契约写进 `eventHandler` 参数的 doc comment 与 README，并在「源码兼容性」单列一段 |
| 2026-08-10 | 契约二（`prepare()` 非幂等）写入而非略过 | 同一轮评审提出，标为低优先级。仍决定写：核实确认 `prepare()` 无幂等守卫，五张主表走 `classes = classByName` 的替换语义、两张反向表直接 append 不重置 —— 今天重复调用安全纯粹是 `OrderedSet.append` 白送的去重。表移出后这层保护消失，而本提案又恰好建议消费者改用无锁数组 append，两者相乘会产生重复条目。一句话的成本，省不得 |
| 2026-08-10 | 落地步骤原第 1、2 步合并 | 同一轮评审指出原第 1 步的验收标准自相矛盾（写「build 通过」，括号里又说预期报错）。合并为一步，验收即 build 通过 |
| 2026-08-10 | category 测试断言标为待实测 | 评审建议新增用例断言 `targetIsSwiftStable == true` 的 `.categoryConformanceIndexed`，理由（category 是唯一跨 image 解析的路径）成立，用例采纳。但 Foundation 里是否存在这样的实例未经实测 —— 现有注释举的 NSError 例子未查证宿主 image。故写入用例但把断言强度标为落地时实测再定，并给出退化方案，不写凭推测成立的断言 |
| 2026-08-10 | **category 测试改走自造 fixture，不赌 Apple 二进制** | RuntimeViewer 侧实测确认 Foundation / libswiftFoundation 均在 dyld shared cache 内、磁盘无独立二进制，`otool` 无法打开，该断言的成立条件无法在合理成本内查证。改为让测试自带 fixture —— 其不确定性方向是安全的（fixture 没产出就响亮失败，而非静默错断言）。同时修正了对方提出的 fixture 形状：同模块内为 Swift 类写 extension 通常不产 `__objc_catlist` 条目（编译器直接并进 method list），须用跨模块 extension（如 `@objc extension NSString: <fixture protocol>`）。该 fixture 顺带把「category 的 `imagePath` 是 category 所在 image」这个语义坑变成可执行断言，比原计划更有价值 |
| 2026-08-10 | **补入契约四：不承诺 `eventHandler` 的执行上下文** | 审阅 RuntimeViewer 0007 时反向发现的库侧缺口。0003 讨论中给出的「走查单线程，可用无锁数组累积」优化建议，在下游被理解成「锁只为满足 `@Sendable` 检查，不是防竞争」—— 把当前实现细节当成了 API 契约。库保留 0002 之后并行化走查的余地，故明确不承诺执行上下文。优化本身仍成立，但理由是「当前无竞争、锁成本接近零」而非「锁可去掉」 |
| 2026-08-10 | **补入契约五：承诺事件的相对发射顺序确定** | 契约四提出后由 RuntimeViewer 侧指出：它连带把「发射顺序」一起放掉了，而两者可分、下游依赖的是后者。决定**承诺顺序、不承诺执行上下文**，理由有三：(1) 这不是新增承诺而是转移 —— 顺序保证今天挂在 `OrderedSet` 查询结果上（`subclasses(of:)` 的 doc comment 已写明），表移出后不转移到事件上等于静默撤销一个已对外给出的保证；(2) 不承诺会让本提案自相矛盾 —— 否决「让消费者重新走查」的决定性理由正是走查丢掉 `__objc_classlist` 顺序稳定性，事件流若也不保序，那条否决理由塌掉一半；(3) 代价小 —— 并行化的收益在解析而非发射，「并行解析 + 有序归并」是标准形状。另备选是显式写「不承诺顺序」，下游改为集合等价 + 应用侧排序，但那会带来 Relationships 顺序不再是二进制声明顺序的用户可见变化，未采纳 |
| 2026-08-10 | 契约五配套测试：只测确定性与阶段分界 | 承诺了就要测，否则契约只是愿望。但不断言完整 `__objc_classlist` 顺序 —— 那要把二进制里的具体类顺序写进测试，会随 SDK 版本无谓地红。「两次 `prepare()` 事件序列完全相同」+「class 阶段全部先于 category 阶段」已覆盖契约五的实际风险面，且不随实现调整变脆 |
| 2026-08-11 | 批准，状态转 Accepted → In Progress | 用户批准后按落地步骤实施 |
| 2026-08-11 | **fixture 方案实测成立，但需要显式 ObjC 运行时名** | 落地时按待验证项实测：跨模块 `@objc extension`（`extension NSString: ObjCIndexingFixtureProtocol`）**确实**产出 `__objc_catlist` 条目，判断正确。但首跑失败于「找不到 fixture category」—— 原因是 `@objc protocol` 未指定运行时名时，Swift 以 mangled 形式（`_TtP<模块><名字>_`）暴露给 ObjC 运行时，而索引器读到的正是 mangled 拼写。加 `@objc(ObjCIndexingFixtureProtocol)` 后通过。**这次失败正是选择 fixture 路线的理由本身**：不确定性以「响亮失败」而非「静默错断言」的形式出现，10 分钟定位 |
| 2026-08-11 | category 测试最终形状：钉住 `imagePath` 语义，不钉 `targetIsSwiftStable` | 按提案预案执行。fixture 的 target 是 `NSString`（非 Swift 类），故 `targetIsSwiftStable` 断言不了 `true`；但断言了 `imagePath == 测试 bundle` 且 `!indexer.classNames.contains("NSString")` —— 把「category 的 `imagePath` 是 category 所在 image、不是 target class 所在 image」这个语义坑变成了可执行断言。这是原计划（在 Foundation 里碰运气）拿不到的 |
| 2026-08-11 | **修正提案自身的一处事实错误：README 从未写过顺序承诺** | 契约五的论证中曾引用「`README.md:556` 也写明了插入顺序保留」。落地时核实 README **没有**这句，顺序承诺的唯一载体是 `subclasses(of:)` 的 doc comment。修正后论证不但成立而且更强：唯一载体随方法一并删除，不主动补进 README 就等于让这个承诺无声消失。四处引用已更正 |
| 2026-08-11 | 实现完成，状态转 Implemented | `ObjCIndexingTests` 全绿（swift-testing 33 tests / 4 suites，含新增三个用例）。`Tests/MachOObjCSectionTests` 有两处失败，经查证**与本次改动无关**：其 `setUp` 硬编码了 `/Users/JH/Downloads/iOS18.5-SwiftUI`（本机不存在），失败进而使 `machOFileInCache!` 强解包崩溃；该文件最近一次改动来自上游 merge `6074f84`，属 fork 的既有环境依赖问题，不在本提案范围内 |
