import Testing
import Foundation
import MachOKit
import MachOObjCSection
import ObjCDeclarationRendering
import ObjCDump
import Semantic
@testable import ObjCIndexing

/// Indexes an image that is already loaded into this very process, so the
/// tests need no fixture binary on disk.
@Suite("ObjC interface indexing")
struct ObjCIndexingTests {
    /// Builds and prepares an indexer over Foundation, collecting every event
    /// it emits along the way.
    private static func makeIndexer(
        collectingInto collector: EventCollector? = nil
    ) async throws -> ObjCInterfaceIndexer {
        let machO = try #require(MachOImage(name: "Foundation"))
        var handler: (@Sendable (ObjCIndexingEvent) -> Void)?
        if let collector {
            handler = { event in collector.record(event) }
        }
        let indexer = ObjCInterfaceIndexer(
            machO: machO,
            imagePath: machO.imagePath,
            eventHandler: handler
        )
        try await indexer.prepare()
        return indexer
    }

    /// Event sink shared with the indexer's `@Sendable` handler.
    final class EventCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [ObjCIndexingEvent] = []

        func record(_ event: ObjCIndexingEvent) {
            lock.lock()
            defer { lock.unlock() }
            storage.append(event)
        }

        var events: [ObjCIndexingEvent] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    @Test("Indexes classes, protocols and categories from a real image")
    func indexesTopLevelDeclarations() async throws {
        let indexer = try await Self.makeIndexer()

        #expect(indexer.classNames.contains("NSString"))
        #expect(indexer.protocolNames.contains("NSCopying"))
        #expect(!indexer.categoryNames.isEmpty)
    }

    @Test("Class groups carry the superclass chain, class first")
    func classGroupCarriesSuperclassChain() async throws {
        let indexer = try await Self.makeIndexer()

        let group = try #require(indexer.classGroup(forName: "NSMutableString"))
        #expect(group.info.first?.name == "NSMutableString")
        // NSMutableString inherits from NSString.
        #expect(group.info.dropFirst().contains { $0.name == "NSString" })
    }

    @Test("Reverse table records subclasses")
    func reverseTableRecordsSubclasses() async throws {
        let indexer = try await Self.makeIndexer()

        let subclasses = indexer.subclasses(of: "NSString")
        #expect(subclasses.contains { $0.className == "NSMutableString" })
    }

    @Test("Reverse table records protocol conformances")
    func reverseTableRecordsConformances() async throws {
        let indexer = try await Self.makeIndexer()

        let conformers = indexer.conformingClasses(toProtocol: "NSCopying")
        #expect(!conformers.isEmpty)
    }

    @Test("C struct definitions are harvested and renderable")
    func harvestsStructDefinitions() async throws {
        let machO = try #require(MachOImage(name: "Foundation"))
        let indexer = try await Self.makeIndexer()

        let structName = try #require(indexer.structNames.first)
        #expect(indexer.containsStruct(named: structName))

        let context = ObjCRenderingContext(machO: machO)
        let rendered = try #require(indexer.structSemanticString(forName: structName, context: context))
        #expect(rendered.string.hasPrefix("struct "))
    }

    @Test("Emits progress and relationship events on one channel")
    func emitsUnifiedEvents() async throws {
        let collector = EventCollector()
        _ = try await Self.makeIndexer(collectingInto: collector)

        let events = collector.events
        #expect(!events.isEmpty)

        var seenPhases: Set<ObjCIndexingEvent.Phase> = []
        var sawSubclass = false
        var sawConformance = false
        for event in events {
            switch event {
            case .progress(let phase, _, _, _):
                seenPhases.insert(phase)
            case .subclassIndexed:
                sawSubclass = true
            case .conformanceIndexed, .categoryConformanceIndexed:
                sawConformance = true
            }
        }

        // Both the progress stream and the relationship events must arrive
        // through the single merged handler.
        #expect(seenPhases.contains(.indexingSubclasses))
        #expect(seenPhases.contains(.loadingClasses))
        #expect(sawSubclass)
        #expect(sawConformance)
    }

    @Test("Aggregate indexer fans relationship queries out to sub-indexers")
    func aggregateFansOutToSubIndexers() async throws {
        let machO = try #require(MachOImage(name: "Foundation"))
        let perImage = try await Self.makeIndexer()

        // An aggregate is an indexer that is never `prepare()`d; it only holds
        // sub-indexers.
        let aggregate = ObjCInterfaceIndexer(machO: machO, imagePath: machO.imagePath)
        #expect(aggregate.subclasses(of: "NSString").isEmpty)

        aggregate.addSubIndexer(perImage)
        #expect(aggregate.subclasses(of: "NSString").contains { $0.className == "NSMutableString" })
    }
}
