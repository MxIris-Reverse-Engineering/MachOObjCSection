# 指向本镜像导出符号的 bind 槽位

> 面向维护者的实现说明。没有对应提案：这是一次明显的 bug 修复。
>
> 记录 2026-10-08 修掉的一个读取缺口：独立 Mach-O 文件里，一个指针槽位用 bind 指向**本镜像自己导出的符号**时（下文叫 self-bind），读取器读不出它指向的东西。iOS 模拟器 runtime 的框架大量是这种槽位，所以在这些文件上大约三分之一的类读不出来。

## 规则

独立文件里的每一个指针槽位，都经 `MachOFile.resolveRebase(_:)` 解码。它按槽位的种类给出答案：

| 槽位 | `resolveRebase` 的答案 |
|---|---|
| rebase | 目标位置 |
| 指向本镜像导出符号的 bind（`BIND_SPECIAL_DYLIB_SELF`） | 那个导出符号的位置加上 addend，由 MachOKitExtensions 的 `resolveSelfBind(fileOffset:)` 查本镜像的导出表得到 |
| 指向别的镜像的 bind | `nil`。要名字时用 `resolveBind(field, in:)` |
| 空槽 | `nil` |

因此读一个可能是 bind 的字段时，**直接调 `resolveRebase`，不要先做别的判断**：

- 不要先判 `isBind` 再返回 `nil`：self-bind 也是 bind，这样会把本镜像里的目标一起丢掉。
- 不要先判槽位原值是否大于 0：用 `LC_DYLD_INFO(_ONLY)` 的旧文件，bind 槽里存的是 addend，通常就是 0，靠原值分不出空槽和 bind。`resolveRebase` 自己会把空槽答成 `nil`。

bind 的查询（`resolveBind`、`isBind`、`resolveSelfBind`）都来自 MachOKitExtensions，chained fixups 与旧的 bind 操作码两种格式都读。本库原来自己的 `isBind` 和 `chainedFixupBindSymbolName` 只认 chained fixups，已经删掉。

## 为什么会有 self-bind

用 `-interposable` 链接的 dylib，访问自己导出的符号也像访问别的库一样走 bind，好让别的镜像能替换（interpose）它。dyld 加载时在本镜像的导出表里找到这个符号，把地址填进去。`dyld_info -fixups` 把它显示成 `bind <this-image>/_OBJC_CLASS_$_UIDocument`。

Apple 的模拟器 runtime 框架就是这样链接的。导出的 ObjC 类会在下面几处留下 self-bind，没导出的类仍是 rebase：

- `__objc_classlist` 里这个类的条目；
- 类结构里的 `isa`（指向自己的 metaclass）与 `superclass`（父类也在本镜像、也导出时）；
- category 的 `cls`（扩展的是本镜像导出的类时）；
- ivar 的 offset 指针（`_OBJC_IVAR_$_…`）；
- `__objc_superrefs` 与 `__got`，本库不读。

各版本模拟器 UIKitCore 的 classlist 里 self-bind 的数量：

| 模拟器 runtime | classlist 条目 | 其中 self-bind |
|---|---|---|
| iOS 16.4 | 4,156 | 1,216 |
| iOS 17.5 | 4,575 | 1,464 |
| iOS 18.5 | 5,017 | 1,586 |
| iOS 26.5 | 5,546 | 1,728 |

iOS 27 起模拟器框架改放进 dyld cache，cache builder 已经把这些 bind 解掉，所以不受影响。dyld cache 里的镜像一律不受影响。

## 修复前的症状

- **类列表**：self-bind 条目要么被丢掉，要么按 bind 的原始位读到别处。iOS 18.5 的 UIKitCore 上有 791 个条目读不出 `class_ro_t`，624 个被误读成 metaclass，`UIView`、`UIResponder`、`UIDocument` 都在里面。
- **metaclass / superclass / category 的类**：读取函数见到 bind 就直接返回 `nil`，所以本镜像里的父类也走不过去。
- **ivar 的 offset**：导出类的 ivar 偏移读不出来。
- **只在旧格式文件上**：bind 槽的原值 0 被当成文件偏移 0，读出来的是 Mach-O header；本库的 bind 名字查询又只认 chained fixups，所以连 `NSObject` 这种别的镜像里的父类名字也拿不到。

对下游的影响：MachOSwiftSection 用 `--dependency-search-path <RuntimeRoot>` 读 iOS 18.5 模拟器的 SwiftUI 时，静态布局要读 `UIDocument` 的 instance size 才能排 `PlatformDocument` 的字段，读不到就把字段偏移写成 `unknown (Objective-C ancestor UIDocument unresolved)`，整份 dump 里有 392 处。`UIDocument` 的 `class_ro_t.instanceSize` 实际是 `0xc4`，按 8 字节对齐后，`PlatformDocument` 的第一个字段在 `0xc8`。

## 改动

- **MachOKitExtensions**：新增 `MachOFile.resolveSelfBind(fileOffset:)`。旧格式的 bind 索引原来只记符号名，现在也记 library ordinal 与 addend（weak bind 不记 ordinal，按名字由 dyld 在任意镜像里找，不算 self-bind）。导出表经 `cached.exportTrie` 缓存：MachOKit 每次读 `exportTrie` 都会从文件重新读整张表，而一个框架要查上千次。
- **本库**：`MachOFile.resolveRebase(_:)` 按上面的表处理四种槽位；类与 category 的 `_readClass`、`_readStubClass`、`_readClassName`，以及 ivar 的 `offset(in:)`，去掉了先判 `isBind` 与先判原值的写法；`_FixupResolvable.resolveBind(fileOffset:in:)` 与 `isBind(fileOffset:in:)` 改为转发 MachOKitExtensions 的同名查询。

## 验证

- `Tests/ObjCMetadataSourceTests/SelfBindPointerSlotTests.swift`：测试时用 `-Wl,-interposable` 编一个小 dylib，chained fixups 与旧格式各一份，覆盖类列表、instance size、superclass、metaclass、ivar offset、category 的类、旧格式里别的镜像的父类名，共 7 个测试 14 例。修复前全红，修复后全绿；期望值来自源码与 `otool -ov`。同一文件里另有一个需要本机有 iOS 18.5 模拟器 runtime 的测试：`UIDocument` 的 instance size 是 `0xc4`（用 xxd 在它的 `data` 指针目标处读出），没有时跳过。
- MachOKitExtensions 的 `SelfBindResolutionTests`：C 写的小 dylib，self-bind 带 addend 4、指向别的镜像的 bind、rebase 三种槽位，两种格式各一份。
- 本库全量（`--skip MachOObjCSectionTests`，与 CI 相同）与 MachOKitExtensions 全量都通过。

## 边界

- 只认导出表里的符号。被 re-export 的符号没有偏移，答 `nil`。
- weak bind 不当作 self-bind。
