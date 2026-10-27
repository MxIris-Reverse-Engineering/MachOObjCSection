import Testing
import Foundation
import MachO
import MachOKit
import MachOObjCSection
import ObjCIndexing
import ObjCMetadataSource

/// Fixtures for the classes a host supplies to `ObjCInterfaceIndexer`, compiled
/// once per process into a temporary directory.
enum SuppliedClassFixture {
    struct CompilationError: Swift.Error, CustomStringConvertible {
        let command: [String]
        let diagnostics: String
        var description: String { "\(command.joined(separator: " ")) failed:\n\(diagnostics)" }
    }

    private enum WorkingDirectoryCleanup {
        nonisolated(unsafe) static var directories: [URL] = []
        static let registration: Void = {
            atexit {
                for directory in WorkingDirectoryCleanup.directories {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
        }()
    }

    static func makeWorkingDirectory(named name: String) throws -> URL {
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        _ = WorkingDirectoryCleanup.registration
        WorkingDirectoryCleanup.directories.append(workingDirectory)
        return workingDirectory
    }

    static func run(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        let standardErrorPipe = Pipe()
        process.standardError = standardErrorPipe
        try process.run()
        // Drain BEFORE waitUntilExit, or a long diagnostic deadlocks both sides.
        let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CompilationError(command: arguments, diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
        }
    }

    static func loadMachOFile(at url: URL) throws -> MachOFile {
        switch try MachOKit.loadFromFile(url: url) {
        case .machO(let machO):
            return machO
        case .fat(let fatFile):
            return try #require(try fatFile.machOFiles().first, "\(url.lastPathComponent) has no slice")
        }
    }

    /// The file offset of the symbol named `name`, the offset convention of a
    /// standalone binary.
    static func fileOffset(ofSymbolNamed name: String, in machO: MachOFile) throws -> Int {
        let symbol = try #require(machO.symbols.first { $0.name == name }, "\(machO.imagePath) has no symbol \(name)")
        return Int(try #require(machO.fileOffset(of: UInt64(symbol.offset)), "\(name) lies in no segment"))
    }

    /// The image `handle` loaded, and the offset of its symbol `name` from the
    /// image's header, the offset convention of a `MachOImage`.
    static func imageOffset(ofSymbolNamed name: String, handle: UnsafeMutableRawPointer) throws -> (image: MachOImage, offset: Int) {
        let symbolPointer = try #require(dlsym(handle, name), "no symbol \(name)")
        var symbolInfo = Dl_info()
        try #require(dladdr(symbolPointer, &symbolInfo) != 0, "no image holds \(name)")
        let header = try #require(symbolInfo.dli_fbase)
        let image = MachOImage(ptr: header.assumingMemoryBound(to: mach_header.self))
        return (image, Int(bitPattern: symbolPointer) - Int(bitPattern: header))
    }
}

// MARK: - A Generic Class's Template

/// A `class_ro_t` written out by hand the way Swift emits a generic class's
/// template: no name, and an ivar whose offset slot is null — the runtime
/// fills both for each specialization. Next to it, the metaclass's, with one
/// class method.
enum TemplateReadOnlyDataFixture {
    static let source = """
    #include <stdint.h>

    struct Method { const char *name; const char *types; const void *implementation; };
    struct MethodList { uint32_t entrySizeAndFlags; uint32_t count; struct Method methods[1]; };
    struct Ivar { int32_t *offset; const char *name; const char *type; uint32_t alignment; uint32_t size; };
    struct IvarList { uint32_t entrySize; uint32_t count; struct Ivar ivars[2]; };
    struct ReadOnlyData {
        uint32_t flags, instanceStart, instanceSize, reserved;
        const void *ivarLayout;
        const char *name;
        const void *baseMethods, *baseProtocols, *ivars, *weakIvarLayout, *baseProperties;
    };

    static void instanceMethodImplementation(void) {}
    static void classMethodImplementation(void) {}
    static int32_t knownFieldOffset = 8;

    static struct MethodList instanceMethods = { 24, 1, { { "templateMethod", "v16@0:8", (const void *)instanceMethodImplementation } } };
    static struct MethodList classMethods = { 24, 1, { { "templateClassMethod", "v16@0:8", (const void *)classMethodImplementation } } };
    static struct IvarList ivars = { 32, 2, {
        { &knownFieldOffset, "knownField", "q", 3, 8 },
        { 0, "unknownField", "q", 3, 8 },
    } };

    __attribute__((visibility("default")))
    struct ReadOnlyData TemplateClassReadOnlyData = { 0, 8, 24, 0, 0, 0, &instanceMethods, 0, &ivars, 0, 0 };

    __attribute__((visibility("default")))
    struct ReadOnlyData TemplateMetaclassReadOnlyData = { 1, 40, 40, 0, 0, 0, &classMethods, 0, 0, 0, 0 };
    """

    static let readOnlyDataSymbolName = "TemplateClassReadOnlyData"
    static let metaclassReadOnlyDataSymbolName = "TemplateMetaclassReadOnlyData"

    private static let compilation = Result { () throws -> URL in
        let workingDirectory = try SuppliedClassFixture.makeWorkingDirectory(named: "TemplateReadOnlyDataFixture")
        let sourceURL = workingDirectory.appendingPathComponent("Fixture.c")
        let libraryURL = workingDirectory.appendingPathComponent("libTemplateReadOnlyDataFixture.dylib")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)
        try SuppliedClassFixture.run(["clang", "-dynamiclib", sourceURL.path, "-o", libraryURL.path])
        return libraryURL
    }

    static func libraryURL() throws -> URL {
        try compilation.get()
    }

    /// The template as a host supplies it, with offsets in `machO`'s
    /// convention.
    static func suppliedClass(readOnlyDataOffset: Int, metaclassReadOnlyDataOffset: Int) -> ObjCSuppliedClass {
        ObjCSuppliedClass(
            name: "TemplateFixture.TemplateClass<A>",
            superClassName: "NSObject",
            readOnlyDataOffset: readOnlyDataOffset,
            metaclassReadOnlyDataOffset: metaclassReadOnlyDataOffset,
            kind: .genericSwiftClass
        )
    }
}

// MARK: - A Category on a Class Stub

/// A Swift class whose superclass lives in a module built for library
/// evolution has no class object: the image registers it through a class stub
/// in `__objc_stublist`, and points the category its `@objc` extension
/// becomes at that stub (`__objc_catlist2`).
enum StubCategoryFixture {
    static let baseSource = """
    import Foundation

    open class ResilientBase: NSObject {
        @objc open func baseMethod() {}
    }
    """

    static let source = """
    import Foundation
    import ResilientBase

    @objc(StubCategoryFixtureProtocol)
    public protocol StubCategoryFixtureProtocol {
        func protocolMethod()
    }

    public final class Widget: ResilientBase {
        @objc public var size: Int = 0
        @objc public func ownMethod() {}
    }

    extension Widget: StubCategoryFixtureProtocol {
        @objc public func extensionMethod() {}
        public func protocolMethod() {}
    }
    """

    /// The name a host gives the class, spelled unlike the Objective-C name
    /// the image's symbols carry.
    static let suppliedClassName = "StubCategoryFixture.Widget"

    struct Libraries {
        let unstrippedURL: URL
        let strippedURL: URL
    }

    private static let compilation = Result { () throws -> Libraries in
        let workingDirectory = try SuppliedClassFixture.makeWorkingDirectory(named: "StubCategoryFixture")
        let baseSourceURL = workingDirectory.appendingPathComponent("ResilientBase.swift")
        let sourceURL = workingDirectory.appendingPathComponent("StubCategoryFixture.swift")
        let unstrippedURL = workingDirectory.appendingPathComponent("libStubCategoryFixture.dylib")
        let strippedURL = workingDirectory.appendingPathComponent("libStubCategoryFixtureStripped.dylib")
        try baseSource.write(to: baseSourceURL, atomically: true, encoding: .utf8)
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)

        try SuppliedClassFixture.run([
            "swiftc", "-emit-library", "-enable-library-evolution",
            "-module-name", "ResilientBase",
            "-emit-module", "-emit-module-path", workingDirectory.appendingPathComponent("ResilientBase.swiftmodule").path,
            "-Xlinker", "-install_name", "-Xlinker", "@rpath/libResilientBase.dylib",
            baseSourceURL.path, "-o", workingDirectory.appendingPathComponent("libResilientBase.dylib").path,
        ])
        try SuppliedClassFixture.run([
            "swiftc", "-emit-library",
            "-module-name", "StubCategoryFixture",
            "-I", workingDirectory.path, "-L", workingDirectory.path, "-lResilientBase",
            "-Xlinker", "-rpath", "-Xlinker", workingDirectory.path,
            sourceURL.path, "-o", unstrippedURL.path,
        ])
        // Takes the local symbols, the category's among them, as a release
        // build's strip does; leaves every section where it was.
        try SuppliedClassFixture.run(["strip", "-x", unstrippedURL.path, "-o", strippedURL.path])
        return Libraries(unstrippedURL: unstrippedURL, strippedURL: strippedURL)
    }

    static func libraries() throws -> Libraries {
        try compilation.get()
    }

    /// `Widget` as a host supplies it, its offsets read off the unstripped
    /// image's symbols: the class's and metaclass's `class_ro_t`
    /// (`_DATA_` and `_METACLASS_DATA_` followed by the class's Objective-C
    /// name), and the stub's address point (`CMs`). Stripping leaves the
    /// offsets as they are.
    static func suppliedClass(includingStub: Bool = true) throws -> ObjCSuppliedClass {
        let machO = try SuppliedClassFixture.loadMachOFile(at: try libraries().unstrippedURL)
        let symbolNames = machO.symbols.map(\.name)
        let readOnlyDataSymbolName = try #require(symbolNames.first { $0.hasPrefix("__DATA__Tt") && $0.hasSuffix("Widget") })
        let metaclassReadOnlyDataSymbolName = try #require(symbolNames.first { $0.hasPrefix("__METACLASS_DATA__Tt") && $0.hasSuffix("Widget") })
        let stubSymbolName = try #require(symbolNames.first { $0.hasPrefix("_$s") && $0.hasSuffix("WidgetCMs") })
        return ObjCSuppliedClass(
            name: suppliedClassName,
            superClassName: "ResilientBase.ResilientBase",
            readOnlyDataOffset: try SuppliedClassFixture.fileOffset(ofSymbolNamed: readOnlyDataSymbolName, in: machO),
            metaclassReadOnlyDataOffset: try SuppliedClassFixture.fileOffset(ofSymbolNamed: metaclassReadOnlyDataSymbolName, in: machO),
            classStubOffset: includingStub ? try SuppliedClassFixture.fileOffset(ofSymbolNamed: stubSymbolName, in: machO) : nil,
            kind: .swiftClassWithResilientAncestry
        )
    }
}

// MARK: - Xcode Service

/// Two classes of Xcode 27.2's `Xcode Service` that `__objc_classlist` lacks,
/// with the offsets MachOSwiftSection reads off their Swift metadata, checked
/// against `dyld_info -fixups`. The binary is thin arm64, and every segment's
/// file offset is its address less 0x100000000. The reverse-engineering volume
/// holding it is not on every machine.
enum XcodeServiceFixture {
    static let path = "/Volumes/RE/Xcode/27.2/Developer/Library/Xcode/Agents/Xcode Service.app/Contents/MacOS/Xcode Service"

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// A generic class, `MenuBarPanelWindow<A: View>: NSPanel`: a template in
    /// its generic metadata pattern, with a null name and a relative method
    /// list of nine methods; the metaclass has none.
    static let menuBarPanelWindow = ObjCSuppliedClass(
        name: "Xcode_Service.MenuBarPanelWindow<A>",
        superClassName: "NSPanel",
        readOnlyDataOffset: 0x711F8,
        metaclassReadOnlyDataOffset: 0x71240,
        kind: .genericSwiftClass
    )

    /// `MenuBarLabelHostingView: NSHostingView<MenuBarLabel>`, registered
    /// through `__objc_stublist` (the stub list entry at 0x7DF30 points at the
    /// stub).
    static let menuBarLabelHostingView = ObjCSuppliedClass(
        name: "_TtC13Xcode_Service23MenuBarLabelHostingView",
        superClassName: "_TtGC7SwiftUI13NSHostingViewV13Xcode_Service12MenuBarLabel_",
        readOnlyDataOffset: 0x7B248,
        metaclassReadOnlyDataOffset: 0x78CD0,
        classStubOffset: 0x7CF40,
        kind: .swiftClassWithResilientAncestry
    )

    static func machOFile() throws -> MachOFile {
        try SuppliedClassFixture.loadMachOFile(at: URL(fileURLWithPath: path))
    }
}
