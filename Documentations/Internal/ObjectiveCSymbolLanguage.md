# `SymbolLanguage.objectiveC`：在这里定义，加载时注册

> 面向维护者的实现说明。对应 MachOKitExtensions 的提案
> [split-symbol-language](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Evolutions/0004-split-symbol-language.md)：
> MachOKitExtensions 3.0.0 起只认 C 与 C++ 的符号名，别的语言由拥有它的包定义、判断并注册。

## 是什么

- `SymbolLanguage.objectiveC`（`rawValue` 为 `"Objective-C"`，这个字符串就是它的身份）定义在 `MachOObjCSection` 模块的 `Support/SymbolLanguage+ObjectiveC.swift`。
- 判断规则在同一个文件的 `ObjectiveCSymbolNameRecognition`，只看名字开头的字节：方法实现 `-[`、`+[`，运行时符号 `_OBJC_`、`__OBJC_`、`l_OBJC_`、`L_OBJC_`、`_objc_msgSend$`。规则原样搬自 MachOKitExtensions 2.x 的 `SymbolLanguage`。
- 注册之后，MachOKitExtensions 的 `SymbolLanguage(ofSymbolNamed:)` 把这些名字判成 `.objectiveC`，它的 C/C++ 符号索引（`SymbolIndexStore`）不再收这些名字，只留它们的偏移作边界：地址落在 ObjC 方法里时，`closestSymbols` 答 `nil`，不再答出前面一个不相干的 C 函数。

## 怎么注册

Swift 没有加载时初始化，所以借 C target：`MachOObjCSectionC` 里的 `symbol_language_registration.c` 有一个 `__attribute__((constructor))`，在镜像加载时调用 `MachOObjCSection` 用 `@_cdecl("objc_section_register_symbol_language")` 导出的 Swift 函数，向 `SymbolLanguageRegistry.shared` 登记 `.objectiveC`。

- `MachOObjCSection` 本来就依赖 `MachOObjCSectionC`。SwiftPM 与 Xcode 自带的包集成整块链接每个 target，constructor 总会带上；从静态归档链接时（Tuist 的静态 framework、静态库），链接器只拉被符号引用到的成员，而 constructor 是 `static` 的、`-ObjC` 也不拉它，所以这个 C 文件另外导出一个什么都不做的锚点 `objc_section_registration_anchor`，由 `SymbolLanguage+ObjectiveC.swift` 的注册函数调用：那个 Swift 文件定义了 extension，带 `-ObjC` 的链接一定拉进它，它对锚点的引用再把 C 文件连同 constructor 拉进来。调用方什么都不用做；别删那个调用（`ObjectiveCSymbolLanguageTests.languageFileRefersToTheRegistrationAnchor` 钉住引用的两端）。2026-11-20 起；之前 RuntimeViewer 的 Tuist workspace 里这门语言一直没注册上（MachOSwiftSection 账本第 144 节）。
- 用 `@_cdecl` 而不是 SE-0495 的 `@c`：本包的工具版本还是 6.2，`@c` 要 6.3。
- 2026-11-19 在 MachOKitExtensions 的提案里做过原型：探针程序不引用注册模块的任何符号，`swift build` 的 debug、release 与 `xcodebuild` 的 Release 都在加载时拿到了注册。纯 Swift 的 SE-0492 `@section` 写进 `__mod_init_func` 链接失败。

## 测试

`Tests/MachOObjCSectionTests/ObjectiveCSymbolLanguageTests.swift`：没有测试调用注册函数，测试进程加载时已经登记；代表名字的判定；Foundation 的 ObjC 名字不进 C/C++ 索引、C 名字全在。

这个测试 target 里的 XCTest 类 `MachOObjCSectionTests` 在 `setUp` 读本机 `Downloads` 里的文件，读不到就崩溃（基线已有的问题），单独跑这几个测试用 `--filter ObjectiveCSymbolLanguageTests`。
