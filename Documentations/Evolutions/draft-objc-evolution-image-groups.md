# Draft - ObjC 演进按 image 组比较，并报出搬家

- **状态**: Accepted
- **创建日期**: 2026-10-29
- **最后更新**: 2026-10-29
- **实现分支**: `feature/objc-evolution-image-groups`
- **关联**: MachOSwiftSection 同步做 Swift 一侧（SwiftDiffing / SwiftInterface）和两库的集成测试，模型与报告文案两边一致；
  那边的提案落地后在这里补链接

## 摘要

现在演进的每个版本只读一个 image。AppKit 的声明搬到 UIFoundation、CollectionViewCore 之后，单 image 演进把搬走的报成
removed、把从别的库搬来的报成 added，其实它们没有消失。本案让演进把每个版本的一组 image 当作同一个 API 面来比：搬家不再
被误报成删除或新增，而是作为一种新记录报出来，不影响兼容性判定。`ObjCAPIEvolutionBuilder` 与
`ObjCEvolutionInterfaceBuilder` 各加一个按 image 组的入口；单 image 的用法、输出与 JSON 逐字节不变。

## 方案

### 入口（`ObjCDiffing`）

```swift
public struct ObjCAPIImageSnapshot: Sendable, Codable, Equatable {
    public let imageName: String
    public let snapshot: ObjCAPISnapshot
}

extension ObjCAPIEvolutionBuilder {
    public func evolution(ofImageGroups imageGroups: [[ObjCAPIImageSnapshot]], versions: [ObjCAPIVersionDescriptor]) throws -> ObjCAPIEvolution
}

extension ObjCAPIVersionDescriptor {
    public let imageNames: [String]?   // set by the builder from the group; nil in a single-image evolution
}
```

- 每个版本一个有序列表，主 image 在前。image 名由调用方给，不从 provenance 的 `binaryPath` 推（那里写的是
  `<cache 路径> (AppKit)`）。哪些 image 在场由调用方决定：组里的 image 可以中途加入。
- 空列表就是这个版本什么都没有。不新增错误 case，少于两个版本、数量对不上照旧报。
- 单 image 快照的格式不变，`ObjCAPISnapshotDocument` 不升 `formatVersion`。

### 一个版本里的几个 image 怎么合并

- **class**：按组顺序全部列入。同名的只比较第一个 image 的那份，其余的照现有规则记成 key collision。
- **category**：unique name 相同的合成一个容器（运行时它们都挂到同一个类上），成员按组顺序拼接。同一个 selector 在两个
  image 里各有一份时，记成成员级的 key collision。
- **protocol**：每个引用它的 image 都在 `__objc_protolist` 里带一份 `protocol_t`。dyld 的 cache builder 只把各处引用改指向
  一份规范副本，`__objc_protolist` 仍指向各 image 自己的副本（`NewSharedCacheBuilder.cpp` 的注释原文：
  "We do NOT update __objc_protolist"）。内容相同的副本去重，不算冲突；内容不同的取组里第一份来比较，其余的记成
  key collision。protocol 没有「所在的 image」，不记搬家。
- **key collision 警告注明 image**：`ObjCAPIKeyCollision` 加 `droppedImageNames: [String]?`，与 `droppedSignatures` 一一对应，
  报告写成 `dropped: NSFoo (UIFoundation)`。单 image 时为 nil。

### 搬家记录

```swift
public struct ObjCImageMove: Sendable, Codable, Equatable {
    public let versionIndex: Int
    public let oldImageNames: [String]
    public let newImageNames: [String]
    public let signature: String?   // members only: the new side's rendering
}

// ObjCContainerLineage and ObjCMemberLineage
public let imageMoves: [ObjCImageMove]?   // nil when there is none
```

- 只有当声明在一次跳变的两侧都在场时才比较。某一侧的 image 集合，是该版本里含有它的所有 image，按组顺序排（通常只有一个，
  重复时有多个）。
- 容器：两侧集合不同就记。成员：两侧集合不同，**而且**（旧集合, 新集合）与所属容器的不同，才记。整个类搬走时，不给每个
  方法都记一遍；category 拆到两个 image 之后，换了 image 的方法单独记，留在原 image 的方法不记。
- 只有搬家、没有其他事件的 lineage 也要列出来（现在只列有事件的）。
- 搬家不影响兼容性判定，`hasBreakingChange` 不变。按旧 install name 绑定的符号还能不能找到，取决于旧 image 有没有
  re-export 新 image，快照里没有这个事实，所以只报不判。
- 事件本身仍与「把两侧合并后的快照交给 `ObjCAPIDiffer`」的结果一致。
- 实现上，成员的 image 归属只为由两个以上 image 拼成的容器单独保存，其余成员沿用容器的归属，免得 51 个版本的
  AppKit 再多占一倍内存。

### 报告（`ObjCAPIEvolutionReporter`，文案与 Swift 一侧相同）

```
ObjC API evolution across 3 versions: 13.0 → 14.0 → 15.0
Image group:
  [●●●] AppKit
  [●●●] UIFoundation
  [○●●] CollectionViewCore

Transitions:
  13.0 → 14.0: 1 added · 3 moved · additive
  14.0 → 15.0: no changes

Classes:
  [○●●] NSBar
      + added in 14.0
  [●●●] NSFoo
      > moved in 14.0: AppKit → CollectionViewCore

Categories:
  [●●●] NSString(NSFooDrawing)
      > moved in 14.0: AppKit → AppKit + UIFoundation
      [●●●] - (void)drawAtPoint:(CGPoint)point;
          > moved in 14.0: AppKit → UIFoundation
```

- 「Image group」紧跟在头部那行下面（`summary` 也有），一个 image 一行，按它在轴上首次出现的顺序排（先看旧版本，
  同一版本内按组顺序）。
- 事件与搬家按 `versionIndex` 合在一起排；同一个版本里，事件在前、搬家在后。image 集合用 ` + ` 连接。
- 跳变摘要在 added / removed / modified 之后加一项 `N moved`；只有搬家的那一步也照常给 verdict 词。
- 只有搬家的成员，签名取自搬家记录的 `signature`。

### 合并头文件（`ObjCInterface`）

```swift
public struct ObjCEvolutionInterfaceImage<MachO: ObjCMetadataSource> {
    public init(imageName: String, indexer: ObjCInterfaceIndexer<MachO>, machO: MachO)
}

extension ObjCEvolutionInterfaceBuilder {
    public mutating func addVersion<MachO: ObjCMetadataSource>(images: [ObjCEvolutionInterfaceImage<MachO>], version: ObjCAPIVersionDescriptor)
}
```

- 一个版本的 image 一次交齐，按组顺序、主 image 在前，返回后不再引用。版本之间仍然可以加完一版就释放。
- 渲染照上面的合并规则：class、protocol 取被比较的那一份，category 的成员取第一个有它的 image；C struct 与 union 在一个版本
  里取第一个定义它的 image。
- 有一个版本按 image 组加入时，演进由 `evolution(ofImageGroups:versions:)` 计算。同一个 builder 不能混用两种
  `addVersion`，混用时 `build()` 抛一个新的错误类型（不给 `ObjCAPIEvolutionError` 加 case）。
- 搬家写进标注：`// [●●●] moved in 14.0: AppKit → UIFoundation`，与同一声明的其他事件用 ` · ` 连接。只有搬家的声明也带标注。
  文件开头的图例在「Bitmap positions」那行之后加上 Image group 几行，格式与报告相同。
- 可用性宏只看在场位图，搬家不影响它。

### 不做

- 两个版本的 `ObjCAPIDiffer.diff` 不加 image 组入口。
- 本库的 `objc-section` 命令行不接这个功能（它按 0010 等待移除）；要上命令行，在 `swift-section objc` 那边接。
- 不判断 re-export，不给 protocol 记搬家。

### 测试与文档

- `ObjCDiffingTests`：用手搭的快照覆盖三条合并规则、搬家的各条规则、只有搬家的 lineage、报告文案；另有一条测试固定
  单 image 演进的 JSON，在改代码之前写好并跑通，确保改完之后逐字节不变。
- `ObjCInterfaceTests`：把进程里的 Foundation 以不同的 image 名放进不同版本，造出搬家与 protocol 去重。
- 本机有 15.5、26.x、27.0 的归档 cache，先探一下其中有没有真实的搬家，有就加一组归档测试；11.0.1 到 15.x 的真实搬家由
  MachOSwiftSection 的集成测试覆盖（那些 cache 在 Ultra 上）。
- 更新使用指南的库调用方一节、`ObjCAPIDiffDesignAndLimitations.md`、术语表（image 组、搬家）和 README。

## 落地步骤

每一步单独构建通过、相关测试通过后提交，文档随所在的那一步一起提交。

- [ ] 1. 固定单 image 演进的 JSON：在改代码之前写好测试并跑通。
- [ ] 2. `ObjCDiffing` 的模型与计算：`ObjCAPIImageSnapshot`、`evolution(ofImageGroups:versions:)`、`imageNames`、
  合并规则、`ObjCImageMove` 与 `imageMoves`、`droppedImageNames`；单元测试；设计说明与术语表。
- [ ] 3. 报告：Image group、`> moved` 行、`N moved`、collision 警告里的 image；报告测试。
- [ ] 4. 合并头文件：`ObjCEvolutionInterfaceImage`、`addVersion(images:version:)`、混用报错、搬家标注与图例；测试；
  使用指南与 README。
- [ ] 5. 探本机归档 cache 里有没有真实的搬家，有就加归档测试，结论写进本提案。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-29 | Created as Draft | MachOSwiftSection 的会话按用户的安排转来这个需求，并给出两边共用的模型与报告文案 |
| 2026-10-29 | 沿用 MachOSwiftSection 提出的模型、类型名与文案 | 两边的报告读起来一致，集成测试可以共用一个基类 |
| 2026-10-29 | 成员搬家多加一个条件：两侧集合必须不同 | 只比「与容器不同」的话，category 拆到两个 image 后，留在原 image 的方法会被记成 `AppKit → AppKit` |
| 2026-10-29 | protocol 去重规则经 dyld 源码核实 | cache builder 不改 `__objc_protolist`，每个 image 都保留自己的副本 |
| 2026-10-29 | 接口一次收齐一个版本的全部 image | 一次调用加完一个版本，不留半开的状态；代价是同一版本的几个索引器要同时在内存里 |
| 2026-10-29 | key collision 警告注明 image | 不注明的话，读者看不出被丢的那份在哪个 image 里 |
| 2026-10-29 | 补上落地步骤，状态改为 Accepted | 用户批准，开始实现 |
