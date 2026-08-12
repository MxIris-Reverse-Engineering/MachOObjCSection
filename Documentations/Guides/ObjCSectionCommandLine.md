# objc-section 使用指南

- **对应提案**: [0002](../Evolutions/0002-objc-machofile-genericization-and-cli.md)
- **最后更新**: 2026-08-12

这份文档写给两类人：用 `objc-section` 命令行导出 ObjC 头的人，以及直接调用
`ObjCInterfaceIndexer` / `ObjCInterfaceBuilder` 处理磁盘上二进制的人。

**从 API 签名和 `--help` 里看不出来、但踩了就出错的东西全在「必须知道的四件事」一节**，
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

```bash
swift build -c release --product objc-section
.build/release/objc-section --help
```

## 两个子命令

```bash
# 导出整个二进制的所有 ObjC 声明
objc-section dump <file>

# 只导出一个类 / 协议 / 分类 / struct / union
objc-section interface <name> <file>
```

`dump` 是默认子命令，所以 `objc-section <file>` 等价于 `objc-section dump <file>`。

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
| `-s, --sections <kinds>` | 只导出某几类：`classes` `protocols` `categories` `structs` `unions` |
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
| `--strip-protocol-conformance` | 去掉 `<Protocol, …>` 列表，以及这些协议已经声明过的成员 |
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

## 必须知道的四件事

下面四条都是「从签名和帮助文本里看不出来、但会让你对着一份看起来正常的输出得出错误结论」的东西。

### 一、文件模式下超类链会截断，`--strip-overrides` 因此剥得更少

`--strip-overrides` 靠超类链工作：它把每一级超类声明过的成员收集起来，从当前类里减掉。
而超类链能走多远，两种模式不一样：

- **镜像模式**（`MachOImage`，进程内）：所有依赖都已经映射进进程，链一路走到根类。
- **文件模式**（`MachOFile`，磁盘上）：只能在**同一个 dyld shared cache 内部**跨二进制走。
  一个独立的 dylib，它的超类若定义在别的二进制里，链就在那里停住。

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

### 四、纯 Swift 类的 ivar 记录两种模式对不上

编译器为纯 Swift 类（名字形如 `_TtC8ModuleName9TypeName`）生成的 ObjC 兼容记录里，
`ivar_t.offset` 字段两种模式读出来不一样：镜像模式读到 0，文件模式解析 rebase 后读到别的值；
个别 ivar 在镜像模式下会因为读不到偏移而被整条丢掉，两边的 ivar 条数因此也可能不同。

这来自底层 `ObjCIvarProtocol` 的两版实现，不是本层引入的。带 `@objc(ExplicitName)` 的 Swift 类
走的是普通 ObjC ivar 记录，不受影响。

分析纯 Swift 类时不要把 ivar 偏移当准数用。

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

## 不建议 conform `ObjCMetadataSource`

这个协议的预期实现者只有 `MachOFile` 和 `MachOImage` 两个，都由本库提供。
它的 requirement 集合会随索引层的需要继续扩充，每次扩充对外部实现者都是破坏性的。
把它当成一个封闭协议来用 —— 消费它（写 `<MachO: ObjCMetadataSource>` 的泛型代码）没问题，
实现它请先开 issue。
