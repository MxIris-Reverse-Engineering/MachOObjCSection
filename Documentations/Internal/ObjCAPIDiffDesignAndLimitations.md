# ObjC API Diff — 设计与已知局限

> 面向维护者的实现说明。对应提案 [0006](../Evolutions/0006-objc-api-diff-and-evolution.md)；
> 「image 组」一节对应提案 [0016](../Evolutions/0016-objc-evolution-image-groups.md)；
> 「同一容器里的重复成员」一节对应提案
> [同一容器里的重复成员按来源取舍，内容相同的不再告警](../Evolutions/draft-objc-duplicate-member-selection.md)。
> 记录 `ObjCDiffing` 模块（ObjC API 比对引擎）的架构、关键设计取舍，以及一组当前的
> 已知局限——大多数源于 ObjC metadata 本身携带的信息边界，而非实现取巧。
>
> 参考实现：MachOSwiftSection 的 `SwiftDiffing`
> （其设计文档 `ABIDiffDesignAndLimitations.md` / `ABIEvolutionDesign.md`）。本文只展开
> ObjC 侧**不同**的部分；与参考实现逐点一致的算法（三路匹配、容器的 first-wins keying、
> evolution 的逐版本矩阵、N == 2 与双侧 diff 的一致性保证）不重复论证。

## 概述

`ObjCAPIDiffer` 比对两个二进制的 ObjC API：把每个声明按其运行时身份
（类名 / 协议名 / category uniqueName / selector）建索引，对 classes、protocols、
categories 三个 bucket 做递归三路集合差分。diff 本身不接触 Mach-O——一旦
`ObjCAPISnapshotBuilder`（`ObjCInterface`）把索引结果组装成 `ObjCAPIModule`，
之后的一切都是纯值计算。

三个入口共用一套算法：live（`diff(old: ObjCAPIModule, new:)`，先冻结再比）、
document（`diff(old: ObjCAPISnapshotDocument, new:)`，带 provenance）、
frozen（`diff(old: ObjCAPISnapshot, new:)`，纯值）。

## 与 SwiftDiffing 的语义差异（有意为之）

| 维度 | SwiftDiffing | ObjCDiffing | 理由 |
|---|---|---|---|
| 身份 | remangle 后的 mangled symbol（`.mangled`/`.printed` 双 case + 回退诊断） | 命名空间字符串（`method:-foo:` 等），无回退路径 | ObjC 身份是纯名字，remangle 及其全部复杂度不存在 |
| function/method 换签名 | removed + added（换 mangled symbol = 换 ABI 入口点） | **modified**（selector 不变即同一入口，typeEncoding 进 payload） | ObjC 的派发身份是 selector 本身 |
| 容器 kind 变化 | 折入容器身份（struct↔class 报 removed+added） | superclass 作为**伪成员**（换父类报 modified，old → new 并列） | 类名是稳定身份，整类 removed+added 会淹没「其余成员未变」的信息 |
| 诊断通道 | 键碰撞 + remangle 回退两类 | 仅键碰撞一类 | 无 remangle；成员级碰撞的现实来源是链接期并进类的 category，容器级的是 image 组里的同名类 |
| 一个容器里重复的身份 | first-wins | 先排除协议副本再取第一份，内容相同的不告警（见「同一容器里的重复成员」） | 系统框架的类里重复成员是常态，first-wins 会取到协议抄来的声明 |
| 顶层 bucket | 8 个（types/protocols/4×extension/2×global） | 3 个（classes/protocols/categories） | ObjC 无 extension 拆分问题，无 global 声明 |

## 键格局（即持久化格式）

`ObjCAPIKey` 的命名空间字符串是 `ObjCAPISnapshotDocument` 的事实序列化格式，
**任何变更必须 bump `currentFormatVersion`**（当前 = 1）：

| 实体 | identityKey | payloadKey |
|---|---|---|
| method | `method:-<sel>` / `method:+<sel>` | `enc:<typeEncoding>`（协议成员追加 `\|optional:0/1`） |
| property | `property:-<name>` / `property:+<name>` | `attr:<normalized>`（剥 `V` 段；协议成员同上） |
| ivar | `ivar:<name>` | `enc:<typeEncoding>` |
| protocol 采纳 | `adopts:<name>` | = identity |
| superclass 伪成员 | `superclass` | `super:<name>`（root class 为空串） |
| 容器 | `class:` / `protocol:` / `category:` + 名字 | —（成员递归 diff） |

### 三个刻意排除的字段

- **`ObjCMethodInfo.imp`** —— 地址，逐次构建都变，进 key 会让一切都 modified。
- **`ObjCIvarInfo.offset`** —— non-fragile ABI 下由运行时滑动，且一处中插会级联
  modified 其后所有 ivar。类型变化（`enc:`）仍然可见；纯布局位移不可见（见局限 3）。
- **`ObjCClassInfo.instanceSize` / `.imageName` / `.version`** —— 派生值 / 环境值。

### property payload 为什么剥 `V` 段

`attributesString` 的 `V<ivarName>` 是合成 backing ivar 名，属实现细节：
它的变化在 ivar 轴上以 `ivar:_old` removed + `ivar:_new` added 的形式已经可见，
折入 property payload 只会把同一件事报两遍。剥除走解析后的
`attributes: [ObjCPropertyAttribute]` 过滤 `.ivar` case 再 `encoded()` 重组——
**不要**用逗号 split 原始串（类型段 `T@"NSDictionary<NSString *,NSNumber *>"`
里有引号内逗号）。

### 协议成员的 optionality 走 payload 不走 identity

required ↔ optional 迁移在同一 selector 上发生，identity 折入 optionality 会把它
错报成 removed + added。payload 折入后如实报 modified。同一版本内一个 selector
不会同时出现在 required 与 optional 组（runtime metadata 结构保证），所以无碰撞。

## 兼容性判定

基线规则（added → additive；removed / modified → breaking）之上只有一条
record 级 refinement：**协议新增 required 成员 → breaking**（现有 conformer 缺实现），
新增 optional 保持 additive。结构与参考实现的 `hasDefaultImplementation`
refinement 同构，同一函数（`ObjCMemberRecord.compatibilityOverride(old:new:)`）
被双侧 differ 与 evolution builder 共用，N == 2 时两条路径的 verdict 不可能分叉。

**协议新采纳另一个协议**按同一条理由判定（见提案
[0013 协议新采纳另一个协议时按破坏性改动判定](../Evolutions/0013-protocol-adoption-compatibility.md)）：
`@protocol P <Q>` 把 Q 的必选成员同样加到 P 的 conformer 头上。协议容器新增的 `adopts:<Q>`，
在新快照的协议表里把 Q 连同它自己的采纳逐层展开，只要有一个必选成员不在旧快照里 P 已要求的
必选成员中（同样逐层展开），就是 breaking；Q 不在新快照里、无法展开时也判 breaking。类与
category 新采纳协议仍是 additive，它们是在提供实现。这条判定要看两侧的协议表，单条 record
看不出来，所以放在容器层：`ObjCMemberRecord.adoptionCompatibilityOverride` 由双侧 differ 与
evolution builder 共用，各自传入相邻两个快照的 `ObjCProtocolRequirements`。

## 同一容器里的重复成员

一个容器的成员里，同一个 identity 可以出现好几次。系统框架的类里这是常态，来源有两步：

- **链接器把 category 并进类。** ld64 默认（`-no_objc_category_merging` 才关）把本 image 里加在本 image 类上的
  category 合并进类自己的方法表、属性表与协议表：category 的列表依次在前，类自己的放最后，不去重
  （`/Volumes/AppleOSS/distribution-Developer_Tools/ld64` 的 `src/ld/passes/objc.cpp`，`PropertyListAtom`）。Swift 类
  不合并。所以 AppKit 的 `__objc_catlist` 里几乎只剩加在别的 image 的类上的 category。
- **clang 把协议的属性抄进 category。** 编译一个采纳了协议的 category 时，协议（连同它采纳的协议）声明的每个属性都
  抄一份进这个 category 的属性表（`clang/lib/CodeGen/CGObjCMac.cpp` 的 `PushProtocolProperties`，同一张表内按名字
  去重）。协议大多继承 `<NSObject>`，于是每个这样的 category 都带一份 `hash`、`superclass`、`description`、
  `debugDescription`。

两步叠起来，NSApplication 的属性表里这四个属性各有 4 份；`NSView` 从 macOS 13 起经合并进来的 category 采纳
`NSLayoutItem`，这个协议的只读 `frame` 排到了类自己的可写 `frame` 前面。macOS 27.0 的 AppKit 有 216 组这样的重复、
330 份多出来的记录，其中 304 份与第一份的 payload 相同。运行时看到的也是这些重复：`class_getProperty` 返回第一份。

**取哪一份**（`ObjCMemberSelection`）：先认出**协议副本**——identity 与 payload 都和容器所采纳协议声明的某个属性相同的
记录。协议沿 `adopts:` 记录在快照协议表里逐层展开，比较时去掉协议成员 payload 末尾的 `|optional:` 段
（`ObjCProtocolPropertyDeclarations`）；不在表里的协议展开不了，它的副本当成容器自己的声明。非协议副本里取第一份，
全是协议副本时取第一份。方法没有协议副本，取第一份，也就是运行时派发到的那份：合并进来的 category 方法排在类方法前面。

**什么时候告警**：被丢的记录只有不是协议副本、payload 又和保留的那份不同，才进 key collision，并写明保留的是哪份
（`ObjCAPIKeyCollision.keptSignature`）。payload 相同的丢了什么也不少；协议副本重复的是协议的声明，它的变化由协议自己
的容器报告。27.0 的 AppKit 按这条规则剩 8 组告警，都是两份都不是协议副本、彼此又不同，分不出该比较哪份
（`NSMenuItemBadge.stringValue`、`NSTextInputContext` 的三个属性等）；另有 15 组从协议副本改取类自己的声明，
`NSView.frame` 那条「13.0 改成 readonly」的假变化因此消失。

**为什么在配对时做，不在冻结快照时去重**：快照是未过滤的事实（局限 2）。冻结时去重还得升快照格式版本，否则带重复的
旧 baseline 对去重后的新快照会取到不同的一份，报出假变化。现在旧 baseline 不用重新生成，也按同一条规则比较。

**为什么不取最后一份，也不挑「更强」的一份**：类自己的列表虽然排在最后，但 `NSTextView.defaultParagraphStyle` 这类
可写声明写在 category 里，类自己的列表里只有协议的只读副本，取最后一份反而取错。「可写优先、类型具体的优先」说不清：
`NSScreen.hash` 两份的差别是 `unsigned long long` 对 `long long`。

**只有协议副本时写明来源**：一个属性在某版本只剩协议副本，说明它在容器里只是因为采纳了声明它的协议。这时的增删改
未必是 API 的增删改：NSView 的锚点在 SDK 里写在分类 `NSView (NSConstraintBasedLayoutInstallingConstraints)` 中、标
`macos(10.11)`，可那个分类不留属性记录（12.7 的 NSView 只有取值方法），13.0 起经并进类的分类采纳 `NSAKLayoutItem` 才有了
协议副本。二进制分不清这种情况与私有方法后来公开：`NSBezierPath.CGPath`、`accessibilityUserInputLabels` 也是取值方法早就
在、属性记录后来才出现，SDK 却都标 `macos(14.0)`，那次出现正是公开的时候。所以不改事件，只陈述来源：
`ObjCMemberSelection.keptProtocolNameByKey` 给出取到的那份是哪个协议的副本，`ObjCLineageEvent` 与 `ObjCMemberChange` 的
`viaProtocolName` 记下它（新增与修改看新的一侧，删除看旧的一侧），报告写成 `+ added in 13.0 via <NSAKLayoutItem>`、
diff 写成 `… (via <NSAKLayoutItem>)`，合并头文件写成 `added in 13.0 via <NSAKLayoutItem>`，并且新增或删除带着协议的
成员不写可用性宏——宏会被读成 SDK 的可用性。声明它的协议取离容器最近的那个（按采纳关系的层数，同层取先采纳的），
`ObjCProtocolPropertyDeclarations` 为快照里每个协议预先算好它展开后的声明与最近的声明者，查一条记录只需按容器采纳的
几个协议各查一次表。

**一处定规则**：双侧 differ、evolution builder 与 `ObjCAPISnapshot.keyCollisions()` 都取 `ObjCMemberSelection` 选的
那一份；公开的测试接缝 `diffMembers(old:new:)` 拿不到协议表，取第一份。合并头文件（`ObjCEvolutionInterfaceBuilder`）
也写这一份，写在它在成员表里的位置：`ObjCAPISnapshot.keptMemberOccurrences()` 给出每个重复的 identity 取第几份，渲染与
`ObjCEvolutionMemberLayout` 边走边数。image 组里 category 的成员跨 image 拼接，取哪份要看整组，所以
`addVersion(images:version:)` 先取齐每个 image 的快照、合并，再渲染。容器级（一个轴上两个同名容器）仍是 first-wins：
一个链接出来的 image 里没有同名容器，现实来源只有 image 组。

## image 组：几个 image 当作一个 API 面

单 image 演进里，从 AppKit 搬到 UIFoundation、CollectionViewCore 的声明在 AppKit 一侧报成 removed，在新库一侧
报成 added，其实它们没有消失。`evolution(ofImageGroups:versions:)` 让每个版本交一组 image（主 image 在前，image 名由
调用方给），先把一个版本的几个 image 合并成一份快照，再走同一套逐版本矩阵；搬家另记成 `ObjCImageMove`。事件因此
就是「对两侧合并后的快照做 diff」的结果，判定规则一条没变。

**一个版本内怎么合并**（`ObjCAPIImageGroupMerge`）：

- **class**：所有 image 的都列入，按组顺序。两个 image 都有的类留两个容器，first-wins 比较第一个 image 的，另一个记成
  key collision。上文局限 6 的订正说单 image 里这条诊断触发不了；跨 image 的重复类正是它在 image 组里的现实来源。
- **category**：unique name 相同的合成一个容器，成员按组顺序拼接——运行时把它们都挂到同一个类上。同一个 selector
  在两个 image 里各有一份时，按上一节的规则取舍：两份不同才报成员级 key collision，相同的不报。
- **protocol**：每个引用它的 image 都在 `__objc_protolist` 里带一份 `protocol_t`。dyld 的 cache builder 只把
  `__objc_protorefs` 与类、category、协议里的引用改指向一份规范副本，`__objc_protolist` 留在各 image 自己的副本上
  （`dyld/cache_builder/NewSharedCacheBuilder.cpp` 的注释："We do NOT update __objc_protolist"）。所以 AppKit 和
  UIFoundation 各带一份 `NSCopying` 是常态：内容相同的副本静默去重；内容不同的留下，于是撞键、比较第一份。
- key collision 在 image 组里注明保留与被丢的那几份各来自哪个 image（`ObjCAPIKeyCollision.keptImageName`，以及与
  `droppedSignatures` 一一对应的 `droppedImageNames`），单 image 时为 nil。

**搬家的规则**：

- 声明在一次跳变两侧都在场才比较；一侧的 image 集合是该版本里含有它的全部 image。集合按各自版本的组顺序存，比较时
  不看顺序。
- 容器两侧集合不同就记一次搬家。成员要两侧集合不同，**并且**（旧, 新）与所属容器的（旧, 新）不同才记：整个类搬走时，
  每个方法都跟着换了 image，再记一遍只是重复；category 拆成两个 image 后，换了 image 的方法单独记，留下的不记（只比
  「与容器不同」的话，留下的方法会被记成 `AppKit → AppKit`）。
- protocol 没有「所在的 image」，不记搬家。
- 只有搬家的 lineage 也要列出来；这样的成员没有事件可取签名，签名放在 `ObjCMemberLineage.latestSignature`（它最新
  出现那一版的渲染，有事件时为 nil）。
- 搬家不影响判定。按旧 install name 绑定的符号还能不能找到，取决于旧 image 有没有 re-export 新 image，快照里没有
  这个事实，所以只报不判。

**报告**（`ObjCAPIEvolutionReporter`）：头部那行下面紧跟「Image group:」，每个 image 一行存在位图，按它在轴上首次
出现的顺序排（先看旧版本，同一版本内按组顺序），`summary` 也带。搬家写成 `> moved in 14.0: AppKit → UIFoundation`，
集合用 ` + ` 连接，与事件按版本合在一起排，同一个版本里事件在前。跳变摘要在 added / removed / modified 之后加
`N moved`；只有搬家的一步照常给 verdict 词。key collision 警告先写保留的那份、再写被丢的那几份，各自在签名后用括号
注明 image。搬家短语与警告的写法放在 `ObjCDiffing` 的 package 级扩展里（`ObjCImageMove.phrase(versionLabel:)`、
`ObjCAPIKeyCollision.warningsHeading` 与 `recordsDescription`），双侧 diff 的报告、演进报告与合并头文件末尾用的是同一份。

**警告的写法**：标题是 `Warnings — identity-key collisions (only the kept record was compared):`，每条写成
`<版本> · <容器> · kept: <签名> · dropped: <签名>, …`（容器级的碰撞没有容器一段，签名就是容器名）。保留的那份在
「同一容器里的重复成员」一节之前一律是第一份，报告里也不写，所以旧版本编出来的 JSON 没有 `keptSignature`；这样的
碰撞只写 `dropped:` 一段。这里的写法从此与 Swift 一侧不同：SwiftDiffing 仍取第一份，标题照旧。

**内存**：成员的 image 归属只为两个以上 image 拼成的容器单独保存，其余成员沿用容器的归属——跨 51 个版本的 AppKit
若每个成员都存一份，会再多出一份与快照同量级的数据。

**与 Swift 一侧**：MachOSwiftSection 的 SwiftDiffing 按同一套模型与报告文案做，两边的类型名对应（`ObjCImageMove` ↔
`ImageMove` 等）。Swift 一侧多一个 `earliestVersionIndex`：被剥掉 local 符号的版本里声明看不见，搬家只能落在两次
观测之间；ObjC 没有这种情况。

## 已知局限

### 1. ObjC 无访问控制 → 判定分不出公开 API 与私有实现

二进制里的每个 selector 地位相同。私有 helper 的重命名与公开 API 的删除都报
breaking，读者需自行结合语义判断。与参考实现「`@frozen` 不可恢复，一律按
resilient 处理」同属「宁可诚实保守，不可自信出错」的取舍。

### 2. 快照是「未过滤」的 metadata 事实，与渲染的 strip 语义无关

`ObjCInterfaceBuilder` 的 strip（剥合成访问器等）是渲染视图的关切；快照固定投影
完整模型，与 `ObjCGenerationOptions` 无关——否则同一二进制在不同选项下产出不同
baseline。后果：property 的 attribute 变化和它的合成 getter/setter 的 typeEncoding
变化可能同时上报，这是如实反映 metadata，不视为重复噪声。

### 3. ivar 纯布局变化不可见

offset 不折入 payload（见上），所以「类型不变、只有布局位移」的 ivar 变化不产生
任何报告。需要布局敏感比对时（对齐、打包变化），是未来的独立维度，不是把 offset
塞回 payload——那会把每次中插放大成整列表 modified。

### 4. 超类链成员不进本类容器

`ObjCClassGroup.info` 首元素是类自身，其余是超类链；快照只投影首元素。
继承来的成员属于超类自己的容器，重复投影会把一次超类变化放大成 N 个子类的变化。
代价：文件模式下超类链截断的那条既有限制（见 CLI 指南「必须知道的几件事」）
对 diff 无影响——diff 根本不看链。

### 5. 递归协议树只取第一层

`protocols` 数组是递归物化的树，快照只取第一层的 `name`（即直接采纳）。
间接采纳的变化由对应协议自己的容器报告。这也避免了把树序列化进 baseline 的
指数膨胀。判定协议新采纳是否 breaking 时要用到间接采纳，它不读这棵树，而是在快照的
协议表里按名字逐层查（见上文「兼容性判定」）。

### 6. category 同名合并风险

category 身份是 `ClassName(CategoryName)`。同一二进制里对同一类声明两个同名
category 是运行时允许的（后果自负），会触发键碰撞诊断——first-wins 保留第一个，
Warnings 段列出被丢弃的。

> **2026-10-27 订正**：这条诊断对类和 category 实际上触发不了。索引器按名字存类和 category，同名项在进入
> 快照之前就只剩一个；而正常链接出来的镜像里也不会有同名项——同名类在链接时撞符号，同一类的同名 category
> 被合并成一个（实测本仓库测试包里两个文件对 NSString 的 Swift 扩展只剩一个 category）。上表「诊断通道」
> 一行说碰撞的现实来源是 duplicate class，同样不成立：运行时的 duplicate class 告警说的是两个镜像。
> 裁决与推翻条件见 [代码审查的已裁决清单](CodeReviewAdjudications.md)。
>
> **2026-10-29 补记**：上面说的只是容器级。成员级的碰撞在单 image 里非但触发得了，还是常态——链接器把 category
> 并进类，留下大量重复成员，见上文「同一容器里的重复成员」。

## 测试结构

- `Tests/ObjCDiffingTests/` —— 纯值单元测试：投影键格局、三路匹配、
  refinement、codec（round-trip / 缺版本头 / 版本不符 / 字节稳定）、evolution
  形状（presence 位图 / 缺口语义 / N == 2 一致性 / 标签解析）、两个 reporter 的
  整段文本断言；image 组的合并与搬家规则（`ObjCAPIImageGroupEvolutionTests`），
  单 image 演进的 JSON 与报告在加入 image 组前后不变（`SingleImageEvolutionOutputTests`），以及
  一个容器里重复成员的取舍与告警（`DuplicateMemberSelectionTests`，用例按 AppKit 的真实情形构造）。
  全程无 Mach-O、无 runtime。
- `Tests/ObjCInterfaceTests/ObjCAPISnapshotBuilderTests.swift` —— 进程内
  Foundation 镜像的冒烟：module 组装（own-declaration only）、快照确定性、
  自 diff 为空、经 document 往返。
- `Tests/ObjCInterfaceTests/ObjCEvolutionInterfaceArchivedCacheTests.swift` —— 归档 cache 里 AppKit 的
  11.0.1、12.0.1、13.0 合并成一份头文件，其中两条钉住重复成员的真实情形：`NSView.frame`/`bounds` 在 13.0 多出排在前面的
  协议副本，`NSMenuItem.action`/`tag`、`NSWindow.contentView` 整条轴上协议副本都在前面；合并头文件都写类自己的声明、
  不带标注。另一条钉住只剩协议副本的 `NSView.leadingAnchor`：标注写 `added in 13.0 via <NSAKLayoutItem>`，不写可用性宏。
  cache 不在时整组跳过。
- `Tests/ObjCInterfaceTests/ObjCEvolutionInterfaceDumpTests.swift` —— 给维护者看的导出，不做断言：把 AppKit、UIFoundation、
  CollectionViewCore、CoreAutoLayout 这一组在全部 51 个归档 macOS 版本上合并成一份头文件，写到
  `~/Documents/SwiftInterfaceTests/macOS-<SDK>-AppKit+…-ObjCEvolutionInterface-MachOObjCSection.h`。移植自 MachOSwiftSection 的
  `ObjCEvolutionInterfaceTestSuite.AppKitImageGroupArchivedDyldCacheTests`，版本轴、标签与可用性宏都一样；补不了没有 class
  object 的 Swift 类（那要读 Swift metadata），所以比那边的少这些类，文件名另带后缀、不覆盖那边的。要几分钟，只在设了
  `MACHO_OBJC_SECTION_DUMP=1` 时运行，用 release 构建（`swift test -c release -Xswiftc -enable-testing`）快得多。
- 手工端到端验证（2026-08-20）：macOS 15.5 vs 26.5.2 两份 dyld shared cache 的
  CoreLocation，`snapshot` → `diff`（644 行报告，捕捉到 CLBeaconRegion 等类的
  真实属性删除）→ `evolution --summary-only`（226 added · 197 removed ·
  67 modified · API-breaking）→ `--fail-on-breaking` 退出码 1 / 自 diff 退出码 0。

## 与提案的差异

无实质偏离。提案「详细设计」中的类型与签名即最终实现；`ObjCAPIDiffer` 额外公开了
`diffMembers(old:new:)` 作为测试接缝（参考实现同款）。
