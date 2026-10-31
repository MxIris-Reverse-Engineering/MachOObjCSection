import Testing
import Foundation
import MachOKit
import MachOObjCSection
import ObjCMetadataSource

/// The export verdict on every class of the compiled fixtures and on each of
/// its ivars, read the way the fact layer reads them, in both modes.
///
/// Before verdicts were read by location, `PublicSwiftRoot` and the
/// `publicValue` ivars of both Swift classes read `notExported`: the lookup
/// went by the Objective-C symbol names, and Swift emits neither an
/// `_OBJC_CLASS_$_` symbol for a class without an Objective-C ancestor nor an
/// `_OBJC_IVAR_$_` symbol for any ivar.
@Suite("Export verdicts on compiled fixtures")
struct ExportedDeclarationsVerdictTests {
    private typealias SwiftClassName = ExportedDeclarationsFixture.SwiftClassName
    private typealias Verdict = ExportedDeclarationsFixture.Verdict

    /// Every class `machO` lists, by name, with its verdicts.
    static func verdicts<MachO: ObjCMetadataSource>(in machO: MachO) -> [String: ExportedDeclarationsFixture.Verdict] {
        let exportIndex = ObjCExportIndex(machO: machO)
        let classRecords = (machO.objc.classes64 ?? []) as [any ObjCClassProtocol]
            + ((machO.objc.classes32 ?? []) as [any ObjCClassProtocol])
        var verdicts: [String: Verdict] = [:]
        for classRecord in classRecords {
            guard let className = machO.objcClassName(of: classRecord) else { continue }
            verdicts[className] = Verdict(
                classStatus: exportIndex.exportStatus(ofClassObjectAt: classRecord.offset),
                ivarStatusByName: machO.objcIvarOffsetVariableOffsets(of: classRecord)
                    .mapValues(exportIndex.exportStatus(ofIvarOffsetVariableAt:))
            )
        }
        return verdicts
    }

    // MARK: - Premises

    /// What makes the Swift image worth testing: its public root class has no
    /// Objective-C symbol at all, only its type metadata symbol, and its
    /// public ivar's offset variable is a field offset. Were Swift ever to
    /// emit the Objective-C spellings, the verdicts below would stop proving
    /// anything about the location lookup.
    @Test("The Swift image publishes its classes and ivars under Swift symbols")
    func swiftImageUsesSwiftSpellings() throws {
        let exportedNames = Set(try ExportedDeclarationsFixture.swiftLibraryFile().exportedSymbols.map(\.name))
        #expect(!exportedNames.contains("_OBJC_CLASS_$_" + SwiftClassName.publicSwiftRoot))
        #expect(exportedNames.contains("_$s27ExportedDeclarationsFixture15PublicSwiftRootCN"))
        #expect(exportedNames.contains("_OBJC_CLASS_$_" + SwiftClassName.publicObjCSubclass))
        #expect(!exportedNames.contains { $0.hasPrefix("_OBJC_IVAR_$_") })
        #expect(exportedNames.contains("_$s27ExportedDeclarationsFixture15PublicSwiftRootC11publicValueSivpWvd"))
    }

    // MARK: - Verdicts

    @Test("Every class and ivar of the Swift image, read from the file")
    func swiftImageInFile() throws {
        let verdicts = Self.verdicts(in: try ExportedDeclarationsFixture.swiftLibraryFile())
        #expect(verdicts == ExportedDeclarationsFixture.swiftImageVerdicts)
    }

    @Test("Every class and ivar of the Swift image, loaded")
    func swiftImageLoaded() throws {
        let verdicts = Self.verdicts(in: try ExportedDeclarationsFixture.swiftLibraryImage())
        #expect(verdicts == ExportedDeclarationsFixture.swiftImageVerdicts)
    }

    @Test("Every class and ivar of the Objective-C image, read from the file")
    func objectiveCImageInFile() throws {
        let verdicts = Self.verdicts(in: try ExportedDeclarationsFixture.objectiveCLibraryFile())
        #expect(verdicts == ExportedDeclarationsFixture.objectiveCImageVerdicts)
    }

    @Test("Every class and ivar of the Objective-C image, loaded")
    func objectiveCImageLoaded() throws {
        let verdicts = Self.verdicts(in: try ExportedDeclarationsFixture.objectiveCLibraryImage())
        #expect(verdicts == ExportedDeclarationsFixture.objectiveCImageVerdicts)
    }
}
