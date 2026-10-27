# 相对方法列表的选择器引用也是指针槽位

> 面向维护者的实现说明。没有对应提案：这是一次明显的 bug 修复。
>
> 记录 2026-10-27 修掉的一个问题：文件模式读 32 位镜像（watchOS 的 arm64_32）时，相对方法列表里的方法名全部读成空，
> 渲染出 `- (int);`、`+ (id);` 这样没有名字的声明。

## 规则

磁盘上的二进制里，相对方法列表（relative method list，条目里存的是相对偏移而不是指针）的 `name` 字段不是字符串的偏移，
而是到一个**选择器引用**的偏移：`__objc_selrefs` 里一个指针宽度的槽位，运行时由 dyld 修正成选择器的地址。
这个槽位和任何指针槽位一样，**要按指针宽度读出原值，再经 `MachOFile.resolveRebase(_:)` 解码**，不能把原值直接当地址用。
写法与指针格式的方法列表一致：用条目相对 Mach-O header 的偏移加上 `name` 的相对偏移算出槽位的 `fieldOffset`，
构造 `UnresolvedValue(fieldOffset:value:)`，交给 `resolveString(in:slot:)`。

dyld shared cache 里的相对方法列表不受影响：cache 里的 `name` 是相对选择器基址的偏移（`relativeDirectSelectors`），没有引用槽位。

## 为什么原值不是地址

用链式修复（chained fixups，`LC_DYLD_CHAINED_FIXUPS`）链接的二进制里，槽位存的是修复记录本身：目标地址之外，
还编码着到同一页里下一个修复槽位的距离。以本仓库的测试样本为例，同一组选择器引用的原值是：

| 样本 | 槽位原值 | 目标 | 编码格式 |
|---|---|---|---|
| arm64，macOS 13 | `0x0010_0000_0000_0919` | `0x919` | `DYLD_CHAINED_PTR_64_OFFSET`，`next` 在第 51–62 位 |
| arm64_32，watchOS 9 | `0x0400_41B1` | `0x41B1` | `DYLD_CHAINED_PTR_32`，`next` 在第 26–30 位 |

旧代码按 8 字节读出原值，交给 `fileHandleAndOffset(forAddress:)`。64 位能读对是碰巧：`fileOffset(of:)` 先按平台去掉
指针标签位（macOS 掩码 `0x7FFF_FFFF_FFFF`），正好把 `next` 一并抹掉；剩下的目标是相对镜像起点的偏移而不是地址，
又碰巧被「低于 `__TEXT` 的地址按文件偏移处理」那条规则接住。32 位两处都不碰巧：arm64_32 的掩码是 `0x7FFF_FFFF`，
抹不掉第 26–30 位的 `next`，`0x0400_41B1` 落在所有段之外，换算失败，方法名就成了空串。按 8 字节读本身倒不是原因：
多读进来的下一个槽位在高 32 位，同样被掩码去掉了。

## 来历

- 读法最初来自上游（p-x9），`3f7ed3f`（2026-04-25）重写这段时保留了「按 8 字节读原值、当地址用」。
- `0760de8`（2026-10-03）把指针格式方法列表的槽位改为经 `resolveRebase` 解码（见
  [dyld cache 里的指针槽位必须先解码](DyldCachePointerSlotDecoding.md)），没有覆盖相对列表的选择器引用。
- 2026-10-27 的代码审查把它报为「32 位按 8 字节读」，实测发现真正的原因是没有解码链式修复，读取宽度只是表象。

## 测试怎么钉住这些

`Tests/ObjCMetadataSourceTests/Fixtures/` 下放着两个用同一份 ObjC 源码编出的小 dylib，一个 arm64_32、一个 arm64，
编译命令写在各自的 `.m` 文件开头。`RelativeMethodListSelectorTests` 对两个样本读同一组类方法与实例方法名：
arm64_32 样本修复前全部为空；arm64 样本修复前后都通过，钉住 64 位的行为没有因为改走解码而变化。
