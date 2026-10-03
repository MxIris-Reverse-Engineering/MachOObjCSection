# dyld cache 里的指针槽位必须先解码

> 面向维护者的实现说明。没有对应提案：这是一次明显的 bug 修复。
>
> 记录 2026-10-03 修掉的一个崩溃的根因、由此确立的读取规则、受影响的范围和验证数据。崩溃的现象是 `swift-section objc` 在 macOS 14.4–15.3.2 的 dyld shared cache 上以 SIGTRAP 退出（rc=133，stdout 与 stderr 都是空的）。

## 规则

从 dyld shared cache 镜像里读出来的每一个指针槽位，都要先经 `MachOFile.resolveRebase(_:)` 解码再用。**不能**把槽位的原值交给 `fileHandleAndOffset(forAddress:)`，也不能拿它去减 `sharedRegionStart`。

- 结构体字段走 `_FixupResolvable.unresolvedValue(of:)`，再交给 `resolveRebase`。
- 用 `readDataSequence` 批量读出的列表条目没有 `_FixupResolvable` 可用，要自己算出每个槽位的偏移，构造 `UnresolvedValue(fieldOffset:value:)`。现成的写法见 `ObjCPropertyList.properties(in:)` 和 `ObjCMethodList.pointerMethod(_:in:entryOffset:)`。
- 偏移与 `resolveRebase` 返回的 `ResolvedValue.offset` 用的是同一套约定：cache 镜像是「相对主 cache 起点的偏移」，独立文件是「相对 Mach-O header 的文件偏移」。所以一个解出来的 `ResolvedValue.offset` 可以直接当下一个槽位的 `fieldOffset` 用（`extendedMethodTypes(in:)` 就是这样读数组元素的）。

## 为什么原值不是地址

dyld shared cache 的可写映射（`__DATA`、`__DATA_CONST`、`__AUTH`、`__AUTH_CONST`）各带一份 slide info：一张记录「哪些 8 字节槽位是指针、加载时要按随机滑动量修正」的表。槽位里存的是这张表规定的编码，不是指针本身。MachOKit 的 `DyldCache.resolveOptionalRebase(at:)` 按映射的 slide info 版本解码，`resolveRebase` 就是在它外面一层。

本仓库归档的 arm64e cache 用到了两种格式，`ipsw dyld info <cache>` 的映射表会写明版本：

| 格式 | 用在 | 槽位原值 | 把原值当地址用的后果 |
|---|---|---|---|
| slide info v3 | macOS 11.0.1–14.3.1 | 目标地址（低 51 位），加上 `到下一个 fixup 的距离 << 51` | 高位让地址查找落空：读出来的字符串是空的，不崩 |
| slide info v5 | macOS 14.4 起 | **相对 cache 起点的偏移**（低 34 位），加上 `high8 << 34`、`next << 52`、`auth << 63` | `next ≠ 0` 时同样查找落空；`next = 0` 的槽位（每页 fixup 链的最后一个）是一个小于 `sharedRegionStart`（`0x180000000`）的裸偏移，减法下溢，Swift 直接陷阱退出 |

两个实例，都用 `ipsw dyld dump` 核对过解码结果：

- 15.0（v5），Foundation 的 `NSXPCListenerDelegate`：`listener:shouldAcceptNewConnection:` 的 types 槽位原值是 `0x24B0EDE`（`next = 0`）。按 v5 解码，目标是 `0x180000000 + 0x24B0EDE = 0x1824B0EDE`，那里是 `B32@0:8@16@24`。原代码对它做 `0x24B0EDE - 0x180000000`，崩溃就出在这里。
- 14.3.1（v3），libobjc 的 `NSObject` 协议：`release` 的 name 槽位原值是 `0x0008_0001_CF79_43B7`，低 51 位 `0x1CF7943B7` 是 `release` 字符串的地址，bit 51 上的 1 是「下一个 fixup 在 8 字节之后」。

**独立 Mach-O 文件为什么一直没出问题**：它的槽位原值要么本来就是地址（旧式 `LC_DYLD_INFO` 重定位），要么是 chained fixup 编码。后者碰巧被 `MachOFile.fileOffset(of:)` 里的 `stripPointerTags` 剥掉高位，再加上它把「低于 `__TEXT` 的值」当文件偏移的处理，结果正好对。cache 镜像不走这条路，所以这个 bug 只出现在 cache 上。修复后独立文件的槽位也改走 `resolveRebase`，A/B 输出逐字节不变（见下文验证数据）。

## 受影响的读取

**指针格式的方法列表**（`method_t { SEL name; const char *types; IMP imp; }`）。在 cache 里它几乎只剩协议的方法列表：类和 category 的方法列表早已被 cache builder 转成相对格式，属性、ivar 等字段也一直走 `resolveRebase`，都不受影响。

协议方法列表的格式随版本变化，症状也随之不同：

| macOS | 协议方法列表 | 修复前的症状 |
|---|---|---|
| 11.0.1–14.3.1 | 几乎全是指针格式，slide info v3 | 方法名、类型丢失：`objc interface NSCoding` 打出 `- (Unknown);`。14.3.1 上 Foundation 的 dump 里有 290 个、AppKit 有 2730 个无名方法 |
| 14.4–15.3.2 | 几乎全是指针格式，slide info v5 | SIGTRAP 崩溃。`ObjCInterfaceIndexer.prepare()` 会读镜像里的每个协议，所以几乎任何镜像都会碰上一个链尾槽位，`objc interface` 无论问哪个声明都崩 |
| 15.4.1–15.8.1 | Foundation 等大多数镜像的协议改成了相对格式，但 CoreFoundation 的协议（如 `NSCopying`）一直是指针格式，每个版本都有 37 个方法读不出 | 不崩，但这些协议的方法名为空，`--strip-protocol-conformance` 因此剔不掉 `copyWithZone:` 这类成员 |
| 26.0、27.0 | 没有观察到指针格式的协议方法列表 | 无 |

下游也受影响：MachOSwiftSection 判定「显式 selector」（`@objc(name)`）的前提之一是读全了所有采纳协议的 selector，而它把读到的空 selector 记为「没读全」（`ObjCClassMethodIndex.swift` 里的 `RawObjCProtocolSelectors.insert`）。在 15.8.1 及更早的 cache 上，凡是采纳了指针格式协议的类，判定都因此被压住，没有出错，只是少了信息。修复后 15.0 上 AppKit 的 NSGradient 等成员补上了 explicit selector 标注，与 26.0 上的输出一致。

同样写法的还有 `ObjCProtocolProtocol.extendedMethodTypes(in: MachOFile)`：它把 `_extendedMethodTypes` 数组的第一个元素当地址读。这是公开 API，库内和下游都没有调用者，这次按同一规则一并修了。

## 来历

这段代码以前没有人修过。2025-11-04 上游 p-x9 的两个提交是转折点：

- `1964e5c` 引入了 `ResolvedValue` 与 `resolveRebase`，把各种字段迁了过去。`ObjCPropertyList` 的批量条目也在这次逐个改走 `resolveRebase`。
- 同一天的 `2c21960`（「Fix to convert address to file offset in method list」）把方法列表条目从 `fileHandleAndOffset(forOffset:)`（把原值当偏移，错）改成了 `forAddress:`（把原值当地址，在 cache 上还是错）。

再往前，条目经 `fileOffset(of:)` 读取，它的 `stripPointerTags` 碰巧能剥掉 v3 的高位，但从来处理不了 v5，因为 v5 存的根本不是地址。方法列表条目是批量读出的，没有 `_FixupResolvable` 可用，所以那次迁移漏掉了它们。截至 2026-10-03，上游 main 仍是同样的代码。

## 加固

除了让槽位先解码，还去掉了两处会因输入异常而让进程陷阱退出的减法：

- `fileHandleAndOffset(forAddress:)` 原先先算 `address - sharedRegionStart`，再在 `cacheAndFileOffset(fromStart:)` 里加回去。现在直接用 `cacheAndFileOffset(for:)` 按地址查找，查找本身带范围检查，低于共享区的地址查不到就返回 nil。
- `resolveRebase` 在槽位没有可解的 rebase 时会退回原值（原设计如此）。原值可能是 0，也可能是 slide info 解码器不认的编码。现在退回的值低于共享区时返回 nil，不再减出下溢。

理由：这个库读的是任意二进制，宿主是 CLI 和 RuntimeViewer。一个解不出来的指针应当降级成「读不出」，而不是让整个宿主进程退出。

## 测试怎么钉住这些

`Tests/ObjCMetadataSourceTests/DyldCachePointerMethodListTests.swift`，四个用例，修复前全部变红：

| 用例 | 钉住什么 | 修复前 |
|---|---|---|
| `slideInfoV5ChainEndSlotResolves` | 15.0 Foundation 上 `NSXPCListenerDelegate` 的方法名与类型：报告里那个崩溃的槽位 | 测试进程 signal 5 |
| `slideInfoV3SlotsResolve` | 14.3.1 Foundation 上 `NSCoding` 两个方法的名字与类型 | 断言失败，名字为空 |
| `everyProtocolMethodResolves` | 14.3.1 Foundation、15.0 Foundation、15.4.1 CoreFoundation：每个协议方法的名字和类型都不为空；前提是镜像里确实还有指针格式的列表 | 15.0 崩溃；15.4.1 有 37 个方法读不出 |
| `stripProtocolConformanceDropsPointerListProtocolMembers` | 15.4.1 Foundation 上 NSString 开 `stripProtocolConformance` 后 `copyWithZone:`、`mutableCopyWithZone:` 被剔掉 | 两个成员都留着 |

这些用例读 `/Volumes/DyldSharedCaches/macOS/<版本>/` 下的归档 cache，卷不在就跳过，所以 **CI 上跑不到**。这不是测试放错了位置，而是 CI 上不存在能复现它的输入：runner 的 macOS 26 cache 和本机的 27 cache 都没有指针格式的协议方法列表，独立 Mach-O 文件又不经过 slide info，而几 GB 的 cache 不可能放进仓库。

加固的两处另有 `Tests/ObjCMetadataSourceTests/SharedRegionAddressGuardTests.swift`。它与 slide info 版本无关，读运行机器自己的 cache，**CI 上会跑**：

| 用例 | 钉住什么 | 去掉加固后 |
|---|---|---|
| `addressBelowSharedRegionHasNoFileLocation` | `fileHandleAndOffset(forAddress: 0x24B0EDE)`（即 15.0 上那个崩溃槽位的原值）返回 nil | 测试进程 signal 5 |
| `nullSlotResolvesToNothing` | 对一个空槽位（Foundation 里 `NSCoding` 的 `classMethods`）调用 `resolveRebase` 返回 nil | 测试进程 signal 5 |

## 验证数据

用同一个 MachOSwiftSection `next` 分别链接修复前后的本库，构建出两个 `swift-section` 做对照。

- 所有归档的 macOS arm64e cache（11.0.1 到 27.0，共 53 个版本）：`objc interface NSCoding -n Foundation` 都返回 0，且两个方法都正确。
- 修复前后逐字节一致：
  - 26.0、27.0 上 Foundation、AppKit、CoreFoundation、libobjc 的 `objc dump --emit-method-imp-addresses`。
  - 五个独立文件：Packages.app 的 x86_64 切片（部署目标 10.9，旧式重定位，指针格式的类方法列表，4048 个 IMP；用断点确认经过了新的 `pointerMethod`，且 imp 非零）、它的 arm64 切片、Xcode 26.6 的 DVTFoundation（chained fixups dylib）、TextEdit（arm64e，chained fixups 主可执行文件）、UI Browser 的 x86_64 切片。
- 14.3.1 上 Foundation 与 AppKit 的 dump：行数不变，`@protocol` / `@interface` / `@end` 等结构行逐行一致。变化只有两种：无名方法变成有名，以及 3 个原先「有名字但类型全是 `(Unknown)`」的方法补上了类型。
- 与 `ipsw dyld macho <cache> Foundation --objc` 的协议方法逐条对照（14.3.1 和 15.0）：全部一致。仅有的差异是 ipsw 不输出协议的可选类方法，以及下面那个既有的打印问题。

## 本轮不做的

- **末尾带空片段的 selector 少打一个参数。** `-[NSUserScriptTaskRunner executeScript:interpreter:arguments:standardInput:standardOutput:standardError:showingProgress::]` 的最后一段没有名字，渲染时被打成 7 个参数。原因是 `ObjCDeclarationRendering/ObjCDump+SemanticString.swift:422` 用 `name.split(separator: ":")` 拆 selector，而 `split` 默认丢掉空片段；swift-objc-dump 的 `ObjCMethodInfo.swift:111` 也是同样写法。这个问题与本次修复无关：在本来就能正确读取的 15.4.1 上，修复前的输出也一样。
- `extendedMethodTypes(in:)` 里沿用了原有的 `try!` 读取，没有动。
