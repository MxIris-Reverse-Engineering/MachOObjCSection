# 术语表

MachOObjCSection 专有名词与约定用法。

跨项目通用的术语收录在全局术语表（iCloud Global 镜像的 `Documentations/Glossary.md`），
本表只收本项目特有的，不重复登记。与 diffing 相关的三条通用术语在全局表：
**baseline snapshot（基线快照）**、**identity key 与 payload key（身份键与载荷键）**、
**lineage（生命线）**。

提案或专题文章引入新术语时，**同批次**登记进本表。

## 术语

按英文名 / 标识符字母序排列。

### key namespace（键命名空间）

`ObjCAPIKey` 的前缀约定：`class:` / `protocol:` / `category:`（容器）、
`method:-` / `method:+`（实例 / 类方法 + selector）、`property:-` / `property:+`、
`ivar:`、`adopts:`（直接协议采纳）、`superclass`（伪成员）。前缀保证不同种类的成员
永不碰撞，同时它就是 baseline 的事实持久化格式——**任何变更必须 bump
`ObjCAPISnapshotDocument.currentFormatVersion`**。完整格局表见
[实现说明](Internal/ObjCAPIDiffDesignAndLimitations.md)。

- **主要出现在**：`Sources/ObjCDiffing/ObjCAPIKey.swift`、`ObjCMemberRecord.swift`
- **延伸阅读**：[提案 0006](Evolutions/0006-objc-api-diff-and-evolution.md)

### ObjCAPIModule 与 ObjCAPISnapshot 之别

同一份声明数据的两种形态，不可混用：**module** 是 live 输入（持有 ObjCDump 的
`*Info` 值，含递归协议树，不可序列化），**snapshot** 是冻结产物（只剩键与签名的纯值，
`Codable`，即 baseline 的内容）。`ObjCAPIDiffer.snapshot(of:)` 是两者之间唯一的桥，
也是全模块唯一接触模型知识的地方。

- **主要出现在**：`Sources/ObjCDiffing/ObjCAPIModule.swift`、`ObjCAPISnapshot.swift`

### pseudo-member（伪成员）

不是真实成员、但被投影成成员记录参与 diff 的容器属性：目前只有 `superclass` 一个。
这样换父类报「类被 modified（old → new 并列）」而不是「整类 removed + added」，
保住「其余成员并未变化」的信息。

- **主要出现在**：`ObjCMemberRecord.makeSuperclass(superclassName:)`

### uniqueName

category 的索引与显示身份：`ClassName(CategoryName)`（如 `NSString(MyAdditions)`）。
category 自己的 `name` 不含目标类，同名 category 可以挂在不同类上，所以一切按名索引
的地方（索引器、diff 的容器键）用的都是 uniqueName。定义在 `ObjCMetadataSource`
（0006 起，从渲染层下沉），一行拼接，两处漂移的风险靠单一定义消除。

- **主要出现在**：`Sources/ObjCMetadataSource/ObjCDump+ModelDerivations.swift`
