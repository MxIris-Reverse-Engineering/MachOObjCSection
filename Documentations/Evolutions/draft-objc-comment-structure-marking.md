# Draft - 给 ObjC 注释标出种类和各段的角色

- **状态**: In Progress
- **创建日期**: 2026-10-31
- **最后更新**: 2026-10-31
- **实现分支**: `feature/objc-comment-structure-marking`（worktree `.worktrees/MachOObjCSection-CommentStructureMarking`，
  叠在 `feature/objc-exported-declarations-only` 上切）
- **配套文档**: 使用指南[「库调用方：标出注释的结构」](../Guides/ObjCSectionCommandLine.md#库调用方标出注释的结构)；术语表的
  [comment structure marking](../Glossary.md#comment-structure-marking注释结构标记)
- **关联提案**: [0011](0011-visibility-regions.md)（标记模式：注释在其中各自带可见性条件）；RuntimeViewer 的
  `draft-source-editor-comment-annotations`（使用方：SourceEditor 面板把注释画成标签）；swift-semantic-string 的
  设计记录 `docs/AnnotationRegions.md`（提供 `AnnotationRegion`、`AnnotationSegment`、`AnnotatedAtom` 与分离入口，
  草案）；MachOSwiftSection 在 Swift 一侧的同一改动（草案）

## 摘要

RuntimeViewer 要在 SourceEditor 面板里把生成器输出的注释画成圆角标签：不显示 `// `、`/* */` 和 `: ` 这类标点，
标签名和数值分色，一行末尾的几条注释各成一个标签。RuntimeViewer 不解析注释文本，结构由生成器在打印时标出。
本案给 `ObjCInterfaceBuilder` 加一个默认关闭的开关 `marksCommentStructure`。打开时，ObjC 渲染输出的每条注释都包进
swift-semantic-string 新增的注释结构区域（`AnnotationRegion`），标出它是哪一种注释（IMP 地址、ivar 偏移……），以及
其中每一段担任什么角色（注释符、标签名、分隔符、值……）。区域只写在原子的 identifier 上，文本一个字节不变。开关
关着时，输出的原子与今天完全相同；开着时，冻结后分离出的字符串与关着时的打印完全相等，span 也一个不差。

## 方案

### 开关放在 builder 上

```swift
// RuntimeViewer 的内容面板：SourceEditor 与标签都打开时
let builder = ObjCInterfaceBuilder(indexer: indexer, machO: machO, marksCommentStructure: true)
if let printed = builder.classInterface(named: "NSView", options: options, ivarOffsetCommentBuilder: ivarOffsetCommentBuilder) {
    let (text, annotations) = printed.frozen().separatingAnnotationRegions()
    // text 与不开开关时的打印冻结后相等；annotations.regions 是每条注释的 kind 与 UTF-8 范围，
    // annotations.segments 是每一段的角色与 UTF-8 范围
}

// swift-section objc 等其他使用方不改，输出不变
let builder = ObjCInterfaceBuilder(indexer: indexer, machO: machO)
```

- `ObjCInterfaceBuilder.init` 加 `marksCommentStructure: Bool = false`。这个 builder 渲染的每一种声明都照此标注：
  类、协议、类别、C struct 与 union，普通模式和标记模式都算。底层的 `ObjCRenderingContext` 加同名属性和构造参数，
  与 `optionalContentMarking` 并列，供直接调用渲染器的人用。
- 不放进 `ObjCGenerationOptions`。那里的每个开关都决定声明里出现什么，各有一个 `VisibilityOption` 供标记模式投影，
  宿主还会把它存成用户设置。这个开关不改变内容，只改变输出的形态，和「要不要标记模式」一样由宿主决定。另外，
  标记模式的三个入口不带 `options` 参数，开关放在那里它们就拿不到。
- 开关名和 MachOSwiftSection 的一致：那边是 `SwiftDeclarationPrintConfiguration.marksCommentStructure`，同样默认
  关闭，和 `marksOptionalContent` 并列。宿主可以用一个设置同时驱动两边。

### 盘点：八处注释，七种 kind

ObjC 渲染路径里输出注释的地方有八处，全部覆盖：

| 注释 | 出自 | 受哪个开关控制 | kind | 各段（角色 `文本`） |
|---|---|---|---|---|
| `// IMP: 0x1A2B` | 方法行尾 | `addMethodIMPAddressComments` | `impAddress` | marker `// ` · label `IMP` · separator `: ` · value `0x1A2B` |
| `// getter IMP: 0x4550`、`// setter IMP: 0x4558` | 属性行尾 | `addPropertyAccessorAddressComments` | `impAddress` | label 为 `getter IMP` / `setter IMP`，其余同上 |
| 上面两种地址无效时：`// IMP: <invalid 0x0>` | 同上 | 同上 | `impAddress` | 同上；value 是那个语义类型为 `.error` 的原子 |
| `// @synthesize width = _width` | 属性行尾 | `addPropertyAttributesComments` | `propertySynthesis` | marker · label `@synthesize` · separator ` ` · name `width` · separator ` = ` · value `_width` |
| `// @synthesize width`（ivar 与属性同名） | 同上 | 同上 | `propertySynthesis` | marker · label `@synthesize` · separator ` ` · name `width` |
| `// @dynamic width` | 同上 | 同上 | `propertyDynamic` | marker · label `@dynamic` · separator ` ` · name `width` |
| `// offset: 8` | ivar 行尾 | `addIvarOffsetComments` | `ivarOffset` | marker · label `offset` · separator `: ` · value `8` |
| `// offset: unknown`（宿主补充的类里，镜像不记偏移的 ivar） | 同上 | 同上 | `ivarOffsetUnknown` | marker · label `offset` · separator `: ` · value `unknown` |
| 宿主自定义的 ivar 偏移注释 | 同上 | 同上 | `ivarOffset` | 见下一节 |
| `id /* block */`、`void * /* function pointer */` | 类型里（没有签名的 block、函数指针） | 总是输出 | `typeNote` | marker `/* ` · text `block` / `function pointer` · marker ` */` |
| `// Generic Swift class, instantiated at runtime` 等三种 | 宿主补充的类的 `@interface` 上方 | 总是输出 | `note` | marker `// ` · text 全文 |

- 一条注释一个区域，从 `// ` 一直覆盖到最后一段。注释前的空格、属性行尾几条注释之间的空格都不在区域里，所以
  `@property … width; // @synthesize width = _width // getter IMP: 0x4550 // setter IMP: 0x4558` 是三个区域。
- `unknown` 单独成一种 kind，而不是 `ivarOffset` 的一个值：RuntimeViewer 要把「偏移未知」画成警示样式，靠 value
  的文字是不是 `unknown` 来判断，等于又在解析注释文本。Swift 一侧对应的是 `fieldOffsetUnknown`，两边对称。
- 区域不带属性。RuntimeViewer 第一版只用段，地址就是 `impAddress` 的 value 段。属性本来就是可选的，以后要复制地址、
  跳到交叉引用时再加，不影响已有的使用方。
- 标记模式下，注释本来就在各自 `add…Comments` 开关的 `VisibilityRegion` 里，注释区域嵌在里面。打印导出声明时，
  标记模式还会用 `markAtoms(from:visibleUnder:)` 给未导出的类整段再套一层可见性标记。swift-semantic-string 确认这
  两种叠法都不会触发它的前置条件检查：那项检查只看构造 `AnnotatedAtom` 时内容里的原子，之后从外面统一加上的标记
  不算；拆开的原子照常并回一个 span，可见性分离与注释分离谁先谁后结果都一样。唯一的例外是 `markAtoms` 的起点
  落在一条注释的几片中间，本库总是从 0 开始，碰不到。
- kind 是 `AnnotationRegion.Kind` 的静态成员。swift-semantic-string 自带两个生成器共用的 `note`，其余六个由本库在
  ObjCDeclarationRendering 里扩展（`extension AnnotationRegion.Kind { public static let impAddress = Self("impAddress") }`
  之类），使用方写 `.impAddress`，不必手写字符串。它们和 MachOSwiftSection 扩展的 kind 名字不重叠，RuntimeViewer
  同时 import 两边不会遇到同名的静态成员；以后两边都要用的 kind 放进 swift-semantic-string。角色用它给的
  `AnnotationSegment.Role`。

### 宿主自定义的 ivar 偏移注释

`ivarOffsetCommentBuilder` 交来的是一个拼好的整串（RuntimeViewer 用 `Transformer.ObjCIvarOffset` 的模板拼），
生成器不知道其中哪一段是值。采用一条写进使用指南的切分规则：在第一个 `: ` 处切开，前面是 label，`: ` 是
separator，后面是 value；没有 `: ` 时整串是 value。`Transformer.ObjCIvarOffset` 自带的三个模板（`offset: ${offset}`、
`ivar offset: ${offset}`、`${offset}`）都能切准，用户手写的其他模板退化成一个值标签。

备选方案是让 transformer 直接交出带角色的段（模板里的字面量和 `${offset}` 分开），这样每种模板都准。但渲染层不依赖
transformer，要给 `ObjCRenderingContext` 和 builder 的八个入口各加一个新的闭包参数，改动的 API 面太大，这次不做。

### 开关开与关的等价性

每条注释只在一处代码里描述：kind 加一串有序的段，每段有角色、文本和语义类型。两种输出都从这一份描述生成，文本
不会在两种模式之间走样。

- **关着**：把相邻、语义类型相同的段合成一个原子输出，结果正好是今天的 `Comment("offset: 8")`，或者
  `Comment("IMP: ")` 加 `Error(…)`。一个原子都不多拆，swift-section objc 和 RuntimeViewer 的 Find 语料不付任何代价。
- **开着**：关着时的每个原子写成一个 `AnnotatedAtom`，它的每一段是一片，包在 `AnnotationSegment` 里，整条注释再包进
  `AnnotationRegion`。分离时同一个 `AnnotatedAtom` 的片并回一个 span，所以分离出的字符串与关着时的打印完全相等。

```swift
// 地址无效的 IMP 注释，开关打开时
AnnotationRegion(.impAddress) {
    AnnotatedAtom(type: .comment) {                       // 关着时的 Comment("IMP: ")
        AnnotationSegment(.marker) { "// " }
        AnnotationSegment(.label) { "IMP" }
        AnnotationSegment(.separator) { ": " }
    }
    AnnotationSegment(.value) { Error("<invalid 0x0>") }  // 关着时本来就是单独的原子
}
```

- 每条注释仍由一个返回 `SemanticString` 的辅助函数产出，在外层容器里只算一个元素，两种模式的元素结构相同。
  `Joined` 这类容器按元素插分隔符，元素多一个，文本就会多出一个空格。

三方约定原本要求开与关分离后连 span 都逐个相等，可 `frozen()` 一个原子出一个 span：只在开着时拆原子就做不到，
关着时也拆又让所有使用方的注释原子变多（每条注释从一个变成两到六个，RuntimeViewer 的 Find 语料用标记模式、注释
全开，每个方法、属性、ivar 都要付）。RuntimeViewer 先把约定放宽成「文本逐字节相同、每个字节的语义类型与 identifier
相同」；swift-semantic-string 随后提供了 `AnnotatedAtom`，开着时拆、分离时并回，原来那条更严的要求也满足了。

### 不在范围内

- 演进头文件里的注释（`ObjCEvolutionInterfaceBuilder` 把多个版本合并成一份带演进标注的头文件，注释有版本位图、
  头部说明、告警）。它们是逐段用 `append(_:type:)` 写进去的，RuntimeViewer 也不显示这种头文件，这次不做。
- `Unknown` 这类 `.error` 原子不是注释，不标。
- objc-section 命令行不加开关，它会按 [0010](0010-remove-objc-section-cli.md) 删掉。

### 测试

- `CommentStructureMarkingTests`：用手工构造的 ivar、属性、方法作 fixture，不依赖二进制，地址可控：一个属性同时带
  `@synthesize name = ivar` 和 getter、setter 两个地址（setter 的地址无效）；同名 ivar 的 `@synthesize` 与 `@dynamic`；
  有效与无效的方法 IMP；`@?` 的 ivar（block）和 `^?` 的 ivar（函数指针）；宿主措辞的 ivar 偏移注释，三个自带模板的
  写法各一次，外加一个不含 `: ` 的。断言分离出的表里每个区域的 kind、覆盖的文字，以及每一段的角色和文字。再拿一个
  集齐这些成员的类，断言开着时分离出的字符串与关着时完全相等。
- `ObjCCommentStructureMarkingTests`：对 Foundation 的每个类、协议、类别、struct、union，在注释全开时比较开关开与关，
  开着时冻结、分离出的字符串与关着时冻结的字符串相等（`FrozenSemanticString` 的 `==` 连 span 一起比），并断言其中
  确实标出了 `impAddress`、`ivarOffset`、`propertySynthesis`、`typeNote`。标记渲染同样比：每个类、协议、类别的
  `marked…` 渲染开着开关、分离注释标记后，与不开开关的标记渲染完全相等，其中包括被导出过滤排除、事后用
  `markAtoms` 整段标记的类。投影的正确性仍由 `ObjCMarkedInterfaceTests` 保证。
- `CommentAtomTests`：开关关着时，每条注释仍是改动前的样子，一个原子，地址无效时是一个注释原子加一个 `.error`
  原子，逐个原子断言。
- `SuppliedClassRenderingTests`：宿主补充的类上方那行是一个注释原子；开着开关时依次是 `note`、`ivarOffset`、
  `ivarOffsetUnknown` 三个区域。
- 使用方验证：RuntimeViewer 对着 `635fe17`（连同 swift-semantic-string 的 `next` `2698750`）做了端到端验证，全部
  通过。它打印 libobjc 的 `NSObject`、四个注释开关全开，开关开与关的 `interfaceString` 文本、span、identifier 完全
  相等，每条注释都在表里、从 `//` 开始，出现的 kind 与角色都在约定清单里。见 RuntimeViewer 的提交 `c3ad6ca7`。

### 依赖与发版

需要 swift-semantic-string 带新组件的版本。它发布后把依赖下限从 0.4.0 抬上去，在此之前本地构建把
swift-semantic-string 这一个依赖用 `swift package edit swift-semantic-string --path <它的 next 检出>` 换成本地的。
不用 `USING_LOCAL_DEPENDENCIES`：它会把 MachOKit、MachOKitExtensions 也一起换成本地检出。MachOSwiftSection 的依赖
范围包含本库每个新的补丁版本，所以本库的 tag 要等 swift-semantic-string 先发版。落地前照例再用 CI 的 Xcode 26.6
编一遍。

使用指南的「库调用方：标出注释的结构」一节与代码同批写好：怎么打开与读回、kind 与各段、签名里看不出来的几条契约。

### 落地步骤

1. **注释改由一份描述产出**（不依赖新 API）——已完成：新增 `ObjCComment`（kind 加一串段），八处注释都经
   `ObjCRenderingContext.comment(_:)` 输出。开关还不存在，输出与改动前逐个原子相同。`CommentAtomTests` 用手工构造的
   ivar、属性、方法钉住每条注释的原子和整行文本，`SuppliedClassRenderingTests` 钉住宿主补充类上方那行；这批测试在
   改动前的代码上同样通过。
2. **开关与标注输出**（依赖 swift-semantic-string 的 `AnnotationRegion`）——已完成，对着它本地的 `next` 构建：
   `ObjCRenderingContext` 与 `ObjCInterfaceBuilder` 上的 `marksCommentStructure`，开着时的标注输出，
   `AnnotationRegion.Kind` 的六个常量，宿主措辞的 ivar 偏移注释的切分规则；测试按「测试」一节。
3. **文档**——已完成：使用指南「库调用方：标出注释的结构」一节，术语表的 comment structure marking 一条，文档索引。

### 待定

- swift-semantic-string 发版后，把依赖下限抬到那个版本，退出 edit 模式，用发布的版本和 Xcode 26.6 各验证一遍，
  才能收尾。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-31 | Created as Draft | RuntimeViewer 要在 SourceEditor 面板里把注释画成标签，并决定由生成器标出注释结构；本库负责 ObjC 一侧。 |
| 2026-10-31 | 开关放在 `ObjCInterfaceBuilder` 的构造参数上，不进 `ObjCGenerationOptions` | 那里是用户可见、会被持久化的内容开关，各对应一个 `VisibilityOption`；标记模式的入口也不带 options。与使用方 RuntimeViewer 商定：它每次调用都新建 builder，加构造参数最顺手。 |
| 2026-10-31 | 自定义 ivar 偏移注释按第一个 `: ` 切分，不让 transformer 交出带角色的段 | 自带的三个模板都能切准；后者要给渲染层和 builder 的八个入口各加一个闭包参数。RuntimeViewer 同意。 |
| 2026-10-31 | 开与关的等价性按「文本逐字节相同、每个字节的语义类型与 identifier 相同」判，span 边界可以不同；关着时一个原子都不多拆 | `frozen()` 一个原子出一个 span，要 span 也相等，关着时就得拆原子，所有使用方都付代价。RuntimeViewer 不比较两种打印的 span，选了这一条，并已告知另外两个仓库的会话。 |
| 2026-10-31 | `offset: unknown` 单独成 kind `ivarOffsetUnknown` | RuntimeViewer 要把偏移未知画成警示样式，靠 value 的文字判断等于又在解析注释文本；与 Swift 一侧的 `fieldOffsetUnknown` 对称。 |
| 2026-10-31 | 区域先不带属性 | RuntimeViewer 第一版只用段，地址就是 `impAddress` 的 value 段；复制地址、跳到交叉引用这类需要再加。 |
| 2026-10-31 | 开关名定为 `marksCommentStructure`，kind 用 struct 加静态成员的 `ObjCCommentKind`，角色常量交给 swift-semantic-string | 与 MachOSwiftSection 商定：开关同名，宿主可以一个设置驱动两边；kind 会增加，与对方的 `SwiftCommentKind` 同形；角色是两边共用的词汇。 |
| 2026-10-31 | 采用 swift-semantic-string 草图里的 `AnnotationRegion`、`AnnotationSegment`、`AnnotatedAtom`；kind 改为扩展 `AnnotationRegion.Kind`，不再另建 `ObjCCommentKind` | 对方的 kind 本身就是 struct 加静态成员的开放常量集，共用的 `note` 在它那里；用 `AnnotatedAtom` 后，开与关分离后连 span 都相等，契约测试可以直接比冻结串。 |
| 2026-10-31 | 不用 swift-semantic-string 提议的 OutputTransformer 模板分段 | 渲染层只拿到 `(Int) -> String` 的闭包，按第一个 `: ` 切；`Transformer.ObjCIvarOffset` 只有一个占位符、代入的是数字，逐个替换与扫描一遍的结果相同，也不必改走新函数。 |
| 2026-10-31 | 用户批准，开始实现 | — |
| 2026-10-31 | 功能分支叠在 `feature/objc-exported-declarations-only` 上切；提案随功能分支提交，不提交到 `next` | 本案覆盖 `printExportedDeclarationsOnly` 标记模式下的情形，依赖那个还没推到 `origin/next` 的功能。本地 `next` 上那次合并还在等用户过目，从它切或在它上面提交，用户撤销那次合并时，本分支就会带着它。 |
| 2026-10-31 | 自定义 ivar 偏移注释的切分规则并进标注输出那一步，原来单列的一步取消 | 切分的结果只在标注输出里看得到；在那一步经公开接口测，不针对内部实现单独测。 |
| 2026-10-31 | 发版前的本地构建用 `swift package edit` 只换 swift-semantic-string，不用 `USING_LOCAL_DEPENDENCIES` | 后者把 MachOKit、MachOKitExtensions 也换成本地检出，测到的就不只是本案的改动。 |
| 2026-10-31 | 加了一条术语 comment structure marking | 与已有的 marked rendering 同用「标记」一词，却是两回事，不写清楚容易混。 |
| 2026-10-31 | 实现完成，等 swift-semantic-string 发版、抬依赖下限后再收尾 | 现在只能对着它本地的 `next` 构建；本库的 tag 不能早于它发版。 |
