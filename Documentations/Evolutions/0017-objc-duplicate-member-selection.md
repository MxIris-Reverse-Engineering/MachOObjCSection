# 0017 - 同一容器里的重复成员按来源取舍，内容相同的不再告警

- **状态**: Implemented
- **创建日期**: 2026-10-29
- **最后更新**: 2026-10-30
- **实现分支**: `feature/objc-duplicate-member-selection`
- **配套文档**: [实现说明「同一容器里的重复成员」](../Internal/ObjCAPIDiffDesignAndLimitations.md#同一容器里的重复成员)；
  使用指南[合并头文件一节](../Guides/ObjCSectionCommandLine.md#库调用方把-n-个版本合并成一份带演进标注的头文件)与
  [image 组一节](../Guides/ObjCSectionCommandLine.md#库调用方几个-image-当作一个-api-面)；术语表的
  [protocol copy](../Glossary.md#protocol-copy协议副本)

## 摘要

diff 和演进按 identity key 配对成员；同一个容器里一个 key 出现几次时，现在一律比较第一份，其余的列进 key collision
警告。代码注释与实现说明都认为单个 image 里碰不到这种情况，实际上系统框架里很常见：链接器默认把本 image 里加在本 image
类上的 category 并进类本身，category 的列表在前、类自己的在最后，不去重（ld64 `src/ld/passes/objc.cpp` 的
`PropertyListAtom`）；clang 又会把 category 所采纳协议的属性抄一份进 category 的属性表（`CGObjCMac.cpp` 的
`PushProtocolProperties`）。macOS 27.0 的 AppKit 因此有 216 组重复、330 份被丢的记录，51 个版本的 AppKit image 组演进
有 8199 行警告。其中 304 份与保留的那份 payload 相同，是纯噪音；26 份不同，而排在前面的常是协议抄来的只读声明：合并头文件
把 `NSView.frame`/`bounds`、`NSWindow.contentView`、`NSMenuItem.action`/`tag` 写成 `readonly`，还把 `NSView.frame`/`bounds`
报成 13.0 改成了 `readonly`、判为破坏性——13.0 起 NSView 经合并进来的 category 采纳了 `NSLayoutItem`，它的只读 `frame`
排到了类自己那份前面，类自己的声明其实没变。本案改掉取舍规则，让警告只剩真正分不出取哪份的情况。

## 方案

- **取哪一份**：先认出**协议副本**——key 与 payload 都和容器所采纳协议声明的某个属性相同的那份。协议沿 `adopts:` 记录在
  快照的协议表里逐层展开（与 `ObjCProtocolRequirements` 同样的走法），比较时去掉协议成员 payload 末尾的 `|optional:` 段。
  非协议副本里取第一份，全是协议副本时取第一份。方法没有协议副本（clang 只抄属性），仍取第一份，与运行时 category 方法
  排在类方法前面的顺序一致。
- **什么时候告警**：只有被丢的非协议副本与保留的那份 payload 不同才算 key collision。payload 相同的丢了什么也不少；协议
  副本的变化由协议自己的容器报告。按 27.0 的 AppKit 推演：告警从 216 组降到 8 组（`NSMenuItemBadge.stringValue`、
  `NSTextInputContext` 的三个属性等，两份都不是协议副本、彼此不同）；15 组改取类自己的声明。
- **一处定规则，四处共用**：双边 differ、evolution builder、`ObjCAPISnapshot.keyCollisions()` 与 `ObjCEvolutionInterfaceBuilder`
  的成员渲染现在各自取第一份，改成调用同一个选择函数，比较的、告警的、写进合并头文件的始终是同一份。image 组里跨 image
  拼成的 category 同样适用，渲染要等整组交齐、知道取哪份之后再挑。
- **快照格式不变**：快照仍记下二进制里的每一份（实现说明局限 2：快照是未过滤的事实），取舍只在配对时做。旧 baseline 不用
  重新生成，也按新规则比较。
- **告警文案**：标题里的「first record kept, later ones not compared」改成按新规则的说法；每条告警加上保留的那份签名，
  `ObjCAPIKeyCollision` 新增可选的 `keptSignature`，没有它的旧 JSON 照样能解码。MachOSwiftSection 的 SwiftDiffing 仍取第一份，
  两边文案从此不同。
- **只有协议副本的属性写明来源**：一个属性在某版本只剩协议副本时，它在那一版的增删改是采纳的协议带来的，未必是新 API。
  NSView 的锚点就是这样：SDK 写的是 `macos(10.11)`，头文件把它们声明在分类里、编不出属性记录，13.0 起经合并进类的分类采纳
  `NSAKLayoutItem` 才有了协议副本，演进却报「13.0 加入」并写 `API_AVAILABLE(macos(13.0))`。从二进制分不出这种情况与私有
  方法后来公开（`NSBezierPath.CGPath`、`accessibilityUserInputLabels`，SDK 都写 14.0），所以只陈述事实：事件带上声明它的
  协议（`ObjCLineageEvent` 与 `ObjCMemberChange` 新增可选的 `viaProtocolName`；新增与修改看新的一侧，删除看旧的一侧），
  报告与合并头文件写成 `added in 13.0 via <NSAKLayoutItem>`；新增或删除带着协议的成员不写 `API_AVAILABLE` /
  `API_OBSOLETED`。声明它的协议取离容器最近的那个：按容器采纳的顺序逐层展开，先遇到哪个协议自己声明了它就是哪个。
- **不改的**：`objc dump` / `interface` 照原样打印每一份；同名类与 protocol 副本这两种容器级告警不变。
- **测试**：`ObjCDiffingTests` 加纯值用例，先确认改前失败——NSView 的情形（新版本多出一份排在前面的只读协议副本，现在报
  modified，改后无事件、无告警）、payload 相同的重复不告警、两份不同的非协议副本仍告警并带保留的签名。
  `ObjCEvolutionInterfaceArchivedCacheTests` 已在合并 12.0.1 → 13.0 的 AppKit，加一条断言 `NSView.frame` 写成可写、没有标注。
- **文档**：实现说明加一节讲重复成员从哪来、怎么取舍，订正局限 6、`Keying.swift` 与 `ObjCAPIKeyCollision` 注释里「现实来源只有
  同名类」的说法；已裁决清单 2026-10-27 那条补记成员级的来源；使用指南「identity 相同的成员只写第一条」与 image 组一节
  改成新规则；术语表加「协议副本」。落地后打 tag，MachOSwiftSection 升依赖后 `swift-section objc diff` / `evolution` 的输出
  随之变化。

## 落地步骤

每一步单独构建通过、相关测试通过后提交，文档随所在的那一步一起提交。修复类的测试先确认在改动前失败。

- [x] 1. 取舍规则：认出协议副本，按新规则为每个 identity key 取一份；双边 differ、evolution builder、`keyCollisions()`
  与合并头文件（单 image 与 image 组）共用它；`ObjCAPIKeyCollision` 记下保留的那份。纯值回归测试与归档 cache 测试
  （`NSView.frame`）；实现说明、使用指南、代码注释、已裁决清单与术语表。
- [x] 2. 报告：两个 reporter 与合并头文件末尾的警告标题，以及保留那份的写法；报告测试。
- [x] 3. 完整验证：全量测试，含 CI 用的 Xcode 26.6；用本分支的命令行重跑几版 AppKit 的演进，对照警告数与 `NSView.frame`，
  结论写进本提案。在 Ultra 上：CI 那组测试（`swift test --skip MachOObjCSectionTests`）在默认的 Xcode 27.2（Swift 6.4.2）与
  CI 用的 Xcode 26.6（Swift 6.3.3）下都通过；归档 cache 的两个测试（`NSView.frame`/`bounds`，以及整条轴上协议副本都排在
  前面的 `NSMenuItem.action`/`tag`、`NSWindow.contentView`）放进 `next` 的源码里跑都失败，在本分支通过。用命令行对 AppKit
  的 12.0.1 → 13.0 → 27.0 跑演进：告警从 485 行（每版 126、136、223 行）降到 22 行（6、7、9 行），剩下的都是两份都不是
  协议副本、彼此又不同的；报告正文与 `next` 相比只少了三条假变化（`NSView.frame`、`bounds` 在 13.0，`NSPopover.detached`
  在 27.0），`NSScreen.hash`、`debugDescription` 改写成类自己的声明。release 构建三次各跑一遍，`next` 6.35–6.56 秒，
  本分支 6.35–6.49 秒，看不出差别。用移植来的导出测试生成 51 个版本的 AppKit 图像组合并头文件：`next` 上的那份告警 8198
  行，与 MachOSwiftSection 生成的完全一样（只少了它补充的 36 个 Swift 类）；本分支降到 385 行，正文只有 21 行不同，全是
  预期的修正——`NSView.frame`/`bounds`（13.0）、`NSPopover.detached`（14.4）、`headerLevel`（12.0、14.4）的假变化去掉，
  `NSMenuItem.action`/`tag`、`NSWindow.contentView`、`NSResponder.touchBar` 等改回可写。
- [x] 4. 只有协议副本的属性写明来源：`viaProtocolName`，两个报告与合并头文件的写法，不写可用性宏；纯值测试、报告测试与
  归档 cache 测试（`NSView.leadingAnchor`）；实现说明、使用指南与术语表；重新生成 51 个版本的头文件核对。归档 cache 测试
  在改动前失败（写的是 `leadingAnchor API_AVAILABLE(macos(13.0));` 与 `added in 13.0`），改后通过。重新生成的 51 个版本
  头文件里：NSView 的锚点写成 `added in 13.0 via <NSAKLayoutItem>`、不带宏；1,204 处标注写明了协议，其中 411 处是所有类上的
  `modified in 14.4 via <NSObject>`（NSObject 协议自己的 `debugDescription` 在 14.4 变了，以前看不出缘由）；可用性宏从
  17,088 行减到 16,474 行。

## 后续项

- **用 SDK 头文件校正可用性**：只剩协议副本的属性只能写明来源，二进制分不清「SDK 早就声明、不留属性记录」与「私有方法后来
  公开」；要得出 NSView 锚点是 10.11 这类结论，得另读 SDK 头文件里的 `API_AVAILABLE`。这是另一个功能，要另起提案。
- **MachOSwiftSection 跟进**：它的依赖升到含本案的版本后，`swift-section objc diff` / `evolution` 的告警与 `via <协议>` 写法
  随之改变；它的 `Documentations/ObjCCommandLine.md` 若写到告警格式，需要同步。
- **两个与本案无关、实现中碰到的测试问题**：`stripSynthesizedMethods removes the setter` 随机挑一个类来测，全量跑时挑到
  NSScanner 失败过一次，重跑四次都通过；`MachOObjCSectionTests` 写死了本机没有的 `/Users/JH/Downloads/iOS18.5-SwiftUI`，
  CI 本来就跳过它。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-29 | Created as Draft | AppKit 的 image 组演进出了 8199 行 key collision 警告；核实后大部分是链接期合并 category 留下的相同副本，少数不同的副本让演进取到协议抄来的声明、报出假变化。这会改 diff 的比较语义，按轻量档先写提案 |
| 2026-10-29 | 取舍放在配对时，不在冻结快照时去重 | 冻结时去重违背「快照是未过滤的事实」，还要升快照格式版本；不升的话，带重复的旧 baseline 对去重后的新快照会取到不同的一份，报出假变化 |
| 2026-10-29 | 不改成取最后一份 | 类自己的列表虽然排在最后，但 `NSTextView.defaultParagraphStyle` 这类可写声明写在 category 里，类自己的列表里只有协议的只读副本，取最后一份会取错 |
| 2026-10-29 | 不按「可写优先、类型具体的优先」挑 | 说不清哪份更强：`NSScreen.hash` 两份的差别是 `unsigned long long` 对 `long long` |
| 2026-10-29 | image 组里跨 image 的 category 成员，payload 相同也不再告警 | 规则统一为「告警即比较被削弱」；成员在哪几个 image 里仍由搬家记录跟踪，丢掉的副本不藏任何变化。这改变了 0016 使用指南里的说法，落地时一并改 |
| 2026-10-29 | 用户批准，开始实现；补上落地步骤 | 精简提案原来没有落地步骤，按方案拆成四步，每步能单独构建、测试通过 |
| 2026-10-29 | 第 1 步：除 `keptSignature` 外再加 `keptImageName`，容器级的告警也填这两项（签名即容器名） | image 组里只写保留那份的签名，读者仍不知道比较的是哪个 image 的；容器级也填，告警的写法才能统一成「保留哪份、丢了哪些」 |
| 2026-10-29 | 第 1 步：公开的测试接缝 `diffMembers(old:new:)` 取第一份 | 它只拿到成员记录，没有协议表可认协议副本；从快照入口比较时都按新规则 |
| 2026-10-29 | 原第 3 步（合并头文件取同一份）并进第 1 步，落地步骤从四步改成三步 | 「同一个镜像交两次，正文是 `objc dump` 少掉重复行」那条测试同时依赖比较与渲染，分开提交会留下比较取类自己的声明、头文件却写协议副本的中间状态 |
| 2026-10-29 | 第 1 步：image 组的 `addVersion(images:version:)` 先取齐每个 image 的快照、合并，再渲染 | category 成员取哪个 image 的那份要看整组；为此每个 image 的 module 多组装一次，索引器的查找是字典缓存，这一步很便宜 |
| 2026-10-29 | 第 1 步：改写三条钉住旧行为的测试，而不是删掉 | `ObjCAPIDifferTests` 与 `SingleImageEvolutionOutputTests` 原来用两份相同的记录造碰撞，image 组测试原来期望相同的 category 成员告警；改成两份不同的记录后它们仍钉住碰撞的形状，相同的情形另由新测试钉住「不告警」 |
| 2026-10-29 | 第 2 步：标题定为 `Warnings — identity-key collisions (only the kept record was compared):`，每条写成 `kept: … · dropped: …`，没有保留记录的旧 JSON 只写 `dropped:` 一段 | 不写「内容不同」之类的限定：容器级的碰撞（image 组里的同名类）内容相同也照报，标题只说清楚比较了哪份；三处（diff 报告、演进报告、合并头文件）共用 `ObjCAPIKeyCollision.warningsHeading` 与 `recordsDescription` |
| 2026-10-29 | 第 3 步：归档 cache 测试补一条整条轴上协议副本都排在前面的情形（`NSMenuItem.action`/`tag`、`NSWindow.contentView`） | `NSView.frame` 只覆盖「中途多出协议副本」；协议副本从轴起点就在前面时演进没有事件，错只出现在合并头文件的写法上，原来的测试抓不到 |
| 2026-10-29 | 实现完成，待用户看过后收尾 | 文档：实现说明、使用指南、已裁决清单、术语表（「协议副本」）与两处索引已随第 1、2 步同步，不需要另写说明；README 不涉及告警，不用改。不在本案修、记下的两处：`stripSynthesizedMethods removes the setter` 随机挑类，全量跑时挑到 NSScanner 失败过一次，重跑四次都过；`MachOObjCSectionTests` 写死了本机没有的 `/Users/JH/Downloads/iOS18.5-SwiftUI`，CI 本来就跳过它。下游 MachOSwiftSection 升依赖后，`swift-section objc diff` / `evolution` 的告警跟着变，它的 `ObjCCommandLine.md` 若写到告警格式需同步 |
| 2026-10-30 | 应用户要求，把 MachOSwiftSection 导出 AppKit 图像组合并头文件的那个集成测试移植进来（`ObjCEvolutionInterfaceDumpTests`），只在设了 `MACHO_OBJC_SECTION_DUMP=1` 时运行 | MachOSwiftSection 规定 agent 不跑它的 `IntegrationTests`，移过来才能在本仓库生成并对照改动前后的头文件；补不了没有 class object 的 Swift 类，所以输出另带 `-MachOObjCSection` 后缀，不覆盖那边生成的文件 |
| 2026-10-30 | 用户决定：只有协议副本的属性，在事件里写明是哪个协议带进来的，并且不写可用性宏；作为第 4 步加进本案 | 用户指出 NSView 的锚点早在 SDK 的分类里声明（`macos(10.11)`），合并头文件却写「13.0 加入」与 `API_AVAILABLE(macos(13.0))`。核实后：那个分类在二进制里不留属性记录，13.0 才出现的是 `NSAKLayoutItem` 的协议副本；而「取值方法更早就在」这条线索分不清它和私有方法后来公开（`NSBezierPath.CGPath`、`accessibilityUserInputLabels` 在 SDK 里都是 14.0），51 个版本的头文件里约 2500 处中途新增的属性有约 400 处属于这两类之一。所以不改事件本身，只陈述「经由哪个协议」，并去掉会被当成 SDK 可用性的宏；要得到 10.11 这类结论得另读 SDK 头文件，是另一个功能 |
| 2026-10-30 | 第 4 步：写法定为紧跟在事件后的 `via <协议>`（`added in 13.0 via <NSAKLayoutItem>`），diff 报告写在行尾 `(via <协议>)`；声明它的协议取离容器最近的那个，同层取先采纳的；只有新增或删除带协议时才不写宏 | 不用 ` · ` 分隔，免得被读成另一个事件；最近的协议最能说明属性从哪来（`NSObject` 的四个属性经任何继承它的协议进来，都记作 `NSObject`）；修改不影响宏，宏只说引入与移除 |
| 2026-10-30 | 第 4 步：认协议副本改成对每条属性记录都查（原来只在一个 identity 出现多次时才查），为此给快照里每个协议预先算好展开后的声明 | 只剩一份协议副本的属性正是要写明来源的那些；预先算好之后，查一条记录只需按容器采纳的几个协议各查一次表 |
| 2026-10-30 | 实现完成，合入 `next`，编号 0017，状态改为 Implemented | 落地时取全部共享分支上的最大编号（0016）加一。与方案相比的出入都已记在上面各行：落地步骤由四步并成三步、又按用户决定加了第 4 步，告警多记了保留那份的 image，并移植了生成 51 个版本头文件的导出测试。文档：实现说明「同一容器里的重复成员」一节、使用指南的合并头文件与 image 组两节、已裁决清单与两处索引已同步，术语表新增「protocol copy（协议副本）」；不需要另写使用指南或实现说明。验证用的是第 4 步定稿代码上的那两次运行：CI 那组测试在 Xcode 27.2 与 26.6 下退出码都是 0 |
