# 代码审查的已裁决清单

代码审查报出、但判定为**不修**或**误报**的问题记在这里，连同理由和推翻条件。每次审查先对照这份清单：
已裁决且理由仍成立的直接跳过，不再重走一遍判断；新证据推翻了理由的，更新这里并重新裁决。

确认为真并已修复的问题不记在这里，它们的记录是修复提交和随之落地的回归测试。

## 不修

| 日期 | 问题 | 位置 | 理由 | 推翻条件 |
|---|---|---|---|---|
| 2026-10-27 | `diff --summary-only` 用 `print` 输出结论，`-o` 被忽略，CI 读文件时找不到结论 | `Sources/objc-section/Commands/DiffCommand.swift` | objc-section 命令行在 swift-section 带着 `objc` 子命令发版后整体删除（见 [0010](../Evolutions/0010-remove-objc-section-cli.md)）；swift-section 的 `objc diff` 另有实现，没有这行 `print` | 0010 被否决或长期搁置 |
| 2026-10-27 | `--architecture` 的帮助文字说不指定就用当前架构，遇到 fat 二进制却直接报错要求指定 | `Sources/objc-section/Models/MachOOptionGroup.swift` | 同上，命令行即将删除。这个选项组按注释与 swift-section 的同名选项组逐字一致，那边的帮助文字值得另行核对 | 同上 |
| 2026-10-27 | `MachOImageCache` 只按镜像序号做 key，不区分是哪一份缓存 | `Sources/MachOObjCSection/Extension/DyldCacheLoaded+.swift` | 它服务于 `DyldCacheLoaded`，即本进程已载入的那一份共享缓存，一个进程里只有一份，序号不会撞 | 出现在同一进程里读取多份已载入缓存的用法 |
| 2026-10-27 | 索引器按名字存类和分类，同名的后者覆盖前者，diff 的键碰撞诊断因此对类和分类永远不会触发 | `Sources/ObjCIndexing/ObjCInterfaceIndexer.swift` | 正常链接出来的镜像里没有同名项：同名类在链接时就撞符号；Swift 按模块给扩展的分类起名，但实测本仓库测试包里两个文件对 NSString 的扩展链接后只剩一个分类。0006 把「同一 image 里的同名类」当作碰撞的现实来源，这个前提不成立，诊断通道留给手工构造的输入。2026-10-29 补记：[image 组](../Evolutions/0016-objc-evolution-image-groups.md)里，两个 image 都有的同名类会触发这条诊断，这是它在单 image 之外的现实来源；单 image 的结论不变。同日再补：这条裁决只管类和分类这一级。成员级的碰撞在单 image 里是常态，链接器把分类并进类后，一个类里同一个属性常有好几份，按[同一容器里的重复成员按来源取舍](../Evolutions/draft-objc-duplicate-member-selection.md)处理，见实现说明「同一容器里的重复成员」 | `ObjCIndexingTests` 的 `sameNamedCategoriesAreAllIndexed` 失败，或找到一个确实含同名项的镜像 |
