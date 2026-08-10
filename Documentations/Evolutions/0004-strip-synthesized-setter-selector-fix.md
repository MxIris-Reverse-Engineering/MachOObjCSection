# 0004 - 修正 stripSynthesizedMethods 漏剥 setter 的选择器拼写

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-08-11
- **最后更新**: 2026-08-11
- **所属愿景**: 无
- **关联提案**: [0001](0001-objc-rendering-and-indexing-downstreaming.md)（其决策日志明确把本项列为「应单独提案并配回归测试」的遗留）
- **实现分支 / PR**: main
- **配套文档**: 无 —— 判据见「落地步骤」收尾

## 摘要

`ObjCGenerationOptions.stripSynthesizedMethods` 声称剥掉编译器为属性合成的存取器，但它构造
setter 选择器时漏了尾部冒号：拼出来的是 `setFoo`，而真实选择器是 `setFoo:`。因此这个开关
**从未剥掉过任何 setter**，只剥掉了 getter。

一行修复：`"set" + name.uppercasedFirst` → `"set\(name.uppercasedFirst):"`，并补两条回归测试。

## 动机

### 这个开关有一半从来没生效过

`Sources/ObjCInterface/ObjCInterfaceBuilder.swift` 的 `collectAccessorSelectors(of:intoClassMethods:intoMethods:)`
把要剥掉的存取器选择器收集进 `needsStripMethods`，之后用

```swift
methods: currentClassInfo.methods.removingAll { needsStripMethods.contains($0.name) }
```

过滤。比对的另一端 `ObjCMethodInfo.name` 存的是**完整选择器**
（`swift-objc-dump` 的 `ObjCMethodInfo.name`，"Name of the method"）。

getter 没有参数，选择器就是属性名，所以 `customGetter ?? propertyName` 是对的。
setter 带一个参数，选择器必然以冒号结尾，而原代码拼的是无冒号形式，于是集合里放的
`setFoo` 永远匹配不上方法列表里的 `setFoo:`。

实测确认：Foundation 的 `_NSPersonNameComponentsFormatterData` 打开该开关后，
合成的 setter 原样留在输出里。

### 它还有一个反向风险

同一处拼写也意味着：**一个与属性同名前缀、但零参数的方法 `setFoo` 会被误剥**。
今天的 Foundation 里没有这种形状（新增的回归测试扫过整个 image 未命中，故写成命中才断言），
但这个风险随任何被分析的二进制而来，不受本仓库控制。修正后两个方向同时消失。

### 为什么现在才修

0001 的决策日志有一条：

> 保留 setter 选择器缺冒号的既有行为 —— strip 用 `"set" + name.uppercasedFirst`（无冒号）
> 而真实选择器是 `setFoo:`，`stripSynthesizedMethods` 实际剥不掉 setter。这是迁移前就存在的
> 行为，改掉属于行为变更，应单独提案并配回归测试。

即：这不是新引入的回归，是从 RuntimeViewer 搬过来时**原样保留**的既有缺陷。0001 当时在做
搬迁，刻意不夹带行为变更 —— 那个判断是对的，本提案就是它点名要求的后续。

## 前期调研

### 同类模式横向排查

一处确认为真的错误几乎不会只出现一次，故对全部「构造 ObjC 选择器再与 `ObjCMethodInfo.name`
比对」的位置逐一核对：

| 位置 | 构造 | 判定 |
|---|---|---|
| `ObjCInterfaceBuilder.swift:328` | `customGetter ?? propertyName` | **正确** —— getter 零参数，选择器即属性名 |
| `ObjCInterfaceBuilder.swift:335`（原） | `customSetter ?? "set" + name.uppercasedFirst` | **错误** —— 本提案修复对象 |
| `ObjCInterfaceBuilder.swift:86/90/190/194` | 字面量 `".cxx_construct"` / `".cxx_destruct"` | **正确** —— 零参数方法，无冒号 |
| `ObjCDump+SemanticString.swift:369` | `customGetter ?? name` | **正确** |
| `ObjCDump+SemanticString.swift:370` | `customSetter ?? "set\(name.uppercasedFirst):"` | **正确** —— 渲染层一直拼对了 |
| `stripProtocolConformance` / `stripOverrides` | 直接取 `.map(\.name)`，不构造 | **正确** |

结论：**全库仅此一处实例**。同一个包里渲染层（`:370`）拼对、strip 层（`:335`）拼错，
两者相距不到一个 target，正好互为对照。

### `customSetter` 自带冒号，`??` 两侧一致

`ObjCPropertyInfo.customSetter` 取自属性的 `S` attribute（`ObjCDump+SemanticString.swift:784`），
其值本身就是完整选择器。渲染层 `:370` 直接拿它去查以完整选择器为键的 `methodIMPs` 并且工作正常，
可反证这一点。故修复后 `??` 两侧同为带冒号形式，不存在新的不一致。

### 现有测试为什么没抓住

`stripSynthesizedMethodsSwitch` 只断言 `stripped.count < plain.count`。getter 被剥掉就足以让
总长度变短，于是 setter 一直漏剥而测试常绿。**弱断言是这个缺陷活到今天的直接原因**。

## 提议方案

`collectAccessorSelectors` 里补上冒号：

```swift
let setterName = property.customSetter ?? "set\(propertyName.uppercasedFirst):"
```

并在该行留注释说明冒号不是修饰、而是选择器语义的一部分，以及它同时防住误剥零参数同名方法。

### 非目标

- **不改 getter 的构造。** 零参数选择器就是属性名，现状正确。
- **不改渲染层。** `:370` 一直是对的。
- **不动其它 strip 开关。** 它们不构造选择器。
- **不加「宽松匹配」之类的兼容层。** 旧行为是缺陷，不是可选语义，没有保留价值。

## 详细设计

单行改动，无 API 变化。

回归测试两条，均在 `Tests/ObjCInterfaceTests/ObjCInterfaceTests.swift`：

1. **`stripSynthesizedMethodsRemovesSetters`** —— 扫描 Foundation，找一个确实声明了合成 setter
   （`setFoo:` 出现在方法列表里且属性无 `customSetter`）的类，断言未剥离的输出**包含**该选择器、
   剥离后**不包含**。前一条基线断言的作用是保证后一条测的是剥离行为而不是拼写笔误。
2. **`stripSynthesizedMethodsSparesColonlessLookalike`** —— 反向：若某类同时有属性 `foo` 和零参数
   方法 `setFoo`，剥离后该方法必须**仍在**。Foundation 里目前没有这种形状，故未命中时直接返回而
   非失败 —— 缺的是样本，不是正确性。

## 替代方案考量

### 保留旧行为，另加一个「严格匹配」开关

**为什么否**：旧行为没有任何调用方会**想要** —— 没有人希望一个叫「剥掉合成存取器」的开关只剥一半。
把缺陷升格成可选语义，等于为一个纯粹的笔误永久增加一个配置维度和一条测试路径。

### 顺手也把 getter 改成带冒号形式以求「统一」

**为什么否**：那会直接制造出与本提案同类的新缺陷。getter 是零参数选择器，没有冒号才是对的。
两者不同不是不一致，是 ObjC 选择器语法本身。

## 影响

### 源码兼容性（source compatibility）

**API 纯不变，行为有变更。** 没有任何类型、方法、参数签名改动，调用方无需改一行代码。

但打开 `stripSynthesizedMethods` 的调用方**输出会变**：合成的 setter 从此真的被剥掉。这正是该
开关文档所承诺的效果，因此归类为缺陷修复而非破坏性变更 —— 不提供开关回退旧行为，理由见
「替代方案考量」。

依赖旧输出的快照测试（若有）需要更新基线。本仓库内无此类快照。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，未开启 library evolution，也无 `binaryTarget`。

### 下游影响

- **本仓库内**：仅 `ObjCInterface` target 与 `ObjCInterfaceTests`。
- **RuntimeViewer**：唯一已知会打开该开关的消费者。影响是其「隐藏合成存取器」的显示选项从此
  对 setter 也生效 —— 属于修复到位，非回归。与 0003 的适配互不干扰，两者改动面无交集。
- **MachOSwiftSection / MachOKitUI**：不使用 `ObjCInterface`，不受影响。

**上游 fork 传导**：改动在 `Sources/ObjCInterface/`（0001 新增的 target），
`Sources/MachOObjCSection/` 一行未动，不增加与上游合并的冲突面。

### 文档与示例

- `ObjCGenerationOptions.stripSynthesizedMethods` 的文档措辞无需改 —— 它描述的一直是修复后的
  行为，此前只是实现没做到。
- README 无需改：其中没有针对该开关的具体输出示例。
- 0001 的决策日志**保持原貌** —— 那条「保留既有行为」是当时的决策快照，本提案是它的后续，
  不回头修改它。

## API 演进与废弃策略

无 API 增删，无废弃项。版本递增至 `0.8.104`，不做 semver major 跃迁（本库在 `0.x`，
且这是缺陷修复）。

## 落地步骤

1. **写回归测试并确认其失败**。验收：`stripSynthesizedMethodsRemovesSetters` 为红，
   且失败信息显示 setter 仍在剥离后的输出里。
2. **补上冒号**并加注释说明其语义。验收：第 1 步的测试转绿。
3. **横向排查同类模式**，逐一核对全部选择器构造点。验收：结论记入本提案「前期调研」。
4. **全量测试**。验收：`ObjCInterfaceTests` 退出码为 0。
5. **发版 `0.8.104`**。

**收尾判断**：

- **是否配套专题文章** —— 否。修复本身一行，理由（选择器带不带冒号取决于参数个数）是 ObjC 常识，
  不构成「代码看不出来的决策」；需要留下的上下文已经在本提案和那行注释里。
- **是否引入新术语** —— 否。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-08-11 | Created，并直接实现 | 用户报告：strip setter 时拿 `setFoo` 去比对，而真实选择器是 `setFoo:`。0001 决策日志早已把这一项列为「应单独提案并配回归测试」的遗留，本篇即该后续 |
| 2026-08-11 | 先写红测试再修 | 复现测试在修复前失败于 `_NSPersonNameComponentsFormatterData`（合成 setter 原样留在输出里），修复后转绿。红绿两态都观察到，回归防线才成立 |
| 2026-08-11 | 补一条反向测试：不得误剥零参数同名方法 | 原缺陷是双向的 —— 除漏剥 `setFoo:` 外，还会误剥零参数的 `setFoo`。Foundation 里无此形状，故写成「命中才断言、未命中直接返回」，缺的是样本而非正确性 |
| 2026-08-11 | 横向排查：全库仅此一处 | 逐一核对六处选择器构造点。getter（零参数）与 `.cxx_*` 字面量本就正确；渲染层 `ObjCDump+SemanticString.swift:370` 一直拼对了 —— 同包内一对一错，正好互为对照 |
| 2026-08-11 | 不提供回退旧行为的开关 | 旧行为是笔误不是语义，没有调用方会想要「只剥一半存取器」。为纯缺陷增加配置维度得不偿失 |
| 2026-08-11 | 实现完成，发版 `0.8.104` | `ObjCInterfaceTests` 18 tests 全绿、退出码 0 |
