# ObjC 导出状态的判定 — 判据、边界与实测

> 面向维护者的实现说明。对应提案
> [0008](../Evolutions/0008-objc-export-status.md)，以及把判据改按地址的
> [0018](../Evolutions/0018-objc-exported-declarations-only.md)。
> 记录 `ObjCExportIndex` / `ObjCExportStatus` 的判据来源、为什么按地址判、三处反直觉的边界，
> 以及建索引的实测开销。
>
> 参考实现：MachOSwiftSection 的 `ExportStatus`——该项目的三份提案，0008 给输出加
> `// not exported` 标注、0016 加 `--exported-only` 过滤、0024 把标志下沉到声明模型。
> （那个 0008 是 MachOSwiftSection 的编号，与本项目的 0008 无关。）
> 本文只展开 ObjC 侧**不同**的部分。

## 概述

`ObjCExportIndex` 遍历一次镜像的 export trie，记下能发布类对象或 ivar 偏移变量的导出符号
**所在的位置**，换成 ObjC 记录的 offset 口径：clang 的 `_OBJC_CLASS_$_<类名>` 与
`_OBJC_IVAR_$_<类名>.<ivar 名>`，Swift 的类型元数据 `$s…CN` 与字段偏移 `$s…Wvd`。一个类看它的
类对象所在位置有没有导出符号（`exportStatus(ofClassObjectAt:)`），一个 ivar 看它的记录里偏移
指针所指的变量位置有没有（`exportStatus(ofIvarOffsetVariableAt:)`）。之后每次查询是一次集合
查找，返回三态的 `ObjCExportStatus`。

0008 落地时按名字查，只认 clang 的两种拼法，对 Swift 判错两类东西，见下文「为什么按地址判」。
那两个按名字查的接口（`exportStatus(ofClassNamed:)`、`exportStatus(ofIvarNamed:inClassNamed:)`）
保留，标了 deprecated。

**它回答的是链接可见性，不是访问级别。** ObjC 没有 `public` / `private` 可供恢复，
export trie 能说的只有「dyld 能不能从别的镜像解析到这个符号」。

## 为什么只有类和实例变量有入口

这是本文最需要留档的一条 —— **协议与分类不是漏做，是判不了**。

实证取 dyld shared cache 里的 AppKit 与磁盘上的 `DVTKit.framework`（Xcode 私有框架，
非 cache），用 `dyld_info -exports` 与 `nm -m` 对照：

| 对象 | 符号形态 | AppKit（cache） | DVTKit（磁盘） | 判据 |
|---|---|---|---|---|
| 类 | `_OBJC_CLASS_$_<类名>` | trie 里 667 个 | 定义 167 个类：160 个 `external`（全在 trie），7 个 `non-external` | **成立** |
| 实例变量 | `_OBJC_IVAR_$_<类名>.<ivar 名>` | trie 里 230 个 | 911 个 ivar 符号：59 个 `external`（全在 trie），852 个 `private external` | **成立** |
| 元类 | `_OBJC_METACLASS_$_<类名>` | 667 个 | 160 个 | 成立但冗余，两处都与类符号数完全相等且成对，故不做 |
| 协议 | `__OBJC_PROTOCOL_$_<协议名>` | trie 里 **0 个** | 82 个协议符号**全部**为 `non-external (was a private external)` | **不成立** |
| 分类 | 无对应符号 | — | — | **不成立** |

协议那一行是**编译器行为，不是二进制被 strip**：clang 发射 ObjC 协议符号时一律标
`.private_extern`，链接器合并后 dyld 不导出（运行时经 `objc_getProtocol` 按名字查找，
不走符号解析）。所以在任何二进制上都判不了，与 Swift 的 protocol descriptor（`…Mp`，
正常导出符号）截然不同。

与其给一个永远返回「不适用」的函数，API 里干脆没有这个入口 —— 调用方在编译期就会
发现，而不是在运行期收到一个永远无意义的值。

DVTKit 那 7 个未导出的类，说明这个事实的实际用途：

```
_OBJC_CLASS_$__DVTNSAccessibilityIndexedMockUIElement
_OBJC_CLASS_$__DVTNSPathControlAuxiliary
_OBJC_CLASS_$__TtC6DVTKit35DVTPathControlNavigationPopoverItem
_OBJC_CLASS_$__TtCC6DVTKit25DVTTextCompletionListView13DebugTagLayer
```

前两个是 `_` 前缀的 ObjC 私有类，后两个是 Swift 定义的 `internal` 类。0008 据此认为 Swift 类
不需要特殊处理，符号名就是前缀拼上运行时名。这只对有 ObjC 祖先的 Swift 类成立，这两个类恰好
都有，见下一节。表里量的也只是 clang 的两种拼法。

## 为什么按地址判

0008 的判据对 Swift 错在两处，都是因为 Swift 不用 clang 的拼法：

- **类。** Swift 给类对象的符号是类型元数据 `$s…CN`；只有类带 ObjC 祖先时，才在同一地址加一个
  `_OBJC_CLASS_$_<运行时名>` 别名（`swift/lib/IRGen/GenMeta.cpp` 只在 `classDecl->isObjC()` 时调用
  `emitObjCClassSymbol`）。根类是 `Swift._SwiftObject` 的纯 Swift 类没有这个别名，却照样进
  `__objc_classlist`（同一函数里 `addObjCClass` 不看 `isObjC()`）。按名字查，它们全读成未导出：
  macOS 27.2 的类列表里，导出的 `_Tt` 命名 Swift 类 SwiftUI 26 个错 25 个，SwiftUICore 109 个错
  103 个，AppKit 19 个错 12 个（如 `_TtC6AppKit8MenuItem`），Foundation 8 个错 7 个（如
  `_TtC10Foundation13__DataStorage`）。
- **ivar。** Swift 生成的 ivar 记录里，偏移指针指向字段偏移变量 `$s…Wvd`（`GenClass.cpp` 的
  `buildIvar` 取 `getAddrOfFieldOffset`），没有 `_OBJC_IVAR_$_` 符号。这包括 Swift 类，也包括用
  `@objc @implementation` 写的 ObjC 类：AppKit 导出了 77 个 `Wvd`，全部属于这类类
  （`NSGlassEffectView` 17 个、`_NSTextFormattingViewControllerFormattingDescriptor` 15 个……）。

几种拼法落在同一个位置上：`_OBJC_CLASS_$_` 别名与 `$s…CN` 都在类对象上（macOS 27.2 上 15 个两者都
导出的 Swift 类，偏移全部相同），`_OBJC_IVAR_$_` 与 `Wvd` 都在 ivar 的偏移变量上。所以改为比位置，
一条规则覆盖两种编译器。没有在名字上补规则：那要从 `_Tt…` 运行时名重整出 `$s…CN` 与 `Wvd`，得新增
demangler 依赖，而 `@objc(自定义名)` 的类名字根本对不上。

**建表时怎么挑符号。** 名字以 `_OBJC_CLASS_$_` / `_OBJC_IVAR_$_` 开头、或以 `CN` / `Wvd` 结尾的导出
符号。后两种只看后缀：别的符号碰巧也这样结尾无害，只有恰好落在类对象或偏移变量上的符号才影响判断，
而落在那里的就是在发布它。

**offset 口径。** export trie 的 offset 从镜像 header 算起，ObjC 记录的 offset 不一定：

| 来源 | 记录的 offset | export trie 条目换成记录口径 |
|---|---|---|
| 进程内 `MachOImage` | 相对镜像 header | 不用换 |
| dyld shared cache 里的 `MachOFile` | 相对主 cache 起点（`sharedRegionStart`） | header 地址（`__TEXT` 的地址）加条目 offset，再减 `sharedRegionStart` |
| 独立的 `MachOFile` | slice 内的文件偏移 | header 地址加条目 offset，经 `fileOffset(of:)` 换成文件偏移，与解析指针时同一条路 |

这由 `ObjCMetadataSource.objcOffsets(ofExportedSymbolOffsets:)` 做，一批只读一次 load commands。

**ivar 的偏移变量在哪。** `ObjCIvarProtocol.offset(in:)` 读的是变量里的值，位置读完就丢了，所以核心
target 在 `Support/ObjCDump.swift` 末尾加了一段本 fork 的代码（`// MARK: - Ivar Offset Variables`），
`ObjCClassProtocol.ivarOffsetVariableOffsets(in:)` 照 `offset(in:)` 的同一条路解析偏移指针（文件模式里
`-interposable` dylib 指向自己导出的 bind 也算），返回变量的位置。经
`ObjCMetadataSource.objcIvarOffsetVariableOffsets(of:)` 交给索引层。

**偏移指针为空的 ivar 不会出现。** Swift 在运行时才布局的字段，ivar 记录的偏移指针为空；
`ObjCIvarProtocol.info(in:)` 读不到偏移就丢掉这个 ivar，`ObjCClassInfo.ivars` 里本来就没有它。所以
`ObjCExportStatus` 没有为「这个 ivar 没有偏移变量」加一态（提案草案里有，实现时去掉）。

**与 MachOSwiftSection 的判断一致。** 按类对象位置判，macOS 27.2 的 AppKit、SwiftUI、Foundation、
SwiftUICore 类列表里 977 个 `_Tt` 命名的 Swift 类，与 MachOSwiftSection 的判据（类型描述符 `…Mn` 是否
导出）逐个一致（`dyld_info -exports` 与类列表按类名比对）。`@objc(自定义名)` 的类按名字对不上，没有
算进去；它们都有 ObjC 祖先，`_OBJC_CLASS_$_` 与 `Mn` 在 `swift/lib/IRGen/Linking.cpp` 里同按
`getDeclLinkage` 取链接方式。

## 三处反直觉的边界

### 一、查询是 per-image 的，问错镜像会得到误导性的「未导出」

`NSArray` 是再公开不过的类，但对 Foundation 查它，答案是 `notExported` —— 因为
**`NSArray` 由 CoreFoundation 定义并导出**（toll-free bridging 的缘故，`NSDate`、
`NSURL`、`NSDictionary` 同理）。Foundation 的 trie 里根本没有它。

这个答案是对的：问题是「这个镜像导出了什么」，不是「这个类在哪导出」。但它意味着
**调用方只能拿本镜像自己定义的类去查**。从某个类的 metadata 里读出的超类名、协议采纳
里的类名，经常属于别的镜像，拿去查会得到一串毫无意义的负面答案。

这个坑属于按名字查的旧接口。按位置查时只能拿本镜像列出的记录去问：别的镜像的记录从别处
起算，它的 offset 在这里没有意义。宿主按名字查用 `ObjCInterfaceIndexer.exportStatus(ofClassNamed:)`，
它对本镜像没列出的类返回 `nil`（Foundation 问 `NSArray` 即如此），不再给出误导性的「未导出」；宿主
补充的类没有类对象可判，也返回 `nil`。

### 二、导出符号为零算「无信息」，不算「全都没导出」

`.o` 目标文件没有 export trie、dyld shared cache 镜像的 linkedit 读失败、以及一个
真的用 `-exported_symbols_list` 导出了零个符号的 dylib，从这一层看完全一样：
`exportedSymbols` 返回空数组。

三者归为 `imageHasNoExportInformation`。代价是无法判定「确实什么都不导出」的镜像，
这近乎假想；收益是不会在读取失败时把整个镜像的类**静默地全部标成内部实现类**。这与
MachOSwiftSection 提案 0016 的原则一致：拿不到证据就不裁决，过滤绝不靠猜。

### 三、不用 `ExportTrie.search(byKeyPrefix:)`

MachOKit 提供了前缀搜索，看起来正好能一次捞出 `_OBJC_CLASS_$_` 打头的所有项。**不用**，
理由是正确性：`TrieTreeProtocol._search(byKeyPrefix:)` 沿 trie 下行时用
`children.first(where:)`，前缀消耗完之后若有**多个** child 仍以该前缀开头，只取其中一个，
其余分支整个丢掉。能否取全取决于 trie 恰好在 `_OBJC_CLASS_$_` 处有节点边界 —— 常见的
export trie 生成器确实会把公共前缀压成一层，但「通常正确」不是能拿来建判据的东西。漏一个
分支就是把一批导出的类静默报成内部类。

改为遍历一次 `machO.exportedSymbols` 分拣。实测（见下）这条路 95% 的开销在 MachOKit 解析
trie 本身，分拣只占 1 毫秒左右，所以前缀搜索即便正确也省不下什么。

## 实测：建索引的开销

macOS 26.x / arm64e，dyld shared cache 内的镜像，10 次取中位数：

| 镜像 | 建索引 | 其中 `exportedSymbols` 本身 | 导出符号总数 | 类符号 | ivar 符号 |
|---|---|---|---|---|---|
| Foundation | 40.9 ms | 38.7 ms（94.6%） | 15509 | 397 | 98 |
| AppKit | 23.2 ms | 22.2 ms（95.7%） | 8771 | 667 | 230 |
| SwiftUI | 51.4 ms | 49.2 ms（95.8%） | 19471 | 13 | 0 |

分母：同一台机器上 AppKit 走一遍 `ObjCInterfaceIndexer.prepare()` 是 **27.2 秒**
（2573 个类）。建索引占 **0.085%**，即无条件建表是免费的，不需要开关也不需要延迟构建。

两条附带结论：

- **瓶颈在 MachOKit 解析 trie**（95%），不在本模块的分拣循环。要再优化只能换读取方式，
  而唯一现成的换法（前缀搜索）有上面那个正确性问题。
- **纯 Swift 框架的索引近乎空表**：SwiftUI 只有 13 个 ObjC 类符号、0 个 ivar 符号。
  这是正常的，不是读取失败 —— 区分二者靠的是 `exportedSymbols` 总数不为零。

Set 的规模跟着类符号数走（百量级的短字符串），内存不构成考量。

### 2026-10-31：放进 `prepare()` 之后

`ObjCInterfaceIndexer.prepare()` 现在建一次 `ObjCExportIndex`，并对每个列出的类查一次类对象的结论，
存进 indexer。macOS 27.2 / arm64e，进程内镜像，调试构建，5 次取中位数；测量时机器上还有别的会话在编译，
负载 30–44，绝对值偏大，比例可参考：

| 镜像 | 类数 | `prepare()` | 建索引 + 每类一次查找 | 占比 | 若再读一遍每个类的 ivar 列表 |
|---|---|---|---|---|---|
| Foundation | 891 | 1.00 s | 45 ms | 4.5% | 另加 25–61 ms |
| AppKit | 2773 | 4.00 s | 31 ms | 0.8% | 另加 159–177 ms |
| SwiftUI | 361 | 0.65 s | 43 ms | 6.6% | 另加 11–16 ms |

`prepare()` 比 0008 测量时快了一个数量级（AppKit 27.2 s → 3–5 s），所以建索引那一趟（20–60 ms，几乎
全是 MachOKit 解析 trie）在 ObjC 类少的框架上占到几个百分点。

**ivar 的结论不在 `prepare()` 里算**，最后一列就是原因：要知道偏移变量在哪，得再读一遍类的 ivar 列表，
进程内每读一次类数据都先用 `mach_vm_read_overwrite` 探测内存是否可读（`MachOObjCSectionC/memory_probe.c`），
对每个类都做一遍，AppKit 的 `prepare()` 要多 4% 左右。侧栏只要类的结论，ivar 的结论只在打印那一个类时
有用，所以由打印器当场算，indexer 只把 `ObjCExportIndex` 留给它（`package var exportIndex`）。

## 打印时怎么用这些结论

`ObjCGenerationOptions.printExportedDeclarationsOnly`（可见性选项 `objc.printExportedDeclarationsOnly`，名字照
MachOSwiftSection 的同名开关取）由 `ObjCInterfaceBuilder` 执行，只在有确定的「未导出」时动手：

- **类**：`indexer.exportStatus(ofClassNamed:)` 是 `notExported` 的打印成空串。返回的是空的 `SemanticString`，
  不是 `nil`，`nil` 仍只表示镜像里没有这个类；宿主据此显示占位说明、批量导出跳过它。宿主补充的类没有结论，
  不受影响。
- **ivar**：在打印这个类时当场读偏移变量的位置，按 `indexer.exportIndex` 判，未导出的进 `StrippedMembers`，与
  strip 开关走同一张表。普通打印取并集过滤，标记模式据此给成员标条件。
- **类别**：目标类是本镜像列出的类、且结论是 `notExported` 时整个打印成空串，照 MachOSwiftSection 0083 / 0016
  删「本镜像未导出类型的扩展」的规则；目标类在别的镜像（没有结论）的整个保留，成员没有符号可判。实测系统框架里
  这种类别一个也没有：链接器默认把同一镜像里加在本镜像类上的类别并进类本身（见
  [提案 0017](../Evolutions/0017-objc-duplicate-member-selection.md)），所以这条规则落在不合并类别的镜像上，
  fixture 用 `-Wl,-no_objc_category_merging` 造出这种形态。
- **方法、属性、协议、C struct / union** 都没有自己的导出符号，不动。

**标记模式下整个声明怎么标。** 被排除的类与类别照常打印，再用 swift-semantic-string 的
`markAtoms(from: 0, visibleUnder: .disabled("objc.printExportedDeclarationsOnly"))` 把每个原子标上「开关关着才可见」。
不能包一层 `VisibilityRegion`：那会在声明外面多一层普通打印没有的元素，投影的 span 与普通打印对不上（对照测试比的是
文本、span 与 identifier 三样）。`markAtoms` 只改 identifier，文本、类型、原子数与元素边界都不变，开关打开时投影出来
恰好是空串，连换行也没有——RuntimeViewer 的 Find 语料把投影为空的条目当作不存在。MachOSwiftSection 0083 的
`visible(under:)` 是同一个做法。

实测（macOS 27.2，进程内）开关打开后：

| 镜像 | 类 | 打印为空 | 去掉了部分 ivar | 类别 | 打印为空的类别 |
|---|---|---|---|---|---|
| Foundation | 891 | 529 | 213 | 73 | 0 |
| AppKit | 2773 | 2062 | 595 | 69 | 0 |
| SwiftUI | 361 | 321 | 20 | 10 | 0 |

## 测试怎么钉住这些

`Tests/ObjCMetadataSourceTests/ObjCExportIndexTests.swift` 跑在 Foundation 上，主力是几条交叉验证：

- **地址交叉验证**（`exportedClassSymbolSitsAtClassRecordAddress`）：导出的 `_OBJC_CLASS_$_` 落在
  **该类记录自己的地址**上，这是按位置判的前提。两种 offset 口径混用时它会红，只看结论的测试发现不了。
- **结论跟着发布它的符号走**（`classVerdictFollowsItsPublishingSymbol`）：有导出的 `_OBJC_CLASS_$_` 的类
  必须读作已导出；没有它却读作已导出的，必须是 Swift 类、且类对象上有导出的 `$s…CN`。
- **ivar 的偏移变量**（`exportedIvarSymbolSitsAtItsOffsetVariable`）：每个导出的 `_OBJC_IVAR_$_<类>.<ivar>`
  恰好落在 `objcIvarOffsetVariableOffsets(of:)` 给那个 ivar 的位置上，读出的结论是已导出。
- **file / image 双模式一致**（`fileModeAndImageModeAgreeOnEveryClassAndIvar`）：同一个 Foundation，
  一次作为 cache 里的 `MachOFile`、一次作为进程内的 `MachOImage`，逐个类、逐个 ivar 比对。两种模式的
  offset 起算点不同，换算错了这条会红；`MachOFile` 读 cache 镜像的 linkedit 走的是完全不同的路径
  （`_fileSliceForLinkEditData` 的重定向），它没坏也靠这条。
- **ivar 反向验证**（`exportedIvarSymbolsNameDeclaredIvars`）：把 trie 里每个
  `_OBJC_IVAR_$_<类>.<ivar>` 拆开，要求镜像确实在**那个类**上声明了这个 ivar，钉住「`ObjCClassInfo.ivars`
  只含本类自己的 ivar」这条上游假设。

另有一条 `exportTrieSymbolNamesCarryLeadingUnderscore` 钉住 MachOKit 交还的符号名带前导
下划线。若某个 MachOKit 版本开始剥它，按前缀挑出的符号会静默落空 —— 没有崩溃也没有空结果
可供察觉，只有这条测试会红。

Swift 一侧的形态在系统框架里随版本变，所以用现场编译的 fixture 钉死
（`Tests/ObjCMetadataSourceTests/ExportedDeclarationsVerdictTests.swift`）：一个 Swift dylib 有公开与
internal 的纯 Swift 类、NSObject 子类，各带公开与 internal 的存储属性；一个 ObjC dylib 有导出的类与
`visibility("hidden")` 的类、`@public` 与 `@private` 的 ivar。文件模式与进程内各比对一遍每个类、每个
ivar 的结论，另有一条确认 Swift dylib 确实只用 Swift 的拼法发布（没有 `_OBJC_CLASS_$_` 别名的根类、
没有任何 `_OBJC_IVAR_$_`）。按名字查时，公开的纯 Swift 类与两个 Swift 类的公开 ivar 读作未导出，这条
测试在修复前对着旧判据跑过、确认是红的。

打印由 `Tests/ObjCMetadataSourceTests/ExportedDeclarationsRenderingTests.swift` 钉住：两个 fixture、两种模式下开关打开时
去掉了什么、留下了什么，每个类与类别的标记打印按全关、全开、每个开关单开与单关投影后与普通打印逐字一致，打印为空的投影
也必须为空。`ObjCMarkedInterfaceTests` 在 Foundation 全部声明上做同样的投影比对，组合里含这个开关，另有一条确认开关在
Foundation 上确实去掉了类与 ivar，免得投影比对空跑。

## 本轮不做的

- **CLI 一个字节没动**。MachOSwiftSection 提案 0008 的 `// not exported` 标注没有 ObjC 对应物；
  0016 的 `--exported-only` 过滤后来有了库层面的对应物（`printExportedDeclarationsOnly`，见上文「打印时怎么用这些
  结论」），`objc-section` 命令行按 0010 退役，没有加这个 flag。
- **不进 `ObjCAPISnapshot` / `ObjCDiffing`**。导出状态是符号化状态，不是 API 事实；
  加字段还会破坏既有 baseline 的 `formatVersion` 契约。
- **没有进程级缓存**。本库没有 MachOSwiftSection 那套 `SharedCache` 基座，
  `ObjCExportIndex` 是值类型，生命周期由调用方掌握。
