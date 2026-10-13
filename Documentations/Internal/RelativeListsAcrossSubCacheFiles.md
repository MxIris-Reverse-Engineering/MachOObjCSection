# relative list of lists 的列表不一定和镜像 header 在同一个文件

> 面向维护者的实现说明。没有对应提案：这是一次明显的 bug 修复。
>
> 记录 2026-10-13 修掉的一个读取缺口：从 macOS 26.4 起的 dyld cache 文件里离线读类时，被别的镜像加过 category 的类读不出实例属性和协议列表，元类也挂了列表时类属性也一起丢。修法移植自上游 p-x9/MachOObjCSection 的 `10b3dd5`。

## 规则

relative list of lists 的每一项都是「镜像编号 + 列表偏移」。按这个偏移（相对 cache 起点）找列表时，要在**整个 cache 的所有文件**里找，用 MachOKitExtensions 的 `MachOFile.cacheAndFileOffset(fromStart:)`。不要假定列表和这一项所属镜像的 header 在同一个文件里。

## 为什么会有 relative list of lists，为什么列表会在别的文件里

cache builder 会把别的镜像给一个类写的 category 预先挂到类上。这时类的 `baseMethods` / `baseProperties` / `baseProtocols` 指针最低位是 1，指向一张列表的列表，每项是 `(imageIndex, listOffset)`。读取时按本镜像的 objc image index 挑出自己那一项（`ObjCDump.swift` 里的 `resolvedXxxList(in:imageIndex:)`）。NSView 在 macOS 26.7 上挂了 82 张方法表、28 张属性表、13 张协议表。

cache 文件的布局在 macOS 26.4 变了：

- 15.0 到 26.2 只有主文件和 `.01` 两个文件，一个镜像的代码段和数据段在同一个文件里。
- 26.4 起拆成 13 个文件（27.0 是 80 个），每组镜像的数据单独放进 `.dylddata` 文件。header 和方法表（代码段里的 `__objc_methlist`）在一个文件，属性表和协议表（数据段）在另一个文件。

AppKit 里 NSView 自己的那几张表在哪个文件，以及离线读出的实例属性数（`objc-section interface NSView --dyld-shared-cache -n AppKit`，读 `/Volumes/DyldSharedCaches/macOS` 下的存档 cache）：

| macOS | cache 文件数 | header | 自己的属性表、协议表 | 修复前 | 修复后 |
|---|---|---|---|---|---|
| 15.0 | 2 | 主文件 | 主文件 | 290 | 290 |
| 26.2 | 2 | 主文件 | 主文件 | 355 | 355 |
| 26.4 | 13 | `.01` | `.02.dylddata` | 0 | 355 |
| 26.7 | 13 | `.01` | `.02.dylddata` | 0 | 355 |
| 27.0 | 80 | `.01` | `.25.dylddata` | 0 | 371 |

26.5.2 与 26.6.2 同 26.4。方法表在所有版本里都和 header 在同一个文件。

## 修复前的症状

`MachOFile.relativeListLocation(for:)` 只在 `_machO(at:)` 找到 header 的那个文件里换算偏移。列表在另一个文件时它返回 `nil`，上层当作「这张表不存在」，不报错：

- **实例属性和协议列表整段为空**：`@interface NSView : NSResponder` 后面没有 `<…>`，也没有一条实例 `@property`。
- **类属性**：元类也挂了列表时一起丢，比如 NSView 的 9 个类属性；NSWindow 的类属性就没丢。
- **方法不受影响**：方法表和 header 在同一个文件。

macOS 26.7 上逐个类对比文件模式与镜像模式：AppKit 2,573 个类里 51 个读不到实例属性、22 个读不到协议；Foundation 872 个类里 45 个与 20 个。受影响的恰是最常用的类：NSView（355 → 0）、NSWindow（334 → 0）、NSTableView、NSTextField、NSButton、NSImage、NSColor、NSString、NSError、NSBundle。随手抽查别的类大多正常，所以不容易发现。

镜像模式不受影响：`list(in: MachOImage, for:)` 直接按进程内地址读，不需要找文件。下游的 swift-section 0.22.0 的 `objc` 子命令受影响；RuntimeViewer 走镜像模式，不受影响。

## 改动

`relativeListLocation(for:)` 改用 `_machO(at:)` 找到的那个 `MachOFile` 的 `cacheAndFileOffset(fromStart:)` 换算偏移。它依次查镜像所在的文件、主文件，最后查 MachOKitExtensions 的子 cache 表。

`_machO(at:)` 每次都新建一个 `MachOFile`，而子 cache 表挂在 `MachOFile` 实例上，所以每张跨文件的列表都要新建一张子 cache 表、打开一次它所在的文件。这些都随这个 `MachOFile` 一起释放，不会像 [DyldCacheSubCacheReadTests](../../Tests/ObjCMetadataSourceTests/DyldCacheSubCacheReadTests.swift) 记录的那次一样堆积映射。实测开销很小（见「验证」），所以没有改成复用调用方那个 `MachOFile` 的表。

## 与上游的关系

- 移植自上游 `10b3dd5`（Fix relative list cache resolution，2026-08-06，随 PR #37 合入上游 main）。
- 同一个 PR 的 `ff936fa`（Preserve all relative list entries）没有移植：它在同一镜像有多张列表时全部读入，而本库只取第一张。macOS 26.7 上本机已加载的 516 个 cache 镜像、26,296 个类里，只有 UniformTypeIdentifiers 的 `_UTCoreType` 同一镜像有两张方法表。同一镜像里的 category 一般在链接时就被 `ld` 合进了类本身（`-no_objc_category_merging` 才关掉），所以这种情况很少。

## 验证

- `Tests/ObjCMetadataSourceTests/RelativeListAcrossSubCacheTests.swift`：在运行中系统的 cache 里各找一个 Foundation 类，它自己的属性表（另一例是协议表）不在 header 所在的文件里，比较文件模式与镜像模式读出的属性名和协议名。修复前两例都红（文件模式为空），修复后都绿。cache 没有这种布局时（macOS 26.2 及更早）整组跳过。
- 全量（`--skip MachOObjCSectionTests`，与 CI 相同）：23 个套件 171 个测试全部通过。
- macOS 26.7 上 release 版 `objc-section dump --uses-system-dyld-shared-cache -n AppKit`：
  - 修复前 11,006 条 `@property`、696 个带协议列表的 `@interface`；修复后 13,581 条与 718 个。
  - 按行的多重集合比较：修复前独有的 22 行全是不带协议列表的 `@interface`；修复后多出 2,575 条属性（其中 135 条类属性）、22 行带协议列表的 `@interface` 和 61 个空行，其余一行不变。
  - 各跑 3 次：修复前 7.6–8.3 秒，修复后 7.8–8.4 秒；峰值内存都在 87–93 MB。
- 上表各版本存档 cache 的修复前后数字，都用同一份 `objc-section` 源码（修复前为 0.8.110）分别编出的 release 版测得。

## 边界

- 只解决「列表在哪个文件里」。同一镜像有多张列表时仍只取第一张，见上一节。
- 读出的属性表照原样保留同名项（`ld` 合并 category 时不去重），本库不处理。
