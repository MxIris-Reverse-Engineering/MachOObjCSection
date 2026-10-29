import ObjCDump
import Testing
@testable import ObjCDiffing

/// A container can hold one identity several times. The linker merges the
/// categories an image adds to its own classes into those classes, the
/// categories' lists ahead of the class's own and nothing deduplicated, and
/// clang copies into a category's property list every property the protocols
/// it adopts declare. These pin which record a comparison takes and which of
/// the others are worth a warning.
@Suite("Duplicate members of one container")
struct DuplicateMemberSelectionTests {
    private let differ = ObjCAPIDiffer()

    /// `NSLayoutItem`'s `frame`, read-only, as the protocol declares it.
    private static let readOnlyFrame = Fixtures.propertyInfo(name: "frame", attributesString: "T{CGRect={CGPoint=dd}{CGSize=dd}},R")
    /// `NSView`'s own `frame`, read-write.
    private static let readWriteFrame = Fixtures.propertyInfo(name: "frame", attributesString: "T{CGRect={CGPoint=dd}{CGSize=dd}}")
    private static let layoutItem = Fixtures.protocolInfo(name: "NSLayoutItem", properties: [readOnlyFrame])

    private static let twoVersions = [ObjCAPIVersionDescriptor(label: "12.0"), ObjCAPIVersionDescriptor(label: "13.0")]

    /// `NSView` as macOS 12 has it: its own `frame` only.
    private func viewBeforeLayoutItem() -> ObjCAPISnapshot {
        differ.snapshot(of: ObjCAPIModule(classes: [Fixtures.classInfo(name: "NSView", properties: [Self.readWriteFrame])]))
    }

    /// `NSView` as macOS 13 has it: a category merged into the class adopts
    /// `NSLayoutItem`, so the protocol's copy of `frame` comes first and the
    /// class's own declaration after it.
    private func viewAdoptingLayoutItem() -> ObjCAPISnapshot {
        differ.snapshot(of: ObjCAPIModule(
            classes: [Fixtures.classInfo(name: "NSView", protocols: [Self.layoutItem], properties: [Self.readOnlyFrame, Self.readWriteFrame])],
            protocols: [Self.layoutItem]
        ))
    }

    @Test("A protocol's copy ahead of the class's own declaration is no change in the class")
    func protocolCopyAheadOfOwnDeclarationIsNoChange() throws {
        let evolution = try ObjCAPIEvolutionBuilder().evolution(of: [viewBeforeLayoutItem(), viewAdoptingLayoutItem()], versions: Self.twoVersions)
        let view = try #require(evolution.classes.first { $0.name == "NSView" })
        #expect(view.memberLineages.map(\.key.rawValue) == ["adopts:NSLayoutItem"])
    }

    @Test("A protocol's copy that differs from the class's own declaration is no collision")
    func protocolCopyIsNoCollision() throws {
        let evolution = try ObjCAPIEvolutionBuilder().evolution(of: [viewBeforeLayoutItem(), viewAdoptingLayoutItem()], versions: Self.twoVersions)
        #expect(evolution.keyCollisionsByVersion == nil)
    }

    @Test("A two-sided diff compares the class's own declaration, not the protocol's copy")
    func diffComparesOwnDeclaration() throws {
        let diff = differ.diff(old: viewBeforeLayoutItem(), new: viewAdoptingLayoutItem())
        let view = try #require(diff.classes.first { $0.name == "NSView" })
        #expect(view.memberChanges.map(\.key.rawValue) == ["adopts:NSLayoutItem"])
        #expect(diff.diagnostics == nil)
    }

    @Test("Copies of a property with the same payload are no collision")
    func identicalPropertyCopiesAreNoCollision() {
        let hash = Fixtures.propertyInfo(name: "hash", attributesString: "TQ,R")
        let snapshot = differ.snapshot(of: ObjCAPIModule(classes: [Fixtures.classInfo(name: "NSApplication", properties: [hash, hash, hash, hash])]))
        #expect(snapshot.keyCollisions().isEmpty)
    }

    @Test("Copies of a method with the same type encoding are no collision")
    func identicalMethodCopiesAreNoCollision() {
        let categoryOverride = Fixtures.methodInfo(name: "setControlView:", typeEncoding: "v24@0:8@16", imp: 0x1000)
        let ownImplementation = Fixtures.methodInfo(name: "setControlView:", typeEncoding: "v24@0:8@16", imp: 0x2000)
        let snapshot = differ.snapshot(of: ObjCAPIModule(classes: [Fixtures.classInfo(name: "_NSDatePickerArrowCell", methods: [categoryOverride, ownImplementation])]))
        #expect(snapshot.keyCollisions().isEmpty)
    }

    @Test("Two differing declarations that copy no adopted protocol still collide, the first one kept")
    func differingOwnDeclarationsCollide() {
        let copyingStringValue = Fixtures.propertyInfo(name: "stringValue", attributesString: "T@\"NSString\",C,N")
        let readOnlyStringValue = Fixtures.propertyInfo(name: "stringValue", attributesString: "T@\"NSString\",R")
        let snapshot = differ.snapshot(of: ObjCAPIModule(classes: [
            Fixtures.classInfo(name: "NSMenuItemBadge", properties: [copyingStringValue, readOnlyStringValue]),
        ]))
        #expect(snapshot.keyCollisions() == [
            ObjCAPIKeyCollision(
                key: ObjCAPIKey(rawValue: "property:-stringValue"),
                containerName: "NSMenuItemBadge",
                droppedSignatures: [readOnlyStringValue.headerString],
                keptSignature: copyingStringValue.headerString
            ),
        ])
    }

    @Test("A class's own declaration is kept over a protocol's copy that comes first, and the copy is not listed")
    func ownDeclarationIsKeptOverProtocolCopy() {
        #expect(viewAdoptingLayoutItem().keyCollisions().isEmpty)
        let diff = differ.diff(old: viewAdoptingLayoutItem(), new: viewBeforeLayoutItem())
        let frameChanges = diff.classes.flatMap(\.memberChanges).filter { $0.key.rawValue == "property:-frame" }
        #expect(frameChanges.isEmpty)
    }

    @Test("A protocol adopted through another protocol makes a copy too")
    func copyThroughAnInheritedProtocolIsRecognized() throws {
        let inheritingLayoutItem = Fixtures.protocolInfo(name: "NSAKLayoutItem", protocols: [Self.layoutItem])
        let snapshot = differ.snapshot(of: ObjCAPIModule(
            classes: [Fixtures.classInfo(name: "NSView", protocols: [inheritingLayoutItem], properties: [Self.readOnlyFrame, Self.readWriteFrame])],
            protocols: [inheritingLayoutItem, Self.layoutItem]
        ))
        let evolution = try ObjCAPIEvolutionBuilder().evolution(of: [viewBeforeLayoutItem(), snapshot], versions: Self.twoVersions)
        let view = try #require(evolution.classes.first { $0.name == "NSView" })
        #expect(view.memberLineages.map(\.key.rawValue) == ["adopts:NSAKLayoutItem"])
        #expect(evolution.keyCollisionsByVersion == nil)
    }

    @Test("Copies of a protocol that is not in the snapshot read as the class's own declarations")
    func copyOfAnUnknownProtocolReadsAsOwn() {
        let snapshot = differ.snapshot(of: ObjCAPIModule(classes: [
            Fixtures.classInfo(name: "NSView", protocols: [Self.layoutItem], properties: [Self.readOnlyFrame, Self.readWriteFrame]),
        ]))
        #expect(snapshot.keyCollisions() == [
            ObjCAPIKeyCollision(
                key: ObjCAPIKey(rawValue: "property:-frame"),
                containerName: "NSView",
                droppedSignatures: [Self.readWriteFrame.headerString],
                keptSignature: Self.readOnlyFrame.headerString
            ),
        ])
    }
}
