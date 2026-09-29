# Draft - 标记模式：一次渲染全量声明，并标出每段内容受哪个开关控制

- **状态**: In Progress
- **创建日期**: 2026-09-29
- **最后更新**: 2026-09-29
- **关联**: swift-semantic-string 的设计记录 `docs/VisibilityRegions.md`（提供 `VisibilityRegion`、区域表与投影）；
  MachOSwiftSection 的同名提案 `draft-visibility-regions`；RuntimeViewer 的 `draft-find-navigator`（使用方）
- **实现分支**: `feature/visibility-regions`

## 摘要

RuntimeViewer 的 Find 要「语料只打印一次，搜索时按用户当前的 Generation Options 只输出可见内容」。ObjC 的十个
开关（六个 strip、四个注释）决定声明里有哪些成员行、行尾有哪些注释，而 `ObjCInterfaceBuilder` 今天的做法是先按
开关过滤 metadata 再渲染——被过滤掉的内容从输出里消失，事后无法知道「换一组开关会多出什么」。本提案给 builder
加一个**标记模式**：不过滤、不省注释，渲染全量声明，同时用 `VisibilityRegion` 把每段受开关控制的内容标上条件。
调用方按任意开关组合投影这份输出，得到的文本与该组合下的普通渲染逐字节相同。

## 方案

- **入口**：`ObjCInterfaceBuilder.markedClassInterface(named:cTypeReplacements:ivarOffsetCommentBuilder:)`、
  `markedProtocolInterface(named:…)`、`markedCategoryInterface(uniqueName:…)`。不带 `options` 参数——标记模式下开关
  不参与渲染。C struct / union 不受任何开关影响，照旧用普通入口。普通入口的行为与输出不变。
- **开关名**：`ObjCGenerationOptions.VisibilityOption`（十个，`objc.stripOverrides` 这类原始值）、
  `isEnabled(_:)`，以及投影用的谓词 `isVisibilityOptionEnabled(_:)`（不认识的名字读作关）。
- **strip 的条件**：builder 先逐个开关算出它会去掉哪些成员（`StrippedMembers`，按 ivar / 类属性 / 属性 / 类方法 /
  方法分列）。普通渲染取已开开关的并集过滤，结果与改动前完全相同；标记模式把每个成员对应的开关集合交给
  `ObjCRenderingContext.optionalContentMarking`（`ObjCOptionalContentMarking`），渲染器用它包住成员，条件是
  「这些开关全部关闭」。规则（`collectAccessorSelectors`、父类链、协议成员名）只此一份。
- **注释的条件**：四个 `add*Comments` 各自包住它那一段，连同前导的 `Space()` / `Joined(prefix: " ")`。
  标记模式下 IMP 地址总是收集，属性的 getter / setter 地址注释才有内容可标。
- **容器不用另外处理**：ivar 花括号、属性与方法块之间的空行、协议的 `@required` / `@optional` 标题，由
  swift-semantic-string 的容器按成员条件自动带上（见其设计记录 `docs/VisibilityRegions.md`），渲染器只包成员本身。
- **正确性**：`ObjCMarkedInterfaceTests` 对 Foundation 的每个 class / protocol / category，在全关、全开、每个开关
  单开、每个开关单关、strip 与注释两半各自全开这 24 组组合下，断言「标记渲染按该组合投影」与「普通入口按该组合
  渲染」完全相等（文本、span、identifier），并断言标记渲染本身读作「不 strip、注释全开」；另有一组带自定义 ivar
  偏移注释与 C 类型替换的用例。约 33 秒。
- **依赖**：需要 swift-semantic-string 带 `VisibilityRegion` 的版本；该版本发布后把远程依赖的下限抬上去，
  在此之前本地构建走 `USING_LOCAL_DEPENDENCIES` 或 SwiftPM 的 edit 模式。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-29 | Created as Accepted | RuntimeViewer 的用户报告 Find 能搜到被 strip 的 ivar 和合成 getter / setter，并要求「语料要为所有可能出现的内容进行索引，但是只输出匹配当前options的内容」、改开关不重建语料。经两个会话各自设计后比较，一致认为归属只能由渲染器在输出时给出。用户：「可以改，上游都是我自己的库，写提案直接开工吧」。 |
| 2026-09-29 | strip 规则不复制到 RuntimeViewer | 另一条路是 RuntimeViewer 照抄 `needsStrip*` 的规则和 ObjC 的版式、事后给每行认归属；两边的规则与版式一改就会悄悄对不上。标记模式让这份规则只存在于 builder 里。 |
| 2026-09-29 | 容器不再单独包「任一成员可见」的区域 | swift-semantic-string 的容器改为把成员的条件带到自己的换行、分隔符与前后缀上，渲染器只需包成员与注释。对照测试在 Foundation 全部声明、24 组组合下一次通过。 |
| 2026-09-29 | Accepted → In Progress | 实现与测试完成于 `feature/visibility-regions`，未提交。`MachOObjCSectionTests`（XCTest）依赖本机不存在的 `/Users/JH/Downloads/iOS18.5-SwiftUI`，setUp 即崩，与本改动无关；其余测试全部通过。 |
