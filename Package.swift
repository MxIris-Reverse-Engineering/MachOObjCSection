// swift-tools-version: 6.2

@preconcurrency import PackageDescription
import Foundation

func envEnable(_ key: String, default defaultValue: Bool = false) -> Bool {
    let value = Context.environment[key]
    guard let value else {
        return defaultValue
    }
    if value == "1" {
        return true
    } else if value == "0" {
        return false
    } else {
        return defaultValue
    }
}

let usingLocalDependencies = envEnable("USING_LOCAL_DEPENDENCIES")

extension Package.Dependency {
    enum LocalSearchPath {
        case package(path: String, isRelative: Bool, isEnabled: Bool = usingLocalDependencies, traits: Set<PackageDescription.Package.Dependency.Trait> = [.defaults])
    }

    static func package(local localSearchPaths: LocalSearchPath..., remote: Package.Dependency) -> Package.Dependency {
        let currentFilePath = #filePath

        let isClonedDependency = currentFilePath.contains("/checkouts/") ||
            currentFilePath.contains("/SourcePackages/") ||
            currentFilePath.contains("/.build/")

        if isClonedDependency {
            return remote
        }

        for local in localSearchPaths {
            switch local {
            case .package(let path, let isRelative, let isEnabled, let traits):
                guard isEnabled else { continue }
                let url = if isRelative {
                    URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: currentFilePath))
                } else {
                    URL(fileURLWithPath: path)
                }

                if FileManager.default.fileExists(atPath: url.path) {
                    return .package(path: url.path, traits: traits)
                }
            }
        }
        return remote
    }
}

let package = Package(
    name: "MachOObjCSection",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .watchOS(.v6),
        .tvOS(.v13),
    ],
    products: [
        .library(
            name: "MachOObjCSection",
            targets: ["MachOObjCSection"]
        ),
        .library(
            name: "ObjCMetadataSource",
            targets: ["ObjCMetadataSource"]
        ),
        .library(
            name: "ObjCDeclarationRendering",
            targets: ["ObjCDeclarationRendering"]
        ),
        .library(
            name: "ObjCIndexing",
            targets: ["ObjCIndexing"]
        ),
        .library(
            name: "ObjCInterface",
            targets: ["ObjCInterface"]
        ),
        .library(
            name: "ObjCOutputTransformer",
            targets: ["ObjCOutputTransformer"]
        ),
        .library(
            name: "ObjCDiffing",
            targets: ["ObjCDiffing"]
        ),
        // The bridge to swift-type-indexing's SDK index, macOS only.
        .library(
            name: "ObjCTypeIndexing",
            targets: ["ObjCTypeIndexing"]
        ),
        // The Objective-C layer of MachOSwiftSection's cross-reference analysis.
        // Its interfaces are `@_spi(Internals)`: they serve MachOSwiftSection's
        // `CrossReferenceAnalysis` and promise no stable API (MachOSwiftSection
        // proposal `move-cross-reference-layers`).
        .library(
            name: "ObjCCodeReferences",
            targets: ["ObjCCodeReferences"]
        ),
        .executable(
            name: "objc-section",
            targets: ["objc-section"]
        ),
    ],
    dependencies: [
        .package(
            local: .package(
                path: "../MachOKit",
                isRelative: true
            ),
            remote: .package(
                url: "https://github.com/MxIris-Reverse-Engineering/MachOKit",
                // 0.55.100 is the fork's release over upstream 0.55.0, the
                // first to provide `DyldCache.locateValue` and `LocatedValue`
                // (SPI `Support`). They replace this package's own helpers of
                // the same names, which 0.55.0 made ambiguous. It still
                // carries 0.52.105, which releases a file handle's identity
                // together with the handle (`FileHandleHolder` keys the
                // mapping of every file and dyld cache it reads on it), and
                // reads an image without an export trie as exporting nothing.
                from: "0.55.100"
            )
        ),
        .package(
            local: .package(
                path: "../swift-objc-dump",
                isRelative: true,
            ),
            remote: .package(
                url: "https://github.com/MxIris-Reverse-Engineering/swift-objc-dump",
                // 0.8.102 writes every argument of a selector with unlabeled
                // ones in `ObjCMethodInfo.headerString`, the member signature
                // the API diff reports.
                from: "0.8.102"
            )
        ),
        .package(
            url: "https://github.com/p-x9/swift-fileio.git",
            from: "0.14.0"
        ),
        .package(
            local: .package(
                path: "../swift-semantic-string",
                isRelative: true
            ),
            remote: .package(
                url: "https://github.com/MxIris-Reverse-Engineering/swift-semantic-string",
                // 0.7.0 brings `SemanticType.macro` and `Macro`, which the
                // Swift naming annotations print `NS_SWIFT_NAME` and
                // `NS_REFINED_FOR_SWIFT` with (proposal swift-type-indexing-package).
                from: "0.7.0"
            )
        ),
        .package(
            local: .package(
                path: "../MachOKitExtensions",
                isRelative: true
            ),
            remote: .package(
                url: "https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions",
                // 1.1.1 builds each sub-cache of a dyld cache once and hands
                // back the same instance on every lookup, which `fileHandle`
                // keys its mapping on. 1.2.0 adds `resolveSelfBind(fileOffset:)`,
                // which `resolveRebase` needs for a pointer slot bound to the
                // image's own export. 2.0.0 only adds the MachOReading and
                // MachOResolving modules, which this package does not use, so
                // it built against either major version. 2.0.0 also adds
                // `MachOCodeReferences`, the cross-reference core that
                // `ObjCCodeReferences` plugs into, so 2.0.0 was the floor from
                // the release that took that layer in. 3.0.0 takes the
                // Objective-C symbol-name rules out of `MachOSymbols`: this
                // package defines `SymbolLanguage.objectiveC` and registers it
                // (proposal split-symbol-language), so 3.0.0 is the floor now.
                "3.0.0"..<"4.0.0"
            )
        ),
        .package(
            url: "https://github.com/apple/swift-collections",
            from: "1.2.0"
        ),
        // Already in the graph before this line existed — `swift-objc-dump`'s
        // `ObjCTypeDecodeKit` depends on `FoundationToolbox`. Declaring it
        // directly costs nothing in resolution or build time and lets the
        // targets below drop their hand-rolled copies of `Mutex` and
        // `uppercasedFirst` — see proposal 0005.
        .package(
            local: .package(
                path: "../FrameworkToolbox",
                isRelative: true
            ),
            remote: .package(
                url: "https://github.com/Mx-Iris/FrameworkToolbox",
                from: "0.9.0"
            )
        ),
        // The SDK index (API notes and module interfaces) `ObjCTypeIndexing`
        // bridges to: it reads a class's or protocol's Swift naming from API
        // notes, and attributes a type to its module through this package's
        // Objective-C metadata. Every source of it is macOS-only, so the one
        // target that uses it depends on it with a macOS condition. 0.1.0 is
        // its first release.
        .package(
            local: .package(
                path: "../swift-type-indexing",
                isRelative: true
            ),
            remote: .package(
                url: "https://github.com/MxIris-Reverse-Engineering/swift-type-indexing",
                from: "0.1.0"
            )
        ),
        // Command-line only. The library targets stay free of both.
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.5.1"
        ),
        .package(
            url: "https://github.com/onevcat/Rainbow",
            from: "4.0.0"
        ),
    ],
    targets: [
        .target(
            name: "MachOObjCSection",
            dependencies: [
                // Also holds the constructor that registers
                // `SymbolLanguage.objectiveC` when the image loads.
                "MachOObjCSectionC",
                "MachOKit",
                // Chained-fixup and dyld cache lookups go through its cached
                // views; MachOKit's own methods walk the fixup chains on every call.
                .product(name: "MachOKitExtensions", package: "MachOKitExtensions"),
                .product(name: "MachOSymbols", package: "MachOKitExtensions"),
                .product(name: "FileIO", package: "swift-fileio"),
                .product(name: "ObjCDump", package: "swift-objc-dump"),
            ]
        ),
        .target(
            name: "MachOObjCSectionC"
        ),
        // The Objective-C recognizer of the cross-reference analysis: message
        // sends, class references, instance variables, method names. A target
        // of its own, so the upstream `MachOObjCSection` target stays untouched.
        .target(
            name: "ObjCCodeReferences",
            dependencies: [
                "MachOKit",
                "MachOObjCSection",
                .product(name: "MachOCodeReferences", package: "MachOKitExtensions"),
            ]
        ),
        // The generic entry point onto Objective-C metadata. It restates
        // MachOObjCSection's parallel `MachOFile` / `MachOImage` overloads as
        // requirements taking `Self`, which is what lets everything above it be
        // written once instead of twice. Kept out of the core target on
        // purpose — see proposal 0002's "Alternatives considered".
        .target(
            name: "ObjCMetadataSource",
            dependencies: [
                "MachOObjCSection",
                "MachOKit",
                .product(name: "MachOKitExtensions", package: "MachOKitExtensions"),
                .product(name: "ObjCDump", package: "swift-objc-dump"),
            ]
        ),
        .target(
            name: "ObjCDeclarationRendering",
            dependencies: [
                "MachOObjCSection",
                "ObjCMetadataSource",
                "MachOKit",
                .product(name: "MachOKitExtensions", package: "MachOKitExtensions"),
                .product(name: "Semantic", package: "swift-semantic-string"),
                .product(name: "ObjCDump", package: "swift-objc-dump"),
                // For `.box.uppercasedFirst()` / `.box.lowercasedFirst()`.
                .product(name: "FoundationToolbox", package: "FrameworkToolbox"),
            ]
        ),
        .target(
            name: "ObjCIndexing",
            dependencies: [
                "MachOObjCSection",
                "ObjCMetadataSource",
                "ObjCDeclarationRendering",
                "MachOKit",
                .product(name: "Semantic", package: "swift-semantic-string"),
                .product(name: "ObjCDump", package: "swift-objc-dump"),
                // For `@Mutex`. Deliberately `SwiftStdlibToolbox` rather than
                // `OSToolbox`: the split that moves `Mutex` down a layer is not
                // released yet, and once it is, this target re-exports it.
                .product(name: "SwiftStdlibToolbox", package: "FrameworkToolbox"),
            ]
        ),
        .testTarget(
            name: "MachOObjCSectionTests",
            dependencies: [
                "MachOObjCSection",
                .product(name: "MachOSymbols", package: "MachOKitExtensions"),
            ]
        ),
        // The ObjC-specific transformer modules. They extend the shared
        // `Transformer` namespace from swift-semantic-string, but their
        // vocabulary is Objective-C (C primitive spellings, ivar offsets), so
        // they ship here rather than in a general-purpose string package.
        .target(
            name: "ObjCOutputTransformer",
            dependencies: [
                .product(name: "OutputTransformer", package: "swift-semantic-string"),
                .product(name: "Semantic", package: "swift-semantic-string"),
            ]
        ),
        // The ObjC API diff engine (proposal 0006). Pure value computation
        // over the ObjCDump info model — deliberately independent of the
        // rendering and indexing layers, mirroring how MachOSwiftSection's
        // SwiftDiffing sits on SwiftDeclaration alone. ObjCMetadataSource is
        // here only for the model-derived accessors (`uniqueName` & co.).
        .target(
            name: "ObjCDiffing",
            dependencies: [
                "ObjCMetadataSource",
                .product(name: "ObjCDump", package: "swift-objc-dump"),
            ]
        ),
        .target(
            name: "ObjCInterface",
            dependencies: [
                "MachOObjCSection",
                "ObjCMetadataSource",
                "ObjCDeclarationRendering",
                "ObjCIndexing",
                "ObjCDiffing",
                "MachOKit",
                .product(name: "Semantic", package: "swift-semantic-string"),
                .product(name: "ObjCDump", package: "swift-objc-dump"),
                // For `.box.uppercasedFirst()`.
                .product(name: "FoundationToolbox", package: "FrameworkToolbox"),
            ]
        ),
        // The bridge to swift-type-indexing: `ObjCDeclaredTypeNames`, an
        // image's Objective-C metadata as the `DeclaredTypeNameSource` its
        // `TypeDatabase` reads private types from, and the API notes' Swift
        // naming of a class or protocol as `ObjCSwiftImportNotes`. A target of
        // its own, so the indexing and rendering layers stay free of the SDK
        // index, which only builds for macOS.
        .target(
            name: "ObjCTypeIndexing",
            dependencies: [
                "ObjCMetadataSource",
                "ObjCIndexing",
                "ObjCDeclarationRendering",
                .product(name: "TypeIndexing", package: "swift-type-indexing", condition: .when(platforms: [.macOS])),
            ]
        ),
        .executableTarget(
            name: "objc-section",
            dependencies: [
                "MachOObjCSection",
                "ObjCMetadataSource",
                "ObjCDeclarationRendering",
                "ObjCIndexing",
                "ObjCInterface",
                "ObjCOutputTransformer",
                "ObjCDiffing",
                "MachOKit",
                .product(name: "MachOKitExtensions", package: "MachOKitExtensions"),
                .product(name: "Semantic", package: "swift-semantic-string"),
                .product(name: "OutputTransformer", package: "swift-semantic-string"),
                .product(name: "ObjCDump", package: "swift-objc-dump"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Rainbow", package: "Rainbow"),
            ]
        ),
        .testTarget(
            name: "ObjCOutputTransformerTests",
            dependencies: [
                "ObjCOutputTransformer",
                .product(name: "OutputTransformer", package: "swift-semantic-string"),
                .product(name: "Semantic", package: "swift-semantic-string"),
            ]
        ),
        .testTarget(
            name: "ObjCInterfaceTests",
            dependencies: [
                "ObjCInterface",
                "ObjCIndexing",
                "ObjCDeclarationRendering",
                "ObjCDiffing",
                .product(name: "Semantic", package: "swift-semantic-string"),
                .product(name: "ObjCDump", package: "swift-objc-dump"),
                .product(name: "FoundationToolbox", package: "FrameworkToolbox"),
            ]
        ),
        .testTarget(
            name: "ObjCIndexingTests",
            dependencies: [
                "ObjCIndexing",
                "ObjCDeclarationRendering",
                .product(name: "Semantic", package: "swift-semantic-string"),
                .product(name: "ObjCDump", package: "swift-objc-dump"),
            ]
        ),
        .testTarget(
            name: "ObjCMetadataSourceTests",
            dependencies: [
                "ObjCMetadataSource",
                "ObjCIndexing",
                "ObjCInterface",
                "ObjCDeclarationRendering",
                .product(name: "MachOKitExtensions", package: "MachOKitExtensions"),
                .product(name: "Semantic", package: "swift-semantic-string"),
                .product(name: "ObjCDump", package: "swift-objc-dump"),
            ],
            exclude: [
                "Fixtures/ObjCSection32BitFixture.m",
                "Fixtures/ObjCSection64BitFixture.m",
            ],
            resources: [
                .copy("Fixtures/libObjCSection32BitFixture.dylib"),
                .copy("Fixtures/libObjCSection64BitFixture.dylib"),
            ]
        ),
        .testTarget(
            name: "ObjCSectionCommandTests",
            dependencies: [
                "objc-section",
                "ObjCDeclarationRendering",
                "ObjCOutputTransformer",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "ObjCDiffingTests",
            dependencies: [
                "ObjCDiffing",
                .product(name: "ObjCDump", package: "swift-objc-dump"),
            ]
        ),
        .testTarget(
            name: "ObjCCodeReferencesTests",
            dependencies: [
                "ObjCCodeReferences",
                "MachOKit",
                .product(name: "MachOCodeReferences", package: "MachOKitExtensions"),
                .product(name: "MachOFixtureSupport", package: "MachOKitExtensions"),
            ]
        ),
        .testTarget(
            name: "ObjCTypeIndexingTests",
            dependencies: [
                "ObjCTypeIndexing",
                "ObjCIndexing",
                "ObjCDeclarationRendering",
                "MachOKit",
                .product(name: "MachOKitExtensions", package: "MachOKitExtensions"),
                .product(name: "TypeIndexing", package: "swift-type-indexing", condition: .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "ObjCDeclarationRenderingTests",
            dependencies: [
                "ObjCDeclarationRendering",
                .product(name: "Semantic", package: "swift-semantic-string"),
                .product(name: "ObjCDump", package: "swift-objc-dump"),
            ]
        ),
    ]
)

// MARK: - Upcoming features

// Every Swift target adopts three upcoming features that Swift 7 turns on:
// ExistentialAny, MemberImportVisibility and InferIsolatedConformances.
// MachOSwiftSection's proposal swift6-mode-and-upcoming-features covers the
// MachO packages together.
let upcomingFeatureSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + upcomingFeatureSettings
}

// MARK: - Tuist development workspace

// MachOSwiftSection's Tuist development workspace (its Documentations/Internal/TuistDevelopment.md)
// maps this package's tests with Tuist, which rejects shapes SwiftPM accepts: a test that depends on
// an executable target or on a macro target (Tuist builds a macro as a plugin, so `@testable import`
// of it finds no module), and a test that depends on a target no product contains. Only while Tuist
// resolves the packages, with TUIST_MAPS_LOCAL_PACKAGE_TESTS=1, the first kinds are left out — the
// macro expansion tests then run under `swift test` only — and the last kind gets a library product
// of its own. Nothing changes without the variable.
if Context.environment["TUIST_MAPS_LOCAL_PACKAGE_TESTS"] == "1" {
    let executableOrMacroTargetNames = Set(package.targets.filter { $0.type == .executable || $0.type == .macro }.map(\.name))
    func dependencyName(_ dependency: Target.Dependency) -> String? {
        switch dependency {
        case .targetItem(let name, _), .byNameItem(let name, _):
            return name
        default:
            return nil
        }
    }
    package.targets.removeAll { target in
        target.type == .test && target.dependencies.contains { dependency in
            dependencyName(dependency).map(executableOrMacroTargetNames.contains) ?? false
        }
    }
    let productTargetNames = Set(package.products.flatMap { product in (product as? Product.Library)?.targets ?? [] })
    let testDependencyNames = Set(package.targets.filter { $0.type == .test }.flatMap { $0.dependencies.compactMap(dependencyName) })
    package.products += package.targets
        .filter { target in target.type == .regular && testDependencyNames.contains(target.name) && !productTargetNames.contains(target.name) }
        .map { target in Product.library(name: target.name, targets: [target.name]) }
}
