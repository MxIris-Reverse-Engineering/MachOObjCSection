import Testing
import Foundation
import MachOKit
import MachOObjCSection
import ObjCDump
import ObjCIndexing
import ObjCMetadataSource

/// The classes a host supplies to `ObjCInterfaceIndexer`, for the Swift
/// classes the image keeps no class object for (proposal "host-supplied
/// classes").
@Suite("Supplied classes in the index")
struct SuppliedClassIndexingTests {
    // MARK: - Stand-ins

    /// Foundation's classes have class objects, so a stand-in takes one's
    /// `class_ro_t` and supplies it again under other names; image mode
    /// counts offsets from the image's header.
    @Test("Supplied classes index after the listed ones, in image mode")
    func standInsInImageMode() async throws {
        let image = try #require(MachOImage(name: "Foundation"))
        try await StandInScenario.run(
            machO: image,
            unreadableOffset: -Int(bitPattern: image.ptr)
        ) { objcClass in
            let readOnlyData = try #require(StandInScenario.readOnlyData(of: objcClass, in: image))
            let (metaclassImage, metaclass) = try #require(objcClass.metaClass(in: image))
            let metaclassReadOnlyData = try #require(StandInScenario.readOnlyData(of: metaclass, in: metaclassImage))
            return (readOnlyData.offset, metaclassReadOnlyData.offset)
        }
    }

    /// File mode counts the offsets of an image in a dyld cache from the main
    /// cache's start.
    @Test("Supplied classes index after the listed ones, in a dyld cache file")
    func standInsInDyldCacheFile() async throws {
        let cacheURL = try #require(DyldCache.host?.url)
        let machO = try #require(try DyldCache(url: cacheURL).machOFile(by: .name("Foundation")))
        try await StandInScenario.run(machO: machO, unreadableOffset: -8) { objcClass in
            let readOnlyData = try #require(objcClass.classROData(in: machO))
            let (metaclassImage, metaclass) = try #require(objcClass.metaClass(in: machO))
            let metaclassReadOnlyData = try #require(metaclass.classROData(in: metaclassImage))
            return (readOnlyData.offset, metaclassReadOnlyData.offset)
        }
    }

    // MARK: - A Generic Class's Template

    @Test("A template reads without a name and keeps the ivar of unknown offset, in a file")
    func templateInFile() async throws {
        let machO = try SuppliedClassFixture.loadMachOFile(at: try TemplateReadOnlyDataFixture.libraryURL())
        let suppliedClass = TemplateReadOnlyDataFixture.suppliedClass(
            readOnlyDataOffset: try SuppliedClassFixture.fileOffset(ofSymbolNamed: "_" + TemplateReadOnlyDataFixture.readOnlyDataSymbolName, in: machO),
            metaclassReadOnlyDataOffset: try SuppliedClassFixture.fileOffset(ofSymbolNamed: "_" + TemplateReadOnlyDataFixture.metaclassReadOnlyDataSymbolName, in: machO)
        )
        let indexer = ObjCInterfaceIndexer(machO: machO, imagePath: machO.imagePath, suppliedClasses: [suppliedClass])
        try await indexer.prepare()
        try Self.expectTemplate(in: indexer, suppliedClass: suppliedClass)
    }

    @Test("A template reads without a name and keeps the ivar of unknown offset, in a loaded image")
    func templateInLoadedImage() async throws {
        let libraryURL = try TemplateReadOnlyDataFixture.libraryURL()
        let handle = try #require(dlopen(libraryURL.path, RTLD_NOW))
        defer { dlclose(handle) }
        let (image, readOnlyDataOffset) = try SuppliedClassFixture.imageOffset(ofSymbolNamed: TemplateReadOnlyDataFixture.readOnlyDataSymbolName, handle: handle)
        let (_, metaclassReadOnlyDataOffset) = try SuppliedClassFixture.imageOffset(ofSymbolNamed: TemplateReadOnlyDataFixture.metaclassReadOnlyDataSymbolName, handle: handle)
        let suppliedClass = TemplateReadOnlyDataFixture.suppliedClass(
            readOnlyDataOffset: readOnlyDataOffset,
            metaclassReadOnlyDataOffset: metaclassReadOnlyDataOffset
        )
        let indexer = ObjCInterfaceIndexer(machO: image, imagePath: libraryURL.path, suppliedClasses: [suppliedClass])
        try await indexer.prepare()
        try Self.expectTemplate(in: indexer, suppliedClass: suppliedClass)
    }

    private static func expectTemplate<MachO: ObjCMetadataSource>(
        in indexer: ObjCInterfaceIndexer<MachO>,
        suppliedClass: ObjCSuppliedClass
    ) throws {
        #expect(indexer.classNames == [suppliedClass.name])
        let group = try #require(indexer.suppliedClassGroup(forName: suppliedClass.name))
        let info = try #require(group.info.first)
        #expect(group.info.count == 1)
        #expect(info.name == suppliedClass.name)
        #expect(info.superClassName == "NSObject")
        #expect(info.instanceSize == 24)
        #expect(info.ivars.map(\.name) == ["knownField", "unknownField"])
        #expect(info.ivars.map(\.offset) == [8, 0])
        #expect(group.ivarNamesWithUnknownOffset == ["unknownField"])
        #expect(info.methods.map(\.name) == ["templateMethod"])
        #expect(info.classMethods.map(\.name) == ["templateClassMethod"])
    }

    // MARK: - Categories on a Class Stub

    @Test("A category on a supplied class's stub goes under the supplied name")
    func stubCategoryGoesUnderTheSuppliedName() async throws {
        let machO = try SuppliedClassFixture.loadMachOFile(at: try StubCategoryFixture.libraries().unstrippedURL)
        let suppliedClass = try StubCategoryFixture.suppliedClass()

        // The premises: the image lists no class object for `Widget`, and its
        // one category points at the stub the symbols name.
        #expect((machO.objc.classes64 ?? []).isEmpty)
        let categories = machO.objc.categories2_64 ?? []
        try #require(categories.count == 1, "the category is not on __objc_catlist2")
        #expect(machO.objcCategoryTargetClassStubOffset(of: categories[0]) == suppliedClass.classStubOffset)

        let plainEvents = EventRecorder()
        let plainIndexer = ObjCInterfaceIndexer(machO: machO, imagePath: machO.imagePath, eventHandler: plainEvents.record)
        try await plainIndexer.prepare()
        // Unstripped, the category is named after a local symbol, with the
        // Objective-C name of the class.
        let plainCategoryName = try #require(plainIndexer.categoryNames.first)
        #expect(plainCategoryName.hasPrefix("_Tt"))
        #expect(plainEvents.categoryConformances == [
            .init(targetClassName: String(plainCategoryName.prefix { $0 != "(" }), protocolName: "StubCategoryFixtureProtocol", targetIsSwiftStable: false),
        ])

        let suppliedEvents = EventRecorder()
        let indexer = ObjCInterfaceIndexer(machO: machO, imagePath: machO.imagePath, suppliedClasses: [suppliedClass], eventHandler: suppliedEvents.record)
        try await indexer.prepare()
        let categoryName = try #require(indexer.categoryNames.first)
        #expect(indexer.categoryNames.count == 1)
        #expect(categoryName.hasPrefix(StubCategoryFixture.suppliedClassName + "("))
        let categoryInfo = try #require(indexer.categoryGroup(forName: categoryName)?.info)
        #expect(categoryInfo.className == StubCategoryFixture.suppliedClassName)
        #expect(categoryInfo.methods.map(\.name).contains("extensionMethod"))
        #expect(suppliedEvents.categoryConformances == [
            .init(targetClassName: StubCategoryFixture.suppliedClassName, protocolName: "StubCategoryFixtureProtocol", targetIsSwiftStable: true),
        ])

        let classInfo = try #require(indexer.suppliedClassGroup(forName: StubCategoryFixture.suppliedClassName)?.info.first)
        #expect(classInfo.methods.map(\.name).contains("ownMethod"))
        #expect(!classInfo.methods.map(\.name).contains("extensionMethod"))
    }

    @Test("In a stripped image only the supplied stub finds the category")
    func strippedStubCategory() async throws {
        let machO = try SuppliedClassFixture.loadMachOFile(at: try StubCategoryFixture.libraries().strippedURL)

        let plainIndexer = ObjCInterfaceIndexer(machO: machO, imagePath: machO.imagePath)
        try await plainIndexer.prepare()
        #expect(plainIndexer.categoryNames.isEmpty)

        let indexer = ObjCInterfaceIndexer(machO: machO, imagePath: machO.imagePath, suppliedClasses: [try StubCategoryFixture.suppliedClass()])
        try await indexer.prepare()
        #expect(indexer.categoryNames.count == 1)
        #expect(indexer.categoryNames.first?.hasPrefix(StubCategoryFixture.suppliedClassName + "(") == true)
    }

    @Test("A supplied class without its stub leaves its categories as they were")
    func suppliedClassWithoutStub() async throws {
        let machO = try SuppliedClassFixture.loadMachOFile(at: try StubCategoryFixture.libraries().unstrippedURL)

        let plainIndexer = ObjCInterfaceIndexer(machO: machO, imagePath: machO.imagePath)
        try await plainIndexer.prepare()

        let indexer = ObjCInterfaceIndexer(
            machO: machO,
            imagePath: machO.imagePath,
            suppliedClasses: [try StubCategoryFixture.suppliedClass(includingStub: false)]
        )
        try await indexer.prepare()
        #expect(indexer.categoryNames == plainIndexer.categoryNames)
        #expect(indexer.suppliedClassGroup(forName: StubCategoryFixture.suppliedClassName) != nil)
    }

    // MARK: - Categories on a Class with Generic Ancestry

    /// The class has a stub too, but its category points at the class's
    /// metadata, which names the class: the category goes under that name,
    /// stripped or not, and a class supplied under it needs no stub.
    @Test("A category on a class with generic ancestry goes under the class's runtime name", arguments: [false, true])
    func genericAncestryCategory(stripped: Bool) async throws {
        let libraries = try GenericAncestryCategoryFixture.libraries()
        let machO = try SuppliedClassFixture.loadMachOFile(at: stripped ? libraries.strippedURL : libraries.unstrippedURL)
        let runtimeName = GenericAncestryCategoryFixture.runtimeName

        // The premises: the image lists no class object for `Gadget` and
        // registers its stub, yet the one category is on `__objc_catlist` and
        // points at no stub.
        #expect((machO.objc.classes64 ?? []).isEmpty)
        #expect(machO.sections64.first { $0.sectionName == "__objc_stublist" }?.size == 8)
        #expect((machO.objc.categories2_64 ?? []).isEmpty)
        let categories = machO.objc.categories64 ?? []
        try #require(categories.count == 1, "the category is not on __objc_catlist")
        #expect(machO.objcCategoryTargetClassStubOffset(of: categories[0]) == nil)

        let events = EventRecorder()
        let indexer = ObjCInterfaceIndexer(
            machO: machO,
            imagePath: machO.imagePath,
            suppliedClasses: [try GenericAncestryCategoryFixture.suppliedClass()],
            eventHandler: events.record
        )
        try await indexer.prepare()
        let categoryName = try #require(indexer.categoryNames.first)
        #expect(indexer.categoryNames.count == 1)
        let categoryInfo = try #require(indexer.categoryGroup(forName: categoryName)?.info)
        #expect(categoryInfo.className == runtimeName)
        #expect(categoryInfo.methods.map(\.name).contains("extensionMethod"))
        #expect(events.categoryConformances == [
            .init(targetClassName: runtimeName, protocolName: "GenericAncestryCategoryFixtureProtocol", targetIsSwiftStable: true),
        ])

        let classInfo = try #require(indexer.suppliedClassGroup(forName: runtimeName)?.info.first)
        #expect(classInfo.methods.map(\.name).contains("ownMethod"))
        #expect(!classInfo.methods.map(\.name).contains("extensionMethod"))
    }

    @Test("A class with generic ancestry supplied under another name parts from its category")
    func genericAncestryCategoryUnderAnotherName() async throws {
        let machO = try SuppliedClassFixture.loadMachOFile(at: try GenericAncestryCategoryFixture.libraries().unstrippedURL)
        let suppliedClassName = "GenericAncestryCategoryFixture.Gadget"
        let indexer = ObjCInterfaceIndexer(
            machO: machO,
            imagePath: machO.imagePath,
            suppliedClasses: [try GenericAncestryCategoryFixture.suppliedClass(named: suppliedClassName)]
        )
        try await indexer.prepare()
        #expect(indexer.suppliedClassGroup(forName: suppliedClassName) != nil)
        let categoryName = try #require(indexer.categoryNames.first)
        #expect(indexer.categoryGroup(forName: categoryName)?.info.className == GenericAncestryCategoryFixture.runtimeName)
    }

    // MARK: - Xcode Service

    @Test(
        "Xcode Service's generic and stub-registered classes read from the offsets MachOSwiftSection supplies",
        .enabled(if: XcodeServiceFixture.isAvailable)
    )
    func xcodeService() async throws {
        let machO = try XcodeServiceFixture.machOFile()
        let indexer = ObjCInterfaceIndexer(
            machO: machO,
            imagePath: machO.imagePath,
            suppliedClasses: [XcodeServiceFixture.menuBarPanelWindow, XcodeServiceFixture.menuBarLabelHostingView]
        )
        try await indexer.prepare()

        let panelWindow = try #require(indexer.suppliedClassGroup(forName: XcodeServiceFixture.menuBarPanelWindow.name)?.info.first)
        #expect(panelWindow.superClassName == "NSPanel")
        #expect(panelWindow.methods.count == 9)
        #expect(panelWindow.classMethods.isEmpty)

        let hostingView = try #require(indexer.suppliedClassGroup(forName: XcodeServiceFixture.menuBarLabelHostingView.name)?.info.first)
        #expect(hostingView.methods.map(\.name) == ["layout", "viewWillDraw", "initWithCoder:"])
        #expect(hostingView.methods.map { machO.objcResolvedIMPAddress(forRawValue: $0.imp) } == [0x1_0002_7C68, 0x1_0002_7C78, 0x1_0002_7E80])
    }
}

// MARK: - Stand-in Scenario

/// Supplies one of the image's classes again under other names — before its
/// supplied superclass, in a cycle, after an unknown superclass — next to the
/// entries the indexer skips, and checks the index against one built without
/// them.
enum StandInScenario {
    static func readOnlyData(of objcClass: ObjCClass64, in image: MachOImage) -> ObjCClassROData64? {
        if let readOnlyData = objcClass.classROData(in: image) {
            return readOnlyData
        }
        guard let readWriteData = objcClass.classRWData(in: image) else { return nil }
        return readWriteData.classROData(in: image) ?? readWriteData.ext(in: image)?.classROData(in: image)
    }

    static func run<MachO: ObjCMetadataSource>(
        machO: MachO,
        unreadableOffset: Int,
        readOnlyDataOffsets: (ObjCClass64) throws -> (instance: Int, metaclass: Int)
    ) async throws {
        let plainEvents = EventRecorder()
        let plainIndexer = ObjCInterfaceIndexer(machO: machO, imagePath: machO.imagePath, eventHandler: plainEvents.record)
        try await plainIndexer.prepare()

        // A class with every kind of member, whose superclass is a class of
        // this image too.
        let source = try #require(plainIndexer.classNames.sorted().lazy.compactMap { className -> (ObjCClass64, ObjCClassInfo, String)? in
            guard let group = plainIndexer.classGroup(forName: className),
                  let objcClass = group.objcClass as? ObjCClass64,
                  let info = group.info.first,
                  !info.protocols.isEmpty, !info.ivars.isEmpty, !info.methods.isEmpty, !info.classMethods.isEmpty,
                  let superClassName = info.superClassName,
                  plainIndexer.classGroup(forName: superClassName) != nil
            else { return nil }
            return (objcClass, info, superClassName)
        }.first)
        let (sourceClass, sourceInfo, sourceSuperClassName) = source
        let offsets = try readOnlyDataOffsets(sourceClass)

        func standIn(_ name: String, superClassName: String?, readOnlyDataOffset: Int? = nil, kind: ObjCSuppliedClass.Kind = .swiftClassWithResilientAncestry) -> ObjCSuppliedClass {
            ObjCSuppliedClass(
                name: name,
                superClassName: superClassName,
                readOnlyDataOffset: readOnlyDataOffset ?? offsets.instance,
                metaclassReadOnlyDataOffset: offsets.metaclass,
                kind: kind
            )
        }
        let suppliedClasses = [
            standIn("SuppliedStandInSubclass", superClassName: "SuppliedStandIn", kind: .swiftClassWithGenericAncestry),
            standIn("SuppliedStandIn", superClassName: sourceSuperClassName),
            standIn("SuppliedStandIn", superClassName: "DuplicateSuperclass"),
            standIn("SuppliedCycleFirst", superClassName: "SuppliedCycleSecond"),
            standIn("SuppliedCycleSecond", superClassName: "SuppliedCycleFirst"),
            standIn("SuppliedOrphan", superClassName: "NoSuchSuperclass", kind: .genericSwiftClass),
            standIn("", superClassName: nil),
            standIn(sourceInfo.name, superClassName: "TakenSuperclass"),
            standIn("SuppliedUnreadable", superClassName: nil, readOnlyDataOffset: unreadableOffset),
        ]
        let indexedNames = ["SuppliedStandInSubclass", "SuppliedStandIn", "SuppliedCycleFirst", "SuppliedCycleSecond", "SuppliedOrphan"]

        let events = EventRecorder()
        let indexer = ObjCInterfaceIndexer(machO: machO, imagePath: machO.imagePath, suppliedClasses: suppliedClasses, eventHandler: events.record)
        try await indexer.prepare()

        // Names and lookups.
        #expect(Set(indexer.classNames) == Set(plainIndexer.classNames).union(indexedNames))
        #expect(indexer.classNames.count == plainIndexer.classNames.count + indexedNames.count)
        for name in indexedNames {
            #expect(indexer.classGroup(forName: name) == nil, "\(name)")
            #expect(indexer.suppliedClassGroup(forName: name) != nil, "\(name)")
        }

        // Its own information is the source class's, under the given names.
        let standIn = try #require(indexer.suppliedClassGroup(forName: "SuppliedStandIn"))
        let standInInfo = try #require(standIn.info.first)
        #expect(standIn.suppliedClass.superClassName == sourceSuperClassName)
        #expect(standInInfo.name == "SuppliedStandIn")
        #expect(standInInfo.superClassName == sourceSuperClassName)
        #expect(standInInfo.protocols == sourceInfo.protocols)
        #expect(standInInfo.ivars == sourceInfo.ivars)
        #expect(standInInfo.properties == sourceInfo.properties)
        #expect(standInInfo.classProperties == sourceInfo.classProperties)
        #expect(standInInfo.methods == sourceInfo.methods)
        #expect(standInInfo.classMethods == sourceInfo.classMethods)
        #expect(standInInfo.instanceSize == sourceInfo.instanceSize)
        #expect(standIn.ivarNamesWithUnknownOffset.isEmpty)

        // Chains, by name.
        let superclassChain = try #require(plainIndexer.classGroup(forName: sourceSuperClassName)).info.map(\.name)
        func chain(_ name: String) -> [String]? {
            indexer.suppliedClassGroup(forName: name)?.info.map(\.name)
        }
        #expect(chain("SuppliedStandIn") == ["SuppliedStandIn"] + superclassChain)
        #expect(chain("SuppliedStandInSubclass") == ["SuppliedStandInSubclass", "SuppliedStandIn"] + superclassChain)
        #expect(chain("SuppliedCycleFirst") == ["SuppliedCycleFirst", "SuppliedCycleSecond"])
        #expect(chain("SuppliedCycleSecond") == ["SuppliedCycleSecond", "SuppliedCycleFirst"])
        #expect(chain("SuppliedOrphan") == ["SuppliedOrphan"])

        // Skipped: an empty name, a name a class object took, a class_ro_t
        // that cannot be read.
        #expect(indexer.suppliedClassGroup(forName: "") == nil)
        #expect(indexer.suppliedClassGroup(forName: sourceInfo.name) == nil)
        #expect(indexer.classGroup(forName: sourceInfo.name)?.info.first == sourceInfo)
        #expect(indexer.suppliedClassGroup(forName: "SuppliedUnreadable") == nil)

        // Events: the listed classes' as before, then the supplied ones in the
        // order given, as Swift classes; the category phase as before.
        let suppliedRelationships = events.classRelationships.filter { indexedNames.contains($0.className) }
        #expect(events.classRelationships == plainEvents.classRelationships + suppliedRelationships)
        let expectedSuppliedRelationships = [
            ("SuppliedStandInSubclass", "SuppliedStandIn"),
            ("SuppliedStandIn", sourceSuperClassName),
            ("SuppliedCycleFirst", "SuppliedCycleSecond"),
            ("SuppliedCycleSecond", "SuppliedCycleFirst"),
            ("SuppliedOrphan", "NoSuchSuperclass"),
        ].flatMap { className, superclassName in
            [EventRecorder.ClassRelationship(className: className, relatedName: superclassName, isSubclass: true, isSwiftStable: true)]
                + sourceInfo.protocols.map { EventRecorder.ClassRelationship(className: className, relatedName: $0.name, isSubclass: false, isSwiftStable: true) }
        }
        #expect(suppliedRelationships == expectedSuppliedRelationships)
        #expect(events.categoryConformances == plainEvents.categoryConformances)

        // The class count takes in every supplied class with a name of its
        // own: the seven left once the empty name and the repeated one are out.
        #expect(events.classTotalCount == plainEvents.classTotalCount.map { $0 + 7 })
    }
}

// MARK: - Event Recording

final class EventRecorder: @unchecked Sendable {
    struct ClassRelationship: Equatable, CustomStringConvertible {
        let className: String
        let relatedName: String
        let isSubclass: Bool
        let isSwiftStable: Bool

        var description: String {
            "\(className) \(isSubclass ? ":" : "<")\(relatedName)\(isSwiftStable ? " (Swift)" : "")"
        }
    }

    struct CategoryConformance: Equatable {
        let targetClassName: String
        let protocolName: String
        let targetIsSwiftStable: Bool
    }

    private let lock = NSLock()
    private var events: [ObjCIndexingEvent] = []

    func record(_ event: ObjCIndexingEvent) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }

    private var recordedEvents: [ObjCIndexingEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    /// Subclass and adoption events of the class phase, in arrival order.
    var classRelationships: [ClassRelationship] {
        recordedEvents.compactMap { event in
            switch event {
            case .subclassIndexed(let className, let superclass, _, let isSwiftStable):
                ClassRelationship(className: className, relatedName: superclass, isSubclass: true, isSwiftStable: isSwiftStable)
            case .conformanceIndexed(let className, let protocolName, _, let isSwiftStable):
                ClassRelationship(className: className, relatedName: protocolName, isSubclass: false, isSwiftStable: isSwiftStable)
            default:
                nil
            }
        }
    }

    var categoryConformances: [CategoryConformance] {
        recordedEvents.compactMap { event in
            guard case .categoryConformanceIndexed(let targetClassName, let protocolName, _, let targetIsSwiftStable) = event else { return nil }
            return CategoryConformance(targetClassName: targetClassName, protocolName: protocolName, targetIsSwiftStable: targetIsSwiftStable)
        }
    }

    /// The total the class phase announces at its start.
    var classTotalCount: Int? {
        recordedEvents.lazy.compactMap { event -> Int? in
            guard case .progress(.indexingSubclasses, _, _, let totalCount) = event else { return nil }
            return totalCount
        }.first
    }
}
