# Draft - 同一容器里的重复成员按来源取舍，内容相同的不再告警

- **状态**: Accepted
- **创建日期**: 2026-10-29
- **最后更新**: 2026-10-29
- **实现分支**: `feature/objc-duplicate-member-selection`

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

- [ ] 1. `ObjCDiffing` 的取舍规则：认出协议副本，按新规则为每个 identity key 取一份；双边 differ、evolution builder 与
  `keyCollisions()` 共用它；`ObjCAPIKeyCollision` 记下保留的那份。纯值回归测试；实现说明、代码注释、已裁决清单与术语表。
- [ ] 2. 报告：两个 reporter 的警告标题与保留那份的写法；报告测试。
- [ ] 3. 合并头文件取比较时保留的那一份，单 image 与 image 组都是；归档 cache 测试断言 `NSView.frame`；使用指南。
- [ ] 4. 完整验证：全量测试；用本分支的命令行重跑几版 AppKit 的演进，对照警告数与 `NSView.frame`，结论写进本提案。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-29 | Created as Draft | AppKit 的 image 组演进出了 8199 行 key collision 警告；核实后大部分是链接期合并 category 留下的相同副本，少数不同的副本让演进取到协议抄来的声明、报出假变化。这会改 diff 的比较语义，按轻量档先写提案 |
| 2026-10-29 | 取舍放在配对时，不在冻结快照时去重 | 冻结时去重违背「快照是未过滤的事实」，还要升快照格式版本；不升的话，带重复的旧 baseline 对去重后的新快照会取到不同的一份，报出假变化 |
| 2026-10-29 | 不改成取最后一份 | 类自己的列表虽然排在最后，但 `NSTextView.defaultParagraphStyle` 这类可写声明写在 category 里，类自己的列表里只有协议的只读副本，取最后一份会取错 |
| 2026-10-29 | 不按「可写优先、类型具体的优先」挑 | 说不清哪份更强：`NSScreen.hash` 两份的差别是 `unsigned long long` 对 `long long` |
| 2026-10-29 | image 组里跨 image 的 category 成员，payload 相同也不再告警 | 规则统一为「告警即比较被削弱」；成员在哪几个 image 里仍由搬家记录跟踪，丢掉的副本不藏任何变化。这改变了 0016 使用指南里的说法，落地时一并改 |
| 2026-10-29 | 用户批准，开始实现；补上落地步骤 | 精简提案原来没有落地步骤，按方案拆成四步，每步能单独构建、测试通过 |
