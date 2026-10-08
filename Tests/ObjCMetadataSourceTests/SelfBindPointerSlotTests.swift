import Testing
import Foundation
import MachOKit
@testable import MachOObjCSection

/// How the fixture's linker writes its fixups.
enum FixupFormat: String, CaseIterable, Sendable, CustomTestStringConvertible {
    /// `LC_DYLD_CHAINED_FIXUPS`, the format of every binary built for
    /// macOS 12 / iOS 15 and later.
    case chainedFixups
    /// The `LC_DYLD_INFO_ONLY` opcode streams of older deployment targets.
    case dyldInfo

    var testDescription: String {
        switch self {
        case .chainedFixups: "chained fixups"
        case .dyldInfo: "dyld info opcodes"
        }
    }

    var linkerArguments: [String] {
        switch self {
        case .chainedFixups: []
        case .dyldInfo: ["-Wl,-no_fixup_chains", "-mmacosx-version-min=11.0"]
        }
    }
}

/// A dylib linked `-interposable` reaches its own exported symbols the way it
/// reaches another library's: through a bind that dyld resolves at load time,
/// to the image itself (`BIND_SPECIAL_DYLIB_SELF`). Apple builds the frameworks
/// of a simulator runtime this way, so in such a file the class list entry, the
/// `isa`, the `superclass` and the category `cls` of every exported class, and
/// the offset pointer of every exported ivar, hold a bind rather than a rebase:
/// 1,586 of the 5,017 class list entries of the iOS 18.5 simulator's UIKitCore.
///
/// The file readers took every pointer slot for a rebase. A self-bound class
/// list entry was dropped or read from the wrong place, and the reads that
/// follow a class's own pointers stopped at the first self-bind, so a Swift
/// subclass of `UIDocument` lost the instance size its fields start at.
@Suite("Pointer slots bound to the image's own symbols")
struct SelfBindPointerSlotTests {
    @Test("The class list reads every class the image defines", arguments: FixupFormat.allCases)
    func classListReadsEveryClass(format: FixupFormat) throws {
        let machO = try SelfBindFixture.machOFile(format: format)
        let classes = try #require(machO.objc.classes64, "the fixture has no class list")
        let classNames = classes.map { $0.classROData(in: machO)?.name(in: machO) ?? "<unreadable>" }
        #expect(classNames.sorted() == ["SelfBindBase", "SelfBindChild", "SelfBindHidden"])
    }

    @Test("A self-bound class reads its instance size", arguments: FixupFormat.allCases)
    func selfBoundClassReadsItsInstanceSize(format: FixupFormat) throws {
        let machO = try SelfBindFixture.machOFile(format: format)
        let childData = try #require(try SelfBindFixture.classData(named: "SelfBindChild", in: machO))
        // isa, `long baseField`, `long childField`, `char tail[20]`.
        #expect(childData.layout.instanceSize == 44)
    }

    @Test("A superclass in the same image resolves to its class", arguments: FixupFormat.allCases)
    func superclassInTheSameImageResolves(format: FixupFormat) throws {
        let machO = try SelfBindFixture.machOFile(format: format)
        let child = try SelfBindFixture.objCClass(named: "SelfBindChild", in: machO)
        let (superclassImage, superclass) = try #require(child.superClass(in: machO))
        #expect(superclass.classROData(in: superclassImage)?.name(in: superclassImage) == "SelfBindBase")
    }

    @Test("A class resolves its metaclass", arguments: FixupFormat.allCases)
    func classResolvesItsMetaclass(format: FixupFormat) throws {
        let machO = try SelfBindFixture.machOFile(format: format)
        let child = try SelfBindFixture.objCClass(named: "SelfBindChild", in: machO)
        let (metaclassImage, metaclass) = try #require(child.metaClass(in: machO))
        let metaclassData = try #require(metaclass.classROData(in: metaclassImage))
        #expect(metaclassData.isMetaClass)
        #expect(metaclassData.name(in: metaclassImage) == "SelfBindChild")
    }

    @Test("An exported ivar reads its offset", arguments: FixupFormat.allCases)
    func exportedIvarReadsItsOffset(format: FixupFormat) throws {
        let machO = try SelfBindFixture.machOFile(format: format)
        let childData = try #require(try SelfBindFixture.classData(named: "SelfBindChild", in: machO))
        let ivars = try #require(childData.ivarList(in: machO)?.ivars(in: machO))
        let offsetsByName = Dictionary(uniqueKeysWithValues: ivars.map { ($0.name(in: machO) ?? "<unnamed>", $0.offset(in: machO)) })
        #expect(offsetsByName == ["childField": 16, "tail": 24])
    }

    @Test("A category resolves the class it extends in the same image", arguments: FixupFormat.allCases)
    func categoryResolvesItsClass(format: FixupFormat) throws {
        let machO = try SelfBindFixture.machOFile(format: format)
        let category = try #require(machO.objc.categories64?.first, "the fixture has no category")
        let (classImage, extendedClass) = try #require(category.class(in: machO))
        #expect(extendedClass.classROData(in: classImage)?.name(in: classImage) == "SelfBindBase")
    }

    @Test("A superclass in another image is named", arguments: FixupFormat.allCases)
    func superclassInAnotherImageIsNamed(format: FixupFormat) throws {
        let machO = try SelfBindFixture.machOFile(format: format)
        let base = try SelfBindFixture.objCClass(named: "SelfBindBase", in: machO)
        #expect(base.superClassName(in: machO) == "NSObject")
    }
}

/// The class a Swift type in the iOS 18.5 simulator's SwiftUI subclasses
/// (`PlatformDocument: UIDocument`), read from the runtime's UIKitCore file.
/// The simulator runtime is not on every machine, so the suite skips without
/// it.
@Suite(
    "A simulator runtime's self-bound classes",
    .enabled(if: SimulatorRuntimeUIKitCore.path != nil)
)
struct SimulatorRuntimeSelfBindTests {
    @Test("UIDocument reads its instance size from the iOS 18.5 simulator's UIKitCore")
    func documentInstanceSize() throws {
        let path = try #require(SimulatorRuntimeUIKitCore.path)
        let machO = try SelfBindFixture.loadMachOFile(at: URL(fileURLWithPath: path), cpuType: .arm64)
        let documentData = try #require(try SelfBindFixture.classData(named: "UIDocument", in: machO))
        // `class_ro_t.instanceSize` of `_OBJC_CLASS_$_UIDocument`, read with
        // xxd at the target of its `data` rebase.
        #expect(documentData.layout.instanceSize == 0xc4)
    }
}

enum SimulatorRuntimeUIKitCore {
    static let path: String? = {
        let volumesDirectory = "/Library/Developer/CoreSimulator/Volumes"
        let runtimeSuffix = "Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.5.simruntime/Contents/Resources/RuntimeRoot/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore"
        let volumeNames = (try? FileManager.default.contentsOfDirectory(atPath: volumesDirectory)) ?? []
        return volumeNames.sorted()
            .map { "\(volumesDirectory)/\($0)/\(runtimeSuffix)" }
            .first { FileManager.default.fileExists(atPath: $0) }
    }()
}

/// Two exported classes, one hidden class and a category, compiled once per
/// fixup format into a dylib linked `-interposable`.
enum SelfBindFixture {
    static let source = """
    #import <Foundation/Foundation.h>

    // Exported: `-interposable` binds every pointer to these to the image itself.
    __attribute__((visibility("default")))
    @interface SelfBindBase : NSObject {
        long baseField;
    }
    @end
    @implementation SelfBindBase
    @end

    __attribute__((visibility("default")))
    @interface SelfBindChild : SelfBindBase {
        long childField;
        char tail[20];
    }
    @end
    @implementation SelfBindChild
    @end

    // Hidden: nothing can interpose it, so its pointers stay rebases.
    __attribute__((visibility("hidden")))
    @interface SelfBindHidden : SelfBindBase
    @end
    @implementation SelfBindHidden
    @end

    @interface SelfBindBase (SelfBindCategory)
    - (void)categoryMethod;
    @end
    @implementation SelfBindBase (SelfBindCategory)
    - (void)categoryMethod {}
    @end
    """

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

    private struct CompilationError: Swift.Error, CustomStringConvertible {
        let diagnostics: String
        var description: String { "self-bind fixture compilation failed:\n\(diagnostics)" }
    }

    private static func compile(format: FixupFormat) -> Result<URL, Swift.Error> {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("SelfBindFixture-\(format.rawValue)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = WorkingDirectoryCleanup.registration
            WorkingDirectoryCleanup.directories.append(workingDirectory)

            let sourceURL = workingDirectory.appendingPathComponent("Fixture.m")
            let libraryURL = workingDirectory.appendingPathComponent("libSelfBindFixture.dylib")
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            // The linker merges a category into its class when both live in
            // the image; keeping it apart keeps its `cls` slot.
            process.arguments = [
                "clang", "-dynamiclib", "-fobjc-arc", "-framework", "Foundation",
                "-Wl,-interposable", "-Wl,-no_objc_category_merging",
            ] + format.linkerArguments + [sourceURL.path, "-o", libraryURL.path]
            let standardErrorPipe = Pipe()
            process.standardError = standardErrorPipe
            try process.run()
            // Drain BEFORE waitUntilExit, or a long diagnostic deadlocks both sides.
            let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw CompilationError(diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
            }
            return libraryURL
        }
    }

    /// Compiled once per process.
    private static let chainedFixupsCompilation = compile(format: .chainedFixups)
    private static let dyldInfoCompilation = compile(format: .dyldInfo)

    static func machOFile(format: FixupFormat) throws -> MachOFile {
        let libraryURL = switch format {
        case .chainedFixups: try chainedFixupsCompilation.get()
        case .dyldInfo: try dyldInfoCompilation.get()
        }
        let machO = try loadMachOFile(at: libraryURL, cpuType: nil)
        try requireSelfBoundClassListEntry(in: machO, format: format)
        return machO
    }

    static func loadMachOFile(at url: URL, cpuType: CPUType?) throws -> MachOFile {
        switch try MachOKit.loadFromFile(url: url) {
        case .machO(let thinFile):
            return thinFile
        case .fat(let fatFile):
            let slices = try fatFile.machOFiles()
            guard let cpuType else {
                return try #require(slices.first, "\(url.lastPathComponent) has no slice")
            }
            return try #require(slices.first { $0.header.cpuType == cpuType }, "\(url.lastPathComponent) has no \(cpuType) slice")
        }
    }

    /// The premise every test stands on, checked through MachOKit alone: the
    /// linker did bind the class list entry of `SelfBindChild` to the image
    /// itself.
    private static func requireSelfBoundClassListEntry(in machO: MachOFile, format: FixupFormat) throws {
        let symbolName = "_OBJC_CLASS_$_SelfBindChild"
        switch format {
        case .chainedFixups:
            let fixups = try #require(machO.dyldChainedFixups, "the fixture has no chained fixups")
            let classList = try #require(machO.sections64.first { $0.sectionName == "__objc_classlist" })
            let selfBound = stride(from: classList.offset, to: classList.offset + classList.size, by: 8).contains { slotOffset in
                guard let (chainedImport, _) = machO.resolveBind(at: UInt64(slotOffset)) else { return false }
                return chainedImport.info.libraryOrdinalType == .dylib_self
                    && fixups.symbolName(for: chainedImport.info.nameOffset) == symbolName
            }
            try #require(selfBound, "the class list does not bind \(symbolName) to the image itself")
        case .dyldInfo:
            try #require(machO.dyldChainedFixups == nil, "the fixture was linked with chained fixups")
            let selfBound = machO.bindingSymbols.contains { $0.bindSpecial == .dylib_self && $0.symbolName == symbolName }
            try #require(selfBound, "no bind opcode binds \(symbolName) to the image itself")
        }
    }

    static func objCClass(named className: String, in machO: MachOFile) throws -> ObjCClass64 {
        let classes = try #require(machO.objc.classes64, "the image has no class list")
        return try #require(
            classes.first { $0.classROData(in: machO)?.name(in: machO) == className },
            "the class list does not read \(className)"
        )
    }

    static func classData(named className: String, in machO: MachOFile) throws -> ObjCClassROData64? {
        try objCClass(named: className, in: machO).classROData(in: machO)
    }
}
