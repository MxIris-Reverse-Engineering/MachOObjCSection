# objc-section 使用指南

- **对应提案**: [0002](../Evolutions/0002-objc-machofile-genericization-and-cli.md)（dump / interface）、[0006](../Evolutions/0006-objc-api-diff-and-evolution.md)（snapshot / diff / evolution）、[0007](../Evolutions/0007-dump-sections-spelling-and-empty-diagnostics.md)（`--sections` 写法与空结果诊断）、[0009](../Evolutions/0009-objc-section-release-automation.md)（预编译二进制）、[0014](../Evolutions/0014-host-supplied-classes.md)（由宿主补充的类，库调用方）、[0015](../Evolutions/0015-objc-evolution-interface.md)（合并多个版本、带演进标注的头文件，库调用方）、[0016](../Evolutions/0016-objc-evolution-image-groups.md)（几个 image 当作一个 API 面，库调用方）
- **最后更新**: 2026-10-29

这份文档写给两类人：用 `objc-section` 命令行导出 ObjC 头的人，以及直接调用
`ObjCInterfaceIndexer` / `ObjCInterfaceBuilder` 处理磁盘上二进制的人。

**从 API 签名和 `--help` 里看不出来、但踩了就出错的东西全在「必须知道的六件事」一节**，
其余部分是常规用法说明。

## 它能做什么

在 0002 之前，索引层只接受 `MachOImage` —— 也就是**已经加载进当前进程的镜像**。这意味着
只能分析本机架构、本平台、且能成功 `dlopen` 的东西。0002 之后，同一套索引与渲染代码也接受
`MachOFile`，于是：

- 在 x86_64 机器上分析 arm64e 的二进制；
- 在 macOS 上分析 iOS / watchOS 的二进制；
- 分析签名不匹配、依赖缺失、故意损坏的样本；
- 在 CI 里跑接口 diff、批量导出头文件，不需要先把目标加载进进程。

`objc-section` 就是这个能力的命令行门面。

## 安装与构建

0.8.106 起，每个版本的 [GitHub Release](https://github.com/MxIris-Reverse-Engineering/MachOObjCSection/releases)
都附带 `objc-section-macos-universal.zip`（Apple Silicon 与 Intel 通用），解压即用。二进制只做了
ad-hoc 签名、没有公证，用浏览器下载的副本如果被 macOS 拦下，执行
`xattr -d com.apple.quarantine objc-section`。

也可以从源码构建（Xcode 26.0 / Swift 6.2 起）：

```bash
swift build -c release --product objc-section
.build/release/objc-section --help
```

## 五个子命令

```bash
# 导出整个二进制的所有 ObjC 声明
objc-section dump <file>

# 只导出一个类 / 协议 / 分类 / struct / union
objc-section interface <name> <file>

# 把一个二进制的 ObjC API 冻结成 baseline 快照（JSON）
objc-section snapshot <file> --label 26.0 -o baseline.json

# 比对两个二进制（或快照）的 ObjC API
objc-section diff <old> <new>

# 跨 N ≥ 2 个版本追踪每个声明的生命线
objc-section evolution <v1> <v2> <v3> --labels 17.0,18.0,26.0
```

`dump` 是默认子命令，所以 `objc-section <file>` 等价于 `objc-section dump <file>`。

### snapshot / diff / evolution（0006）

三个命令的输入互通：`diff` 与 `evolution` 的每个输入既可以是 Mach-O / fat 二进制 /
dyld shared cache，也可以是 `snapshot` 产出的 JSON——按首个非空白字节是否为 `{`
自动识别，二进制会现场索引并冻结。跨 OS 版本追踪系统框架的典型用法：

```bash
# 每个 OS 版本落一份 baseline（索引是瓶颈，比对是毫秒级）
objc-section snapshot 15.5/dyld_shared_cache_arm64e --dyld-shared-cache -n CoreLocation \
    --label 15.5 -o CoreLocation-15.5.json

# 之后比对不再需要原 cache
objc-section diff CoreLocation-15.5.json CoreLocation-26.5.json
objc-section evolution CoreLocation-*.json --summary-only
```

| 选项（diff / evolution 通用） | 作用 |
|---|---|
| `--summary-only` | 只打印结论（diff：breaking 判定行；evolution：转换摘要段） |
| `--json` | 输出结构化 JSON 而不是文本报告（与 `--summary-only` 互斥） |
| `--fail-on-breaking` | 存在 API-breaking 变更时以非零码退出，供 CI 门禁 |
| `-o, --output-path <path>` | 写入文件而不是 stdout（进度与日志一律走 stderr） |
| `--labels a,b,c` | 仅 evolution：版本轴标签，数量必须等于输入数；缺省取快照的 provenance label 或文件名 |

加载类选项（`--dyld-shared-cache` / `-n` / `-p` / `-a`）与 dump 相同，diff / evolution
下语义是「每个输入都是 cache，从每份里提取同一个镜像」。`snapshot` 不接受
`--uses-system-dyld-shared-cache`（系统 cache 没有可记录的稳定路径）。

### 输入：文件、cache 镜像、fat 二进制

选项与 `swift-section` 完全一致，两个工具可以互换着用同一套参数：

| 选项 | 作用 |
|---|---|
| `<file>` | Mach-O 文件路径，或 dyld shared cache 文件路径 |
| `--dyld-shared-cache` | 声明 `<file>` 是一个 cache，而不是单个 Mach-O |
| `--uses-system-dyld-shared-cache` | 用当前系统的 cache，不需要给 `<file>` |
| `-n, --cache-image-name <name>` | 按名字取 cache 里的镜像，例如 `Foundation` |
| `-p, --cache-image-path <path>` | 按完整路径取 cache 里的镜像 |
| `-a, --architecture <arch>` | fat 二进制里选哪个架构（`x86_64` / `arm64` / `arm64e`） |

fat 二进制不指定 `-a` 会报错，并把可选架构列出来。

### 筛选与输出

| 选项 | 作用 |
|---|---|
| `-s, --sections <kinds>` | 只导出某几类，**逗号分隔**：`--sections classes,protocols`。可选值 `classes` `protocols` `categories` `structs` `unions` |
| `-f, --filter <text>` | 只导出名字包含该文本的声明（不区分大小写） |
| `-o, --output-path <path>` | 写入文件而不是打印到 stdout |
| `-c, --color-scheme <scheme>` | 终端着色：`none`（默认）/ `light` / `dark` |
| `-v, --verbose` | 把索引进度打到 stderr（stdout 仍然只有声明本身） |

`interface` 子命令额外有 `--kind`，用来消歧一个同时是类名又是 struct 名的名字。
不给 `--kind` 时按 `classes → protocols → categories → structs → unions` 的顺序找第一个命中的。

### 十个生成开关

全部默认关闭 —— 不加任何开关时，输出就是元数据的原样，不删也不注释。

| 开关 | 作用 |
|---|---|
| `--strip-protocol-conformance` | 去掉所遵循协议声明的全部属性和方法（必需与可选，沿整条协议继承链），像手写头文件那样不重复声明；`<Protocol, …>` 列表保留 |
| `--strip-overrides` | 去掉只是覆写超类的成员（**文件模式下会剥得更少，见下文**） |
| `--strip-synthesized-ivars` | 去掉 `@property` 合成的 ivar |
| `--strip-synthesized-methods` | 去掉 `@property` 合成的 getter / setter |
| `--strip-ctor-method` | 去掉 `.cxx_construct` |
| `--strip-dtor-method` | 去掉 `.cxx_destruct` |
| `--emit-ivar-offsets` | 每个 ivar 后面加偏移注释 |
| `--emit-property-attributes` | 每个属性后面加原始 attribute 串 |
| `--emit-method-imp-addresses` | 每个方法后面加 `// IMP: 0x…` |
| `--emit-property-accessor-addresses` | 每个属性后面加 getter / setter 的 IMP 地址 |

### 注释模板

```bash
# 把 C 基本类型换成别的拼写，可重复
objc-section dump Foo --c-type-replacement "long long=NSInteger" --c-type-replacement double=CGFloat

# 成套替换，之后可以再用单条覆盖其中某一项
objc-section dump Foo --c-type-preset foundation

# 改 ivar 偏移注释的措辞与进制（都会自动打开 --emit-ivar-offsets）
objc-section dump Foo --ivar-offset-template 'ivar @ ${offset}' --ivar-offset-decimal
```

C 类型两种拼写都收：源码里的写法（`unsigned long long`，shell 里要加引号）和驼峰写法（`ulongLong`）。
写错类型名会直接报错并列出所有支持的名字，不会静默忽略。

`--c-type-preset` 有三套：`stdint`（换成 `uint32_t` 这类）、`foundation`（换成 `NSInteger` / `CGFloat`）、
`mixed`（整数用 stdint、长整型和浮点用 Foundation）。

## 必须知道的六件事

下面四条都是「从签名和帮助文本里看不出来、但会让你对着一份看起来正常的输出得出错误结论」的东西。

### 一、文件模式下超类链会截断，`--strip-overrides` 因此剥得更少

`--strip-overrides` 靠超类链工作：它把每一级超类声明过的成员收集起来，从当前类里减掉。
而超类链能走多远，两种模式不一样：

- **镜像模式**（`MachOImage`，进程内）：所有依赖都已经映射进进程，链一路走到根类。
- **文件模式**（`MachOFile`，磁盘上）：只能在**同一个 dyld shared cache 内部**跨二进制走。
  一个独立的 dylib，它的超类若定义在别的二进制里，链就在那里停住。
  同一个文件里的超类能走到，以 bind 引用自己导出的类时也一样（`-interposable` 链接的文件，
  比如 iOS 26 及更早的模拟器 runtime 的框架）；2026-10-08 之前这种父类会让链在这里就停住。

后果很具体：一个继承 `NSObject` 的类，用独立文件分析时，超类链长度是 1（只有它自己），
`--strip-overrides` 于是一个继承来的成员都剥不掉，输出里会留着 `init`、`dealloc` 这类东西。
这**不是 bug**，是文件模式的固有限制 —— 要跨二进制解析超类，需要一整套镜像搜索与依赖解析机制，
不在本库范围内。

需要完整超类链时，要么分析 cache 里的镜像（cache 内部可以跨），要么走镜像模式。

### 二、`classRWData` / `hasRWPointer` 不在泛型接口上

这两个只有 `MachOImage` 版本，而且是对的：RW data 是 ObjC runtime 在 realize class 时才写进去的，
磁盘上的文件里根本不存在这段数据。

所以 `ObjCMetadataSource` 协议**故意不暴露它们**。泛型化它们只会造出一个「文件模式下永远返回 nil」
的假接口，比没有更糟。需要它们的调用方继续走 `MachOImage` 专属路径：

```swift
// 这样写，不要指望泛型代码能拿到 RW data
if let rwData = objcClass.classRWData(in: machOImage) { … }
```

### 三、分析 dyld shared cache 需要 MachOKit 0.52.101 及以上

**这一条现在只是版本下限，不是限制。** 记在这里是因为如果依赖被降级，症状很隐蔽：不报错，
只是输出里悄悄少掉一半内容。

用 MachOKit 0.52.100 及更早版本从 **macOS 26** 的 cache 里取镜像时，类的 ivar 能读出来，但
**方法、属性、协议列表全是空的**：

```
@interface NSFileManager : NSObject {
    id<NSFileManagerDelegate> _delegate;
    …
}
@end     ← 方法和属性本该在这里，而且不会有任何报错
```

原因：cache 里的方法列表被 Apple 提取到共享的 relative list list 中，按「objc image index」索引，
而拿到这个 index 要在 `ObjCHeaderOptimizationRO` 的 3163 条记录里按 header 偏移找到自己那条。
比对时的偏移换算基准取错了 —— 用的是**找到 objc optimization 结构的那个子 cache**，而镜像本身在
**另一个子 cache** 里（这份 cache 有 12 个子 cache，optimization 在 `.03.dyldreadonly`，
Foundation 在 `.01`）。基准不同则永不匹配，index 为 nil，所有按 index 取的列表都落空。

修复来自上游 [p-x9/MachOKit#310](https://github.com/p-x9/MachOKit/pull/310)，
已随 MachOKit fork 的 **0.52.101** 发布，本项目已经依赖该版本。实测 `NSFileManager` 从 5 行
变成 132 行完整接口。

这个缺陷从 MachOKit 0.23.0 起就在代码里，但只有 macOS 26 这种子 cache 布局才触发它 ——
macOS 15 及更早的 cache 在旧版本上也是正常的，所以「以前能用」不构成依赖可以不升的理由。

同一种布局还让本库自己漏过一次，症状也一样不报错：2026-10-13 之前，从 **macOS 26.4 起**的 cache
里读被别的镜像加过 category 的类（NSView、NSWindow、NSString 等）时，**实例属性和协议列表是空的**，
方法照常。那几张表在 `.dylddata` 文件里，而读取器只在镜像 header 所在的文件里找。详见
[实现说明](../Internal/RelativeListsAcrossSubCacheFiles.md)。

### 四、纯 Swift 类的 ivar 记录两种模式对不上

编译器为纯 Swift 类（名字形如 `_TtC8ModuleName9TypeName`）生成的 ObjC 兼容记录里，
`ivar_t.offset` 字段两种模式读出来不一样：镜像模式读到 0，文件模式解析 rebase 后读到别的值；
个别 ivar 在镜像模式下会因为读不到偏移而被整条丢掉，两边的 ivar 条数因此也可能不同。

这来自底层 `ObjCIvarProtocol` 的两版实现，不是本层引入的。带 `@objc(ExplicitName)` 的 Swift 类
走的是普通 ObjC ivar 记录，不受影响。

分析纯 Swift 类时不要把 ivar 偏移当准数用。

### 五、baseline 快照跨工具版本不通用 —— formatVersion 契约

`snapshot` 产出的 JSON 带一个 `formatVersion` 头（当前 = 1）。快照里的键格局
（`method:-…`、`attr:…`、`adopts:…` 这些命名空间字符串）就是事实上的持久化格式，
键格局一变，旧 baseline 与新工具比出来的结果会**静默错误**——所以工具在解码时严格校验
版本号：不相等直接报错（`Unsupported ObjC API snapshot format version …`），
要求用当前版本的工具重新生成 baseline。

这不是缺陷而是设计：一个显式报错换掉一类无声的误报。把 baseline 存进 git 时，
建议在文件名或目录里带上生成时的 OS 版本，重新生成的成本只是一次索引。

另外两条 diff 结果的解读须知：

- **ivar 的纯布局变化不可见**：offset 刻意不参与比较（non-fragile ABI 下由运行时滑动，
  且一处中插会级联报其后所有 ivar）。ivar 的类型变化仍然可见。
- **判定分不出公开 API 与私有实现**：ObjC 无访问控制，私有 selector 的重命名同样报
  API-breaking，需要自行结合语义判断。
- **协议新采纳另一个协议可能报 API-breaking**：`@protocol P <Q>` 让 P 的实现方也得实现 Q 的
  必选成员，所以只要展开后 Q 带来了 P 原先不要求的必选成员，就和给 P 直接加必选成员一样判为
  breaking；被采纳的协议不在快照里、无法展开时也按 breaking 处理。类和 category 新采纳协议仍是兼容改动。

### 六、dump 的空结果只写 stderr，不改退出码

`dump` 一个声明都没导出时，会往 **stderr** 写一行说明是哪种「空」，**退出码仍然是 0**：

| stderr | 含义 |
|---|---|
| `no Objective-C metadata found in <image>` | 整个索引是空的 —— 这个二进制里没有 ObjC 内容 |
| `no <kind> found in <image>` | 你用 `--sections` 点名的某一类在这个二进制里为空（逐类一行） |
| `--filter '<text>' matched none of the <N> declarations in <image>` | 索引里有 N 个声明，但没有一个匹配 `--filter` |

第一条与第二条互斥：整个索引为空时只报第一条，不会再逐类重复。默认（不给 `--sections`）
时不报第二条 —— 否则每次 dump 一个纯 Swift 二进制都会为你从没点名过的类别刷屏。

**退出码不变是有意的**：这是诊断信息，不是失败，不该让任何既有脚本或 CI 因此变红。
需要门禁的场景走 `diff --fail-on-breaking` 那条专用通道。

在这之前，「二进制里没有 ObjC」「点名的类别为空」「filter 没匹配上」三种情况的输出
逐字节相同 —— stdout 空、stderr 空、退出码 0 —— 分不出是真没有还是读失败了。

## 库调用方：泛型参数是推断出来的

`ObjCInterfaceIndexer` 和 `ObjCInterfaceBuilder` 现在带一个泛型参数，但**调用点不用改**：

```swift
// 镜像模式，和 0002 之前一模一样
let indexer = ObjCInterfaceIndexer(machO: image, imagePath: image.imagePath)

// 文件模式，只是换了一个实参
let indexer = ObjCInterfaceIndexer(machO: machOFile, imagePath: machOFile.imagePath)
```

**唯一要改的是显式写出类型名的地方** —— 变量类型标注、函数返回类型、存储属性类型：

```swift
// 改前
private var indexer: ObjCInterfaceIndexer
func makeIndexer() -> ObjCInterfaceIndexer

// 改后
private var indexer: ObjCInterfaceIndexer<MachOImage>
func makeIndexer() -> ObjCInterfaceIndexer<MachOImage>
```

## 库调用方：没有 class object 的类由宿主补充

带 ObjC 祖先的 Swift 类里有三种不在 `__objc_classlist`：泛型类，以及经 `__objc_stublist`
注册的类（超类在开了 library evolution 的别的模块里，或超类是泛型）。索引器只遍历类列表，
看不到它们；它们的 `class_ro_t` 要读 Swift metadata 才找得到，本库不读，由宿主
（MachOSwiftSection）算好后经 `init(machO:imagePath:suppliedClasses:eventHandler:)` 传进来，
术语见[补充类](../Glossary.md#supplied-class补充类)。命令行不接这个入口。下面几条在签名里看不出来：

- **偏移约定与 `ObjCClassRODataProtocol.offset` 相同。** 独立二进制是 slice 内的文件偏移，
  dyld cache 里的镜像是「未滑动地址减 `sharedRegionStart`」，`MachOImage` 是到镜像 header
  的距离。传错约定不会报错，只会读不出（被跳过）或读成别的数据。
- **跳过不报错。** 名字为空、名字已被占用（class object 优先，补充类之间先到先得）、偏移处读不出
  `class_ro_t` 的补充类都被静默跳过，`prepare()` 之后 `suppliedClassGroup(forName:)` 返回
  `nil` 就是被跳过了。进度事件的总数在开始时只去掉空名字和重名的，所以宿主传错时
  `currentCount` 到不了 `totalCount`。
- **两个查询入口分工。** 补充类进 `classNames`、事件、渲染与 API snapshot，但
  `classGroup(forName:)` 对它返回 `nil`（`ObjCClassGroup` 要求一个 class object），要用
  `suppliedClassGroup(forName:)`。只认 `classGroup` 的下游代码会把补充类当成不存在。
- **名字原样使用，超类链按名字接。** 不读 RO 的 `name`（泛型模板里是 NULL）；超类链只在
  本索引里按名字接，遇到本镜像之外的名字即停，所以超类在别的镜像时 `stripOverrides`
  剥不到继承来的成员，镜像模式也一样。
- **偏移未知的 ivar 的 `offset` 是 0，不是真实偏移。** 泛型类模板的 ivar 偏移由运行时按特化填，
  这些 ivar 列在 `ivarNamesWithUnknownOffset` 里；渲染时偏移注释写 `offset: unknown`，
  不经过 `ivarOffsetCommentBuilder`。自己读 `ObjCClassInfo.ivars` 的调用方要先查这个集合。
- **超类在别的模块里的类，category 要靠 `classStubOffset` 归位。** 超类在开了 library
  evolution 的别的模块里时，Swift 把类的 `@objc` 扩展编成 category，`cls` 指向 class stub
  （`__objc_stublist` 条目里存的地址，即 stub 的 isa 字，`CMs` 符号所在处）。给了这个偏移，
  这些 category 就记在补充类的名字下，`targetIsSwiftStable` 为 `true`；不给，strip 过的
  二进制里它们会被整个丢掉。
- **超类是泛型的类，要用运行时名字补充。** 这种类也登记在 `__objc_stublist`，但它的 category
  在 `__objc_catlist` 里，`cls` 指向类自己的 metadata 而不是 stub（它的 stub 只有私有符号
  `CMt`，没有 `CMs`）。所以这些 category 按 `class_ro_t` 里的名字（`_TtC…`）归位，strip 过
  也一样，`classStubOffset` 用不上；补充类换了别的写法，类和它的 category 就分在两个名字下。

## 库调用方：把 N 个版本合并成一份带演进标注的头文件

`ObjCEvolutionInterfaceBuilder`（`ObjCInterface`）把同一个二进制 N ≥ 2 个版本的头文件按声明合并成一份：外观与
`objc dump` 相同，有变化的声明带 `// [○●●] added in 13.0` 这样的注释，传了平台名时再补上 `API_AVAILABLE` /
`API_OBSOLETED`，术语见 [evolution interface](../Glossary.md#evolution-interface演进合并头文件)。`objc-section`
命令行不提供它，把它接到命令行上的是 MachOSwiftSection 的 `swift-section objc evolution --interface`。

```swift
var builder = ObjCEvolutionInterfaceBuilder()
for (label, image) in imagesOldestFirst {
    let indexer = ObjCInterfaceIndexer(machO: image, imagePath: image.imagePath)
    try await indexer.prepare()
    builder.addVersion(indexer: indexer, machO: image, version: ObjCAPIVersionDescriptor(label: label))
}
let merged = try builder.build(availabilityPlatform: "macos")
// merged.interface 是合并后的头文件，merged.evolution 是标注依据的 ObjCAPIEvolution
```

下面几条在签名里看不出来：

- **调用顺序就是版本轴，旧的在前。** 少于两个版本时 `build` 抛 `fewerThanTwoVersions`。版本的 label 原样写进标注和可用性宏。
- **索引器要先 `prepare()`，补充类在创建索引器时传。** 与取快照的要求相同，`addVersion` 不会替你准备。
- **`addVersion` 返回后就不再引用索引器和 MachO。** 宿主可以逐个版本加载，加完就释放。builder 留下的是每个版本的快照、
  每个声明最新的渲染，以及渲染变过的那几版。在 M3 Ultra 上合并 macOS 11.0.1 到 15.0 的 8 个 AppKit：每个版本 6–8 秒，
  每加一个版本进程占用涨 25–35 MB，`build` 之后共 451 MB。
- **用 `ObjCGenerationOptions.default` 渲染，十个生成开关都不适用。** 剥掉的成员没有行可以挂标注，地址和偏移注释每版都不同。
  `cTypeReplacements` 在 `init` 里给，对每个版本都生效。
- **没有标注就是整条轴上都在、从没变过。** 加入或删掉的容器只在它那一行标注，成员不再各自标注，它们跟着容器存在。
  superclass 和采纳的协议都写在 `@interface` 那一行里，它们的变化写成那一行上方的注释行。
- **同一个容器里 identity 相同的成员只写第一条。** 快照只比较第一条，合并结果跟着只写第一条，其余的连同签名列在文件末尾的
  identity key 冲突警告里。所以同一个镜像交两次时，正文是 `objc dump` 的输出少掉这些重复行。
- **可用性宏只在一个宏能说完整个生命周期时才写。** 平台名原样写进宏，label 必须是 1–3 段数字。引入后一直在：
  `API_AVAILABLE(macos(13.0))`；引入后又删掉：`API_OBSOLETED("Removed", macos(12.0.1, 13.0, 13.0))`。从轴起点就在、
  后来删掉的不写：`API_OBSOLETED` 必须带引入版本，而版本轴不知道它，这一点与 Swift 一侧的 `@available(macOS, obsoleted:)`
  不同。删了又加回的、只被修改过的也不写；ivar、采纳的协议和 superclass 从来不写。
- **C struct 与 union 不参与追踪。** 它们放在最后，每个取自定义它的最新版本，前面一行注释说明这一点。
- **声明会在几个 image 之间搬家的，一个版本交一组 image。** 见下一节。

## 库调用方：几个 image 当作一个 API 面

AppKit 的声明这些年陆续搬进 UIFoundation、CollectionViewCore，SwiftUI 的搬进 SwiftUICore。每个版本只读一个 image 时，
搬走的报成 removed、搬来的报成 added。把每个版本的一组 image（[image 组](../Glossary.md#image-groupimage-组)）交给演进，
它们就被当作同一个 API 面来比，搬家单独记成 `ObjCImageMove`，报告写成 `> moved in 14.0: AppKit → UIFoundation`，
合并头文件写成 `// [●●●] moved in 14.0: AppKit → UIFoundation`。`objc-section` 命令行不提供这个功能。

```swift
// The lineage report: each version's images, the primary first
let evolution = try ObjCAPIEvolutionBuilder().evolution(
    ofImageGroups: [
        [ObjCAPIImageSnapshot(imageName: "AppKit", snapshot: appKit13), ObjCAPIImageSnapshot(imageName: "UIFoundation", snapshot: uiFoundation13)],
        [ObjCAPIImageSnapshot(imageName: "AppKit", snapshot: appKit14), ObjCAPIImageSnapshot(imageName: "UIFoundation", snapshot: uiFoundation14),
         ObjCAPIImageSnapshot(imageName: "CollectionViewCore", snapshot: collectionViewCore14)],
    ],
    versions: [ObjCAPIVersionDescriptor(label: "13.0"), ObjCAPIVersionDescriptor(label: "14.0")]
)
print(ObjCAPIEvolutionReporter().report(evolution))

// The merged header: one addVersion(images:version:) per version
var builder = ObjCEvolutionInterfaceBuilder()
builder.addVersion(
    images: [
        ObjCEvolutionInterfaceImage(imageName: "AppKit", indexer: appKitIndexer, machO: appKit),
        ObjCEvolutionInterfaceImage(imageName: "UIFoundation", indexer: uiFoundationIndexer, machO: uiFoundation),
    ],
    version: ObjCAPIVersionDescriptor(label: "13.0")
)
```

下面几条在签名里看不出来：

- **image 名由你给，不从快照推。** provenance 的 `binaryPath` 对 cache 里的 image 写的是 `<cache 路径> (AppKit)`，推不准。
  每个版本的 `imageNames` 由演进按组填好；单 image 演进里它是 nil，JSON 与报告都与以前逐字节相同。
- **只交这个版本里在场的 image，主 image 在前。** image 可以在轴上中途加入，还没有它的版本不交它；
  组为空就是这个版本什么都没有。组的顺序决定同名的类比较哪一份，换顺序本身不算搬家。
- **一个版本里的几个 image 怎么合并**：同名的类比较第一个 image 的那份，其余的列进 key collision 警告；同名的 category
  合成一个，成员按组顺序拼接；各 image 自带的 protocol 副本，相同的去重，不同的比较第一份、其余的进警告。警告里被丢的
  那份后面用括号注明 image。合并头文件的渲染跟着同一套规则：类和协议取被比较的那一份，category 成员取第一个声明它的 image，
  C struct 与 union 取第一个定义它的 image。
- **搬家只在两侧都在场时记，成员只在换法与所属容器不同时才记。** 整个类搬走时方法不逐条记；category 拆到两个 image 后，
  换了 image 的方法单独记。protocol 不属于任何 image，从不搬家。只有搬家的成员在报告里取 `latestSignature` 显示签名。
- **搬家不影响 `hasBreakingChange`。** 旧 install name 下的符号还在不在，取决于旧 image 有没有 re-export 新 image，快照里
  没有这个事实，所以只报不判。
- **`addVersion(images:version:)` 一次交齐一个版本的全部 image。** 这几个索引器在调用期间要同时在内存里，返回后就可以释放；
  版本之间仍可加完一版就放掉。同一个 builder 不能混用两种 `addVersion`，混用时 `build` 抛
  `ObjCEvolutionInterfaceError.singleImageVersionsMixedWithImageGroups`。
- **合并头文件的开头多几行 Image group 图例。** 每个 image 一行存在位图，按它在轴上首次出现的顺序排，与报告头部相同。

## 不建议 conform `ObjCMetadataSource`

这个协议的预期实现者只有 `MachOFile` 和 `MachOImage` 两个，都由本库提供。
它的 requirement 集合会随索引层的需要继续扩充，每次扩充对外部实现者都是破坏性的。
把它当成一个封闭协议来用 —— 消费它（写 `<MachO: ObjCMetadataSource>` 的泛型代码）没问题，
实现它请先开 issue。
