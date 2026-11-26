# `swiftClassFlags` 留在类布局里

> 面向维护者的实现说明。没有对应提案：这是合并上游 p-x9/MachOObjCSection 0.10.0（2026-11-26）时定下的兼容处理。
>
> 上游在 0.9.0 的 `fa97301` 把 `swiftClassFlags` 从类布局里删了，本 fork 把它留着，因为 MachOSwiftSection 在用。

## 规则

- `ObjCClass64.Layout`、`ObjCClass32.Layout` 与 `_ObjCClassLayoutProtocol` 保留 `swiftClassFlags` 字段，位置紧跟在 `class_t` 的五个指针后面。
- 上游新增的 `ObjCClassProtocol.swiftClassFlags(in:)`（`MachOFile` 与 `MachOImage` 两个重载）照样提供，但直接取已读出的 `layout.swiftClassFlags`，Swift 类返回它，其余返回 `nil`。
- 以后合并上游时，`fa97301` 在这三个文件里的删除不要接。`Tests/ObjCMetadataSourceTests/SwiftClassFlagsLayoutTests.swift` 用到这个字段，字段被删就编不过。

## 上游为什么删

`swiftClassFlags` 是 `objc_class` 在 `class_t` 之后额外放的 4 字节，只有 Swift 类有。字段写在 `Layout` 里，读任何类的布局都按 `MemoryLayout<Layout>.size` 读：64 位读 44 字节，而 `class_t` 只有 40 字节；32 位是 24 对 20。Objective-C 类的这 4 字节其实是紧随其后的别的数据。上游的理由是：类正好在文件末尾时，多读的部分会越界。它把字段移出 `Layout`，改由 `swiftClassFlags(in:)` 从 `offset + MemoryLayout<Layout>.size` 另读 4 字节。

## 为什么本 fork 不跟

MachOSwiftSection 的 `Sources/Analysis/SwiftObjCInterop/ClassHierarchyDumper.swift` 给 `ObjCClass64.Layout` 补了 `Equatable`，在里面比较 `swiftClassFlags`，`main` 与 `next` 两条分支都有。删掉这个字段，它就编不过。

MachOSwiftSection 用本地依赖构建（`USING_LOCAL_DEPENDENCIES=1`）时，读的就是本库的检出。所以本库一合并，它马上受影响，等不到它去改版本约束的时候。

## 代价

读类的布局时，行为与合并前一样：每个类都多读 4 字节。

- Objective-C 类多读的 4 字节没有人去解释。只有类正好在文件或映射的末尾时，多读才会失败。类在 `__objc_data` 里，后面总还有别的数据，目前没见过这种情况。
- `MemoryLayout<Layout>.size` 里含这个字段，所以它不是字段的起点。上游 `swiftClassFlags(in:)` 的写法（从 `offset + MemoryLayout<Layout>.size` 读）在本 fork 会读错位置，所以改成了直接取字段。

## 什么时候可以跟上游删

MachOSwiftSection 不再读 `layout.swiftClassFlags`（改用 `swiftClassFlags(in:)`，或比较时不带这个字段）之后，就可以接上游的删除：三个文件回到上游写法，`swiftClassFlags(in:)` 换回上游的实现，`SwiftClassFlagsLayoutTests` 里检查字段位置的那条测试删掉。
