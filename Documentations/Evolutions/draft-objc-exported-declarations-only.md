# Draft - 只打印导出的 ObjC 声明，导出判断改按地址

- **状态**: In Progress
- **创建日期**: 2026-10-31
- **最后更新**: 2026-10-31
- **实现分支**: `feature/objc-exported-declarations-only`（worktree `.worktrees/MachOObjCSection-ExportedDeclarationsOnly`，从 `next` 切）
- **关联提案**: [0008](0008-objc-export-status.md)（导出状态的事实层，本案修正其中类与 ivar 的判据）、[0011](0011-visibility-regions.md)（标记模式）；
  MachOSwiftSection 的 0083 `exported-only-marking-mode`（Swift 一侧的同一功能）；RuntimeViewer 的 `draft-exported-declarations-filter`（使用方）

## 摘要

RuntimeViewer 已经能只看导出的 Swift 声明，ObjC 一侧缺本库的支持。本案给 `ObjCGenerationOptions` 加
`printExportedDeclarationsOnly`：打开时，未导出的类打印为空，挂在本镜像未导出的类上的类别打印为空，偏移变量未导出的
ivar 被去掉；没有自己导出符号的方法、属性、协议一律保留。标记模式（0011）同样覆盖这个开关。导出判断在
`ObjCInterfaceIndexer.prepare()` 里一次算好，侧栏不经过打印就能直接查。

调研时发现 0008 的判据在 Swift 上有两处错，不修的话 RuntimeViewer 两个列表的标记对不上：

1. **类按 `_OBJC_CLASS_$_<类名>` 判。** Swift 只给有 ObjC 祖先的类生成这个符号（`swift/lib/IRGen/GenMeta.cpp` 只在
   `classDecl->isObjC()` 时调用 `emitObjCClassSymbol`），纯 Swift 类（根类是 `_TtCs12_SwiftObject`）没有它，却照样列在
   `__objc_classlist` 里，于是一律读成未导出。macOS 27.2 的类列表里，导出的 Swift 类 SwiftUI 26 个错 25 个，SwiftUICore
   109 个错 103 个，AppKit 19 个错 12 个（如 `_TtC6AppKit8MenuItem`），Foundation 8 个错 7 个（如
   `_TtC10Foundation13__DataStorage`）。
2. **ivar 按 `_OBJC_IVAR_$_<类名>.<ivar 名>` 判。** Swift 生成的 ivar 记录（Swift 类，以及用 `@objc @implementation` 写的
   ObjC 类）里，偏移指针指向 Swift 自己的字段偏移变量 `$s…Wvd`（`GenClass.cpp` 的 `buildIvar`），名字与 `_OBJC_IVAR_$_`
   无关。AppKit 导出了 77 个这样的变量，全部属于 `@objc @implementation` 的类（`NSGlassEffectView` 17 个、
   `_NSTextFormattingViewControllerFormattingDescriptor` 15 个……），按名字查一律读成未导出，开关一开就被误删。

## 方案

**1. 判据改按地址（事实层 `ObjCExportIndex`）。**

- **类**：类对象所在位置上有没有导出符号。clang 的 `_OBJC_CLASS_$_`、Swift 的 `_OBJC_CLASS_$_` 别名与类型元数据 `$s…CN`
  都落在类对象上（抽查 macOS 27.2 上 15 个两者都导出的 Swift 类，偏移全部相同）。clang 编译的类结论与原判据相同。
- **ivar**：ivar 记录的偏移指针所指的变量上有没有导出符号，clang 的 `_OBJC_IVAR_$_` 与 Swift 的 `Wvd` 都在这里。偏移指针
  为空（Swift 在运行时才布局的字段）的 ivar 本来就不在 `ObjCClassInfo.ivars` 里（`ObjCIvarProtocol.info(in:)` 读不到偏移
  就丢掉它），不需要为它加状态，`ObjCExportStatus` 不变。
- **建表仍是一趟 export trie**：额外记下名字以 `_OBJC_CLASS_$_`、`_OBJC_IVAR_$_` 开头或以 `CN`、`Wvd` 结尾的导出符号的位置，
  换成 ObjC 记录的 offset 口径存下（export trie 从镜像 header 算起）：进程内镜像两者本就相同；cache 里的文件是 header 地址加
  条目 offset 再减 `sharedRegionStart`；独立文件经 `fileOffset(of:)` 换成文件偏移，与解析指针时同一条路。查询是按位置的
  `exportStatus(ofClassObjectAt:)` 与 `exportStatus(ofIvarOffsetVariableAt:)`。
- `ObjCMetadataSource` 加两个要求：一个类每个 ivar 的偏移变量位置（`objcIvarOffsetVariableOffsets(of:)`），以及把一批 export
  trie 条目换成本来源的 offset 口径（`objcOffsets(ofExportedSymbolOffsets:)`）。该协议的文档本来就说明要求会随索引层的需要
  增长，且只有本库的两个遵循者。偏移变量的位置要照 `ObjCIvarProtocol.offset(in:)` 的路解析指针，用的是核心 target 内部的
  函数，所以照 0014 的先例，`ObjCClassProtocol.ivarOffsetVariableOffsets(in:)` 追加在 `Support/ObjCDump.swift` 末尾，上游代码不动。
- 按名字查的 `exportStatus(ofClassNamed:)` 与 `exportStatus(ofIvarNamed:inClassNamed:)` 标 deprecated，消息指向按位置的
  查询与下面 indexer 上的类查询。RuntimeViewer、MachOSwiftSection、MachOKitUI、MachOViewer、swift-decompiler 都没有用它们。

**2. indexer 在 `prepare()` 里算好每个类的结论。** 建一次 `ObjCExportIndex`，对类列表里的每个类查一次类对象的结论存下：

```swift
extension ObjCInterfaceIndexer {
    /// `nil`: this image lists no class object of that name — a class of another image, or one the host supplied.
    public func exportStatus(ofClassNamed className: String) -> ObjCExportStatus?
    /// The index `prepare()` built, for the builder to judge the ivars of the one class it renders.
    package var exportIndex: ObjCExportIndex? { get }
}
```

宿主补充的类（0014：泛型 Swift 类与经 stub 注册的类）没有类对象可比，返回 `nil`，不判。宿主只按
`isDefinitelyNotExported` 打标。ivar 的结论不在 `prepare()` 里算，由打印器在打印某个类时当场算（见决策日志）。

**3. 打印。** `ObjCGenerationOptions.printExportedDeclarationsOnly`（默认关，旧设置解码为关），可见性选项
`objc.printExportedDeclarationsOnly`，名字与 MachOSwiftSection 的 `printExportedDeclarationsOnly` /
`swift.printExportedDeclarationsOnly` 一致，宿主一个开关映射到两边。开着时：

- **类**：明确未导出的打印为空。返回空的 `SemanticString`，不是 `nil`，`nil` 仍只表示镜像里没有这个类。
- **ivar**：明确未导出的去掉，与 strip 开关走同一张 `StrippedMembers` 表。
- **类别**：目标类是本镜像列出的类、且明确未导出时打印为空，照 0083 / 0016 对「本镜像未导出类型的扩展」的规则；目标类在
  别的镜像、或判断不了，整个保留。类别的成员没有导出符号，不逐个判断。
- **方法、属性、协议、C struct / union** 都没有自己的导出符号，不动。

**4. 标记模式。** 上面每处「不输出」改为照常输出，标上 `.disabled("objc.printExportedDeclarationsOnly")`：整个类或类别
包一层 `VisibilityRegion`，ivar 进 `ObjCOptionalContentMarking`，与 strip 开关同一张表。投影结果与普通打印逐字一致；
开关关着时，普通打印逐字节不变。被排除的类与类别必须整段落在这个区域里，开关打开时投影出来恰好是空串，不剩空行或注释：
RuntimeViewer 的 Find 语料把投影为空的条目当作不存在。

**测试。**

- 现场编译的 fixture，照 `SuppliedClassFixture` 的做法：一个 Swift dylib（公开与 internal 的纯 Swift 类、NSObject 子类，
  公开与 internal 的存储属性），一个 ObjC dylib（导出的类与 `visibility("hidden")` 的类、`@public` 与 `@private` 的 ivar、
  挂在 hidden 类上的类别）。文件模式与进程内各跑一遍。纯 Swift 类与 Swift ivar 两条先对着旧判据跑出红，再修。
- 真实镜像上的交叉验证：Foundation 进程内与 cache 文件两种模式，每个类、每个 ivar 的结论一致；每个以 `CN` 结尾、落在列出
  的类对象上的导出符号，对应的类读作已导出；clang 编译的类新旧判据一致。
- 渲染：fixture 与 Foundation 上开关开、关两种普通打印；`ObjCMarkedInterfaceTests` 的组合加入新开关（全开、全关、单开、
  单关），断言投影与普通打印逐字一致，并断言 Foundation 上确实有被过滤的类、ivar 与类别，免得测试空跑。被排除的类与
  类别另断言开关打开时的投影恰好是空串。
- `prepare()` 的额外耗时实测后记下（实测见决策日志与实现说明）。
- 照仓库惯例，用 CI 的 Xcode 26.6 再编一遍。

**与 Swift 一侧的一致性。** 按上面的类判据，macOS 27.2 的 AppKit、SwiftUI、Foundation、SwiftUICore 类列表里 977 个以 `_Tt`
命名的 Swift 类，与 MachOSwiftSection 的判据（类型描述符 `…Mn` 是否导出）逐个一致（`dyld_info -exports` 与类列表按类名
比对）。用 `@objc(自定义名)` 的 Swift 类按名字对不上，没有算进去；它们都有 ObjC 祖先，`_OBJC_CLASS_$_` 与 `Mn` 的链接方式
相同（`Linking.cpp` 里两者同在 `getDeclLinkage` 那一组）。RuntimeViewer 接入后可以再从宿主一侧逐个核对。

**不做。**

- 宿主补充的类不判（见第 2 点）。
- 不改 `objc-section` 命令行（按 0010 退役）；`swift-section objc` 要不要加 flag 由 MachOSwiftSection 决定。
- 不进 snapshot / diff，理由同 0008：导出状态是符号层面的事实，不是 API 事实。

**文档。** `Internal/ObjCExportStatusResolution.md` 补「按地址判断」一节（两处错、Swift 的符号形态、偏移口径、实测数据），
术语表的 `ObjCExportStatus` 条目同步，使用指南的库调用方部分加一节（开关、空打印与 `nil` 的区别、per-image 语义、判断
不了的保留）。

**落地步骤。** 每一步单独构建通过、相关测试通过后提交一次。

1. ✅ 事实层：`ObjCExportIndex` 建表时记下四类符号的位置，按位置判断类对象与 ivar 偏移变量；`ObjCMetadataSource` 的两个
   新要求与核心 target 末尾的 `ivarOffsetVariableOffsets(in:)`；按名字查的两个查询标 deprecated。测试：两个现场编译的
   fixture 与 Foundation 上的交叉验证，纯 Swift 类与 Swift ivar 两条先对着旧判据跑红。
2. ✅ indexer：`prepare()` 里建索引、算出每个类的结论，提供 `exportStatus(ofClassNamed:)`。测试：fixture 与 Foundation 上的
   结论、补充类与别的镜像的类返回 `nil`。
3. 打印：`printExportedDeclarationsOnly` 与可见性选项；普通打印按结论去掉类、ivar 与类别。测试：开关开、关两种打印，旧设置的
   解码。
4. 标记模式：类、类别与 ivar 的标记。测试：投影与普通打印逐字一致，被排除的类与类别开关打开时投影恰好为空串。
5. 文档与收尾验证：实现说明、术语表与使用指南；`prepare()` 的耗时实测；全量测试；Xcode 26.6 编译。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-31 | Created as Draft | RuntimeViewer 做完了只看导出的 Swift 声明，ObjC 一侧需要本库提供打印过滤、标记模式与可直接查询的类结论；调研中发现 0008 的判据把纯 Swift 类与 Swift 生成的 ivar 判成未导出 |
| 2026-10-31 | 判据改按地址，不在名字上补规则 | 按名字修要从 `_Tt…` 运行时名重整出 `$s…CN` 与 `Wvd`，得新增 demangler 依赖，`@objc(自定义名)` 的类也对不上；按地址一条规则同时覆盖 clang 与 Swift 两种发射方式 |
| 2026-10-31 | 推翻 0008「不改 `ObjCInterfaceIndexer`」 | 0008 时 RuntimeViewer 用自己的索引器；现在它包着本库的 `ObjCInterfaceIndexer`（`upstream`），结论放进 indexer，打印与侧栏读同一份 |
| 2026-10-31 | 按名字查的两个查询标 deprecated，不删 | 它们给出的是确定但错误的答案，要让调用方看见；没有已知使用方，删掉也无妨，但删公开 API 要等下一次破坏性版本 |
| 2026-10-31 | 打印为空返回空串，不返回 `nil` | 与 MachOSwiftSection 一致：RuntimeViewer 据此显示占位说明、批量导出跳过；`nil` 保持「镜像里没有这个对象」一种含义 |
| 2026-10-31 | Swift 生成的 ivar 按 `Wvd` 是否导出判，不当作判断不了 | 偏移变量本来就是 `Wvd`，这正是「偏移变量没导出」的字面判据；苹果的 Swift 框架普遍不导出 `Wvd`（SwiftUI 0 个、Foundation 1 个），开关一开 Swift 类的 ivar 基本都会去掉，这与 ObjC 客户端拿不到这些 ivar 的事实相符 |
| 2026-10-31 | RuntimeViewer 确认按草案的 API 能接；验收加一条：被排除的类与类别在标记模式下开关打开时投影恰好为空串 | RuntimeViewer 没用过 `ObjCExportIndex` / `ObjCExportStatus`，改判据与新增 case 不影响它；它的 Find 语料把投影为空的条目当作不存在，剩一个空行或注释就会留下空条目 |
| 2026-10-31 | 用户批准，开始实现；状态 Draft → Accepted | 方案与落地步骤如上，实现在 `feature/objc-exported-declarations-only` |
| 2026-10-31 | Accepted → In Progress；第 1 步完成 | 两个现场编译的 fixture 先对着按名字查的旧判据跑：公开的纯 Swift 类、两个 Swift 类的公开 ivar 共 3 条断言失败（原始退出码 1）；改按位置后 fixture 与 Foundation 上 14 个测试全过 |
| 2026-10-31 | 不新增 `ObjCExportStatus.declarationHasNoSymbol` | 草案为偏移指针为空的 ivar 准备了这一态。实测这种 ivar 根本到不了判断这一步：`ObjCIvarProtocol.info(in:)` 读不到偏移就丢掉它，`ObjCClassInfo.ivars` 里没有它，列出的类不会遇到；宿主补充的类本来就不判。不加 case，枚举对穷举它的调用方保持源码兼容 |
| 2026-10-31 | 偏移变量的位置由核心 target 末尾新加的 `ObjCClassProtocol.ivarOffsetVariableOffsets(in:)` 读，照 0014 的先例 | 要与 `offset(in:)` 走同一条指针解析的路（文件模式的 `resolveRebase(_:)` 是核心 target 内部的，进程内要经 `private` 的 `data(in:)` 找 RO data）；MachOKitExtensions 公开的 `resolveRebase(fileOffset:)` 缺少自绑定与旧格式 rebase 的兜底，照抄核心的逻辑又会出现两份。追加在文件末尾、标明属于本 fork，上游代码一行不动 |
| 2026-10-31 | export trie 条目换口径成为 `ObjCMetadataSource` 的批量要求 `objcOffsets(ofExportedSymbolOffsets:)`，独立文件经 `fileOffset(of:)` 换 | 草案打算沿用「文件偏移等于相对 header 的偏移」的约定；改为与解析指针时同一个函数换算，两边口径由构造保证一致，不靠这个约定。批量是为了只读一次 load commands |
| 2026-10-31 | 0008 里依赖按名字查询的测试改用新查询，`classDefinedInAnotherImageReadsAsUnexportedHere` 与 `ivarLookupIsQualifiedByDeclaringClass` 删去 | 两条测的是已 deprecated 的按名字查询的行为，新查询按位置，不存在「问错镜像得到误导性负面答案」与「名字拼错」这两种情形；per-image 的约束改由第 2 步的 indexer 查询对别的镜像的类返回 `nil` 来体现 |
| 2026-10-31 | 第 2 步完成；ivar 的结论不在 `prepare()` 里算，indexer 不提供 `exportStatus(ofIvarNamed:inClassNamed:)`，改由打印器在打印某个类时当场算 | 实测（调试构建，机器负载 30–44）：在 `prepare()` 里为每个类再读一遍 ivar 列表，AppKit 多 159–177 ms，约占 `prepare()` 的 4%——进程内每读一次类数据都先用 `mach_vm_read_overwrite` 探测内存。只算类的结论时，AppKit 只多 31 ms（0.8%），Foundation 45 ms（4.5%）、SwiftUI 43 ms（6.6%），几乎全是 MachOKit 解析 trie。侧栏只要类的结论，ivar 的结论只在打印那一个类时有用；indexer 把 `ObjCExportIndex` 以 `package` 的 `exportIndex` 留给打印器。宿主要逐个 ivar 的结论，可直接用事实层的 `exportStatus(ofIvarOffsetVariableAt:)` 与 `objcIvarOffsetVariableOffsets(of:)`。RuntimeViewer 只用类的查询，不受影响 |
