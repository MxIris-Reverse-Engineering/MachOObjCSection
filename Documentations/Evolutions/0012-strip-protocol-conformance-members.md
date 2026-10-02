# 0012 - stripProtocolConformance 剥掉协议声明的全部成员，保留遵循列表

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-10-02
- **最后更新**: 2026-10-02
- **所属愿景**: 无
- **关联提案**: [0004](0004-strip-synthesized-setter-selector-fix.md)（同类：strip 开关没做到它承诺的事）
- **实现分支 / PR**: `fix/strip-protocol-conformance-members` → `next`
- **配套文档**: 无

## 摘要

`stripProtocolConformance` 的用途是让生成的头文件接近真实头文件：ObjC 里一个类遵循了协议，就不会在
`@interface` 里重复声明协议要求的属性和方法，所以这些成员应当剥掉，`<Protocol, …>` 列表本身保留。

现状只剥了一小部分：类的声明只看**直接**遵循的协议、只剥**必需**成员，漏了 `@optional` 成员和继承链上
的协议（典型是 `NSObject` 协议的 `hash` / `superclass` / `description` / `debugDescription`）。实现
大量 AppKit 代理方法的类，打开开关后几乎什么都没剥。另一边，六处说明文字把它写成了「删掉
`<Protocol, …>` 列表」，与本意相反，实现也从来没删过列表。

修复：沿完整的协议继承链收集必需与可选的全部属性和方法；改正说明文字。

## 动机

### 实际输出

Mica.app（Apple 内部的 Core Animation 编辑器）里的 `ArchiveViewController : NSViewController
<NSTableViewDataSource, NSTableViewDelegate>`，打开开关后：

- `tableView:viewForTableColumn:row:`、`numberOfRowsInTableView:` 等仍在 —— 它们在两个协议里都是
  `@optional`；
- `hash`、`superclass`、`description`、`debugDescription` 仍在 —— 由 `NSObject` 协议声明，两个协议都
  继承了它，而实现不往上追。

结果和不开开关几乎一样。

### 说明文字与本意相反

以下六处都说这个开关会删掉 `<Protocol, …>` 列表：

1. `ObjCGenerationOptions.stripProtocolConformance` 的文档注释（本仓库）；
2. `objc-section` 的 `--help`（本仓库 `Sources/objc-section`）；
3. 本仓库的 `Documentations/Guides/ObjCSectionCommandLine.md`；
4. `swift-section objc` 的 `--help`（MachOSwiftSection）；
5. MachOSwiftSection 的 `Documentations/ObjCCommandLine.md` 与中文版；
6. RuntimeViewer 导出 README 里的选项说明。

### 不是回归

从 0001 落地的第一版（2026-08-10，`85d71f6`）起就是这样：类的分支只收直接协议的必需成员，协议声明的
分支收直接父协议的必需与可选成员，两边不一致，也都不追继承链。0011 把收集逻辑搬进
`strippedMembers(ofClass:superclassInfos:)` / `strippedMembers(ofProtocol:)` 时原样保留。现有的
`stripProtocolConformanceSwitch` 测试只断言「剥离后比剥离前短」，所以抓不到漏剥。

## 提议方案

两个分支都改用同一个收集函数：从给定的协议出发，沿 `ObjCProtocolInfo.protocols` 递归走完整条继承链，
收集每个协议的必需与可选的类属性、属性、类方法、方法；按协议名去重，菱形继承（多个协议都继承
`NSObject`）只走一次。

- **类的声明**：从类直接遵循的协议出发。
- **协议的声明**：从它直接继承的协议出发（自身声明的成员不剥）。

### 非目标

- **不删 `<Protocol, …>` 列表。** 真实头文件里它就在那里。
- **不追父类遵循的协议。** 子类实现父类所遵循协议的方法，属于 `stripOverrides` 的范围。
- **不处理 category 遵循的协议。** category 单独渲染，不在本次范围。
- **不加回退旧行为的开关。** 理由同 0004：旧行为是缺陷，没有调用方会想要「只剥一部分」。

## 影响

- **源码兼容性**：API 不变，行为有变更 —— 打开开关的输出会剥掉更多成员。这正是开关的本意，按缺陷修复
  处理。
- **下游**：RuntimeViewer 的「Strip Protocol Conformance」选项与导出、`swift-section objc` 的同名参数，
  输出随之变化；三处说明文字同批改正（MachOSwiftSection、RuntimeViewer 各自一个提交）。
- **标记模式（0011）**：标记渲染与普通渲染共用同一份「每个开关剥掉哪些成员」的表，自动一致。

## 落地步骤

1. 现场用 clang 编一个 ObjC 样本库（协议链 + 可选成员 + `NSObject` 继承），写回归测试并确认修复前失败。
2. 改收集逻辑，测试转绿；改正本仓库的文档注释与 `objc-section` 的 `--help`。
3. 全量测试。
4. 合入 `next`；MachOSwiftSection、RuntimeViewer 的说明文字同日合入各自的 `next`。

发版不在本提案内。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-10-02 | Created，Accepted | 生成 Mica.app 头文件时发现开关几乎不起作用；用户澄清本意是「剥掉协议声明的全部属性和方法、保留遵循列表，以接近真实头文件」，并批准按此修复 |
| 2026-10-02 | 先写红测试再修 | `StripProtocolConformanceTests` 现场用 clang 编样本库，经 `MachOFile` 读。修复前类的那条失败：9 个成员留在剥离后的输出里——`derivedOptionalProperty` 的 getter、两个可选方法与一个可选类方法、祖父协议的 `baseRequiredMethod` / `baseOptionalMethod`、`NSObject` 协议的四个属性。协议那条也失败：重新声明祖父协议成员的协议没剥掉它。「保留遵循列表」那条修复前就通过，它钉住的是语义 |
| 2026-10-02 | 两条分支共用一个收集函数 | `membersDeclared(byProtocolChainsOf:)`：从给定协议出发，沿 `ObjCProtocolInfo.protocols` 走完整条链，必需与可选一并收集，按协议名去重。`ObjCProtocolInfo` 在 `MachOFile` 读法下也带着继承协议的完整成员表，`NSObject` 的四个属性因此能被识别 |
| 2026-10-02 | 实现完成 | 修复后三条转绿；`swift test --skip MachOObjCSectionTests`（与 CI 相同：该 XCTest 目标读 `/Users/JH/Downloads/iOS18.5-SwiftUI`，这台机器上没有）136 个测试 / 14 个套件全部通过，退出码 0。本仓库的三处说明文字同批改正 |
