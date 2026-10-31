import Testing
import Foundation
import MachOKit
import MachOObjCSection
import ObjCIndexing
import ObjCMetadataSource

/// The export verdicts `ObjCInterfaceIndexer.prepare()` keeps, and what its
/// two queries answer for names it holds no verdict for.
@Suite("Export verdicts kept by the indexer")
struct ExportedDeclarationsIndexingTests {
    /// Foundation, indexed once per process.
    private actor FoundationFixture {
        static let shared = FoundationFixture()

        private var cached: (indexer: ObjCInterfaceIndexer<MachOImage>, machO: MachOImage)?

        func load() async throws -> (indexer: ObjCInterfaceIndexer<MachOImage>, machO: MachOImage) {
            if let cached { return cached }
            let machO = try #require(MachOImage(name: "Foundation"), "Foundation is not loaded in the test process")
            let indexer = ObjCInterfaceIndexer(machO: machO, imagePath: machO.imagePath)
            try await indexer.prepare()
            cached = (indexer, machO)
            return (indexer, machO)
        }
    }

    private static func preparedIndexer<MachO: ObjCMetadataSource>(of machO: MachO) async throws -> ObjCInterfaceIndexer<MachO> {
        let indexer = ObjCInterfaceIndexer(machO: machO, imagePath: machO.imagePath)
        try await indexer.prepare()
        return indexer
    }

    /// Each listed class answers what the fixture says; nothing else is
    /// listed.
    private static func expectVerdicts<MachO: ObjCMetadataSource>(
        of indexer: ObjCInterfaceIndexer<MachO>,
        equal expectedVerdicts: [String: ExportedDeclarationsFixture.Verdict]
    ) {
        #expect(Set(indexer.classNames) == Set(expectedVerdicts.keys))
        for (className, verdict) in expectedVerdicts {
            #expect(indexer.exportStatus(ofClassNamed: className) == verdict.classStatus, "\(className)")
        }
    }

    // MARK: - Fixtures

    @Test("The Swift image's verdicts, read from the file")
    func swiftImageInFile() async throws {
        let indexer = try await Self.preparedIndexer(of: try ExportedDeclarationsFixture.swiftLibraryFile())
        Self.expectVerdicts(of: indexer, equal: ExportedDeclarationsFixture.swiftImageVerdicts)
    }

    @Test("The Swift image's verdicts, loaded")
    func swiftImageLoaded() async throws {
        let indexer = try await Self.preparedIndexer(of: try ExportedDeclarationsFixture.swiftLibraryImage())
        Self.expectVerdicts(of: indexer, equal: ExportedDeclarationsFixture.swiftImageVerdicts)
    }

    @Test("The Objective-C image's verdicts, read from the file")
    func objectiveCImageInFile() async throws {
        let indexer = try await Self.preparedIndexer(of: try ExportedDeclarationsFixture.objectiveCLibraryFile())
        Self.expectVerdicts(of: indexer, equal: ExportedDeclarationsFixture.objectiveCImageVerdicts)
    }

    @Test("The Objective-C image's verdicts, loaded")
    func objectiveCImageLoaded() async throws {
        let indexer = try await Self.preparedIndexer(of: try ExportedDeclarationsFixture.objectiveCLibraryImage())
        Self.expectVerdicts(of: indexer, equal: ExportedDeclarationsFixture.objectiveCImageVerdicts)
    }

    /// The categories' target `NSObject` is another image's class: it has no
    /// verdict here, which is not the same as being unexported.
    @Test("A class of another image has no verdict")
    func classOfAnotherImageHasNoVerdict() async throws {
        let indexer = try await Self.preparedIndexer(of: try ExportedDeclarationsFixture.objectiveCLibraryFile())
        #expect(indexer.exportStatus(ofClassNamed: "NSObject") == nil)
        #expect(indexer.exportStatus(ofClassNamed: "ZZZNoSuchClassCouldPossiblyExist") == nil)
    }

    /// A supplied class has no class object to judge.
    @Test("A supplied class has no verdict")
    func suppliedClassHasNoVerdict() async throws {
        let machO = try SuppliedClassFixture.loadMachOFile(at: try TemplateReadOnlyDataFixture.libraryURL())
        let suppliedClass = TemplateReadOnlyDataFixture.suppliedClass(
            readOnlyDataOffset: try SuppliedClassFixture.fileOffset(ofSymbolNamed: "_" + TemplateReadOnlyDataFixture.readOnlyDataSymbolName, in: machO),
            metaclassReadOnlyDataOffset: try SuppliedClassFixture.fileOffset(ofSymbolNamed: "_" + TemplateReadOnlyDataFixture.metaclassReadOnlyDataSymbolName, in: machO)
        )
        let indexer = ObjCInterfaceIndexer(machO: machO, imagePath: machO.imagePath, suppliedClasses: [suppliedClass])
        try await indexer.prepare()
        try #require(indexer.suppliedClassGroup(forName: suppliedClass.name) != nil)
        #expect(indexer.exportStatus(ofClassNamed: suppliedClass.name) == nil)
    }

    // MARK: - Foundation

    /// Over a real framework, every listed class keeps the verdict the fact
    /// layer reads off its record — so the indexer does not key a verdict
    /// under another class's name or drop one along the way.
    @Test("Every class of Foundation keeps the verdict its record reads")
    func foundationKeepsEveryRecordsVerdict() async throws {
        let (indexer, machO) = try await FoundationFixture.shared.load()
        let recordVerdicts = ExportedDeclarationsVerdictTests.verdicts(in: machO)

        var notExportedClassCount = 0
        for (className, verdict) in recordVerdicts {
            #expect(indexer.exportStatus(ofClassNamed: className) == verdict.classStatus, "\(className)")
            if verdict.classStatus == .notExported { notExportedClassCount += 1 }
        }

        #expect(indexer.exportStatus(ofClassNamed: "NSString") == .exported)
        #expect(indexer.exportStatus(ofClassNamed: "NSArray") == nil, "NSArray is CoreFoundation's to export")
        #expect(notExportedClassCount > 0)
    }
}
