# dyld cache 里相对方法名的起算点随版本而变

> 面向维护者的实现说明。没有对应提案：这是一次明显的 bug 修复。
>
> 记录 2026-10-28 修掉的一个问题：读 macOS 11.x 的 dyld shared cache 时，类和分类的方法名全部读错，
> `objc interface NSView` 打出 `+ (Class);`、`+ (id)('^H?;` 这样的乱码，`initWithFrame:` 一次都不出现。

## 规则

cache builder 把类和分类的方法列表改写成相对格式，并在列表头打上 `0x40000000`（dyld 叫它
`relativeMethodSelectorsAreDirectFlag`，本仓库是 `ObjCMethodListMask.usesSelectorOffsets`，列表种类
`.relativeDirectSelectors`）：条目的 `name` 不再指向选择器引用，而是直接指向选择器字符串。
**这个偏移从哪里算起，随 cache 的版本而变**：

| cache 的 objc 优化数据 | 系统 | 运行时怎么读 | `name` 从哪里算起 |
|---|---|---|---|
| `objc_opt_t` v15 及更早 | macOS 11、iOS 14 | objc4-818：`small().name.get()` | `name` 字段自身，与 `types`、`imp` 一样 |
| `objc_opt_t` v16，以及之后 cache header 里的 `objc_opts` | macOS 12、iOS 15 起 | objc4-838 起：`small().name.get(sharedCacheRelativeMethodBase())` | cache 选定的选择器基址 `@selector(🤯)`，位置记在 `relativeMethodSelectorBaseAddressOffset` |

读文件时按 objc 优化数据的**版本**判定（`MachOFile.relativeMethodNameBase`，取值是 `RelativeMethodNameBase`），
不按「记没记基址」判定：

- 有 `objc_opts`，或 `objc_opt_t` 是 v16：从基址算起。
- `objc_opt_t` 是 v12、v13、v15：从 `name` 字段自身算起。
- 读不到 objc 优化数据（缺了存放它的子 cache 文件、版本号不认识）：判定为未知，方法名留空，**不猜**。
  如果把「读不到」也当成「从字段算起」，新 cache 一次读取失败就会被当成 macOS 11 来解，又是一片乱码。

带 `0x20000000` 的列表（`.relativeDirectSelectorsAndTypes`）的 `types` 与 `name` 同一个起点。这个 flag
比 `objc_opt_t` v16 更新，只出现在记了基址的 cache 里。

进程内读（`MachOImage`）不看 objc 优化数据，按运行时的版本判定：`#available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)`
时用 `NSSelectorFromString("🤯")` 作基址，否则用 `name` 字段自己的地址。带这个 flag 的列表只会在共享 cache 里，
而进程里的共享 cache 就是本进程运行时读的那一份，所以运行时的版本就是答案。

## 证据

- dyld-832.7.1 与 dyld-852.2（macOS 11.0–11.7）的 `include/objc-shared-cache.h` 写的是 `VERSION = 15`；
  dyld-940（macOS 12）是 16，并新增了 `relativeMethodSelectorBaseAddressOffset`。
- dyld-852.2 的 `dyld3/shared-cache/ObjC2Abstraction.hpp`：flag 的注释是「the relative method lists name_offset
  field is an offset directly to the SEL」，`setName` 写入的是 `namePtr - &this->name`，即相对字段自身。
- objc4-818.2（macOS 11.0.1 与 11.5 带的都是它）的 `method_t::name()` 用 `small().name.get()`；objc4-838（macOS 12.0.1）
  改为 `small().name.get(sharedCacheRelativeMethodBase())`，后者返回 `@selector(🤯)`。
- 实测：11.0.1 cache 里 libobjc `__TEXT,__objc_opt_ro` 的前 4 字节是 `0f 00 00 00`，即 v15。13.0 的同一个 section
  是 v16，cache header 另有 `objc_opts`；macOS 13 起两份并存，读取时 `objc_opts` 优先。

旧代码在拿不到基址时写的是 `relativeMethodSelectorBaseAddressOffset ?? 0`：从主 cache 的起点去加 `name` 的偏移，
落到哪里就读哪里的字节。

`ipsw dyld macho <cache> AppKit --objc` 在 11.0.1 上同样把 NSView 的方法名读成乱码，`dyld_info -objc` 不打印 cache
里镜像的 ObjC 信息，所以这两个工具都不能拿来对照 11.x 的结果。

## 受影响的范围

- **macOS 11.0.1–11.7 的 cache 里，类和分类的全部方法名。** 修复前 11.0.1 的 AppKit 有 55,137 个方法声明，
  `objc dump` 输出里 47,461 行带不可打印字符；剩下看着正常的也只是空串或单个字符。MachOSwiftSection 对卷上
  52 个版本的 AppKit 做 objc snapshot，11.x 每个版本约 7.6 万个成员里有 4.8–4.9 万个 selector 带控制字符或
  U+FFFD，12.0.1 起为 0。
- 不受影响：`types` 和 `imp`（一直从各自的字段算起，所以 11.x 的返回类型一直是对的）；协议的方法列表（cache
  里是指针格式）；属性、ivar、父类、协议采纳；12.0.1 起的 cache；不在 cache 里的文件（它们的相对方法列表是
  `.relativeIndirect`，见 [相对方法列表的选择器引用也是指针槽位](RelativeMethodListSelectorReferences.md)）。
- 进程内读：宿主跑在 macOS 11 上时同样读错，那里 `NSSelectorFromString("🤯")` 注册的是一个 cache 里没有的新
  选择器。本仓库的部署目标是 macOS 10.15，这条路径能跑到 macOS 11 上。

## 来历

这段代码以前没有人修过，macOS 11 的读法从一开始就没有处理：

- `17bee7d`（2024-05-23，上游 p-x9）：进程内读用 `NSSelectorFromString("🤯")` 作基址。
- `b38a526`（2024-07-19，上游）：在 dyld cache 里读方法列表，写下 `relativeMethodSelectorBaseAddressOffset ?? 0`。
- `a93e179`（2025-10-12，上游）：基址改为从 `objc_opts` 或 `objc_opt_t` v16 取，更早的版本返回 nil，`?? 0` 照旧。

截至 2026-10-28，上游 main 仍是同样的写法。

## 测试怎么钉住这些

`Tests/ObjCMetadataSourceTests/DyldCacheRelativeMethodNameTests.swift` 读 11.0.1、12.0.1、13.0 三个 cache 的
AppKit，各对应一种格式（`objc_opt_t` v15、v16、`objc_opts`）：

| 用例 | 钉住什么 | 修复前 |
|---|---|---|
| `viewDeclaresInitWithFrame` | NSView 的 `initWithFrame:` 读得出，类型是 `@48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16` | 11.0.1 失败：找不到这个方法 |
| `everyMethodIsNamedBySelector` | 每个类和分类方法的名字都像一个 selector（ASCII 字母、数字、`_`、冒号，以及 `.cxx_destruct` 的点）；前提是镜像里确实有 `.relativeDirectSelectors` 列表 | 11.0.1 失败：53,053 个方法里 52,677 个不像 selector |

12.0.1 与 13.0 修复前后都通过，钉住新 cache 的行为没有因为改按版本判定而变化，也说明「像 selector」这条检查在
正确的数据上不误报。读 cache 的辅助类型挪到了同目录的 `ArchivedMacOSCache.swift`，与
`DyldCachePointerMethodListTests` 共用。

这些用例读 `/Volumes/DyldSharedCaches`，卷不在就跳过，**CI 上跑不到**，理由同
[dyld cache 里的指针槽位必须先解码](DyldCachePointerSlotDecoding.md) 的测试一节：runner 上只有它自己的 macOS 26
cache，几 GB 的旧 cache 放不进仓库。进程内读在 macOS 11 上的那一支，在 macOS 12 及以上的机器上走不到，没有测试。

## 验证数据

2026-10-28 在 JH's Mac Studio Ultra（macOS 27.2，Xcode 27.2）上，用同一份源码在修复前（`next` 的 `4efe0dd`）
与修复后各编一个 `objc-section` 做对照：

- `swift test --skip MachOObjCSectionTests`（CI 的跑法）：224 个测试、35 个 suite，原始退出码 0。跳过的 3 个
  与本次无关：卷上没有它们要的 14.3.1、15.4.1 cache 与 Xcode Service 样本。
- 11.0.1–11.7 共 8 个版本的 AppKit `dump`：修复后每个版本都没有一行带不可打印字符，`initWithFrame:(struct CGRect)`
  各出现 212 次（修复前 1 次，那一处来自协议），方法声明数与修复前相同（11.0.1 都是 55,137）。
- `objc diff` AppKit 11.7 → 12.0.1：修复前报 47,045 个成员删除、53,181 个新增，修复后是 1,164 与 1,347，
  且没有一行乱码。
- 12.0.1、13.0、15.0、26.0、27.2 的 AppKit 与 Foundation，`dump --emit-method-imp-addresses` 修复前后逐字节一致。

## 本轮不做的

- 进程内读只认本进程的共享 cache：把别的系统版本的 cache 映射进内存再经 `MachOImage` 读，基址与判定都会错。
  修复前也是这样（`NSSelectorFromString` 同样只认本进程），这次不动。
- 非 Darwin 平台的进程内读（`#if !canImport(ObjectiveC)` 那一支）沿用 `DyldCacheLoaded.relativeMethodSelectorBaseAddress`，
  拿不到基址就 `fatalError`。那里没有共享 cache，这一支走不到，没动。
