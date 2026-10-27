import ObjCDump
import Testing
@testable import ObjCDiffing

/// A protocol that newly adopts another makes every existing conformer
/// implement the adopted protocol's required members, as adding them to the
/// protocol directly would; a class or category that adopts one only takes on
/// the implementing side.
@Suite("Protocol adoption compatibility")
struct ProtocolAdoptionCompatibilityTests {
    private let differ = ObjCAPIDiffer()

    /// Requires `-encodeWithCoder:`.
    private static let coding = Fixtures.protocolInfo(name: "Coding", methods: [Fixtures.methodInfo(name: "encodeWithCoder:")])
    /// Requires nothing: `-observeValue` is optional.
    private static let observing = Fixtures.protocolInfo(name: "Observing", optionalMethods: [Fixtures.methodInfo(name: "observeValue")])
    /// Requires `-encodeWithCoder:` through its own adoption of `Coding`.
    private static let archiving = Fixtures.protocolInfo(name: "Archiving", protocols: [coding])

    @Test("A protocol that adopts one with required members breaks its conformers")
    func adoptingRequiredMembersIsBreaking() {
        let oldModule = ObjCAPIModule(protocols: [Fixtures.protocolInfo(name: "Drawing"), Self.coding])
        let newModule = ObjCAPIModule(protocols: [Fixtures.protocolInfo(name: "Drawing", protocols: [Self.coding]), Self.coding])

        #expect(differ.diff(old: oldModule, new: newModule).hasBreakingChange)
    }

    @Test("A protocol that adopts one with only optional members stays compatible")
    func adoptingOptionalMembersIsCompatible() {
        let oldModule = ObjCAPIModule(protocols: [Fixtures.protocolInfo(name: "Drawing"), Self.observing])
        let newModule = ObjCAPIModule(protocols: [Fixtures.protocolInfo(name: "Drawing", protocols: [Self.observing]), Self.observing])

        #expect(!differ.diff(old: oldModule, new: newModule).hasBreakingChange)
    }

    @Test("A protocol that adopts one whose members it already required stays compatible")
    func adoptingAlreadyRequiredMembersIsCompatible() {
        let oldModule = ObjCAPIModule(protocols: [
            Fixtures.protocolInfo(name: "Drawing", protocols: [Self.archiving]), Self.archiving, Self.coding,
        ])
        let newModule = ObjCAPIModule(protocols: [
            Fixtures.protocolInfo(name: "Drawing", protocols: [Self.archiving, Self.coding]), Self.archiving, Self.coding,
        ])

        #expect(!differ.diff(old: oldModule, new: newModule).hasBreakingChange)
    }

    /// The adopted protocol's requirements cannot be known, so the adoption
    /// is judged breaking rather than risk missing a break.
    @Test("A protocol that adopts one the snapshot does not hold is judged breaking")
    func adoptingUnknownProtocolIsBreaking() {
        let oldModule = ObjCAPIModule(protocols: [Fixtures.protocolInfo(name: "Drawing")])
        let newModule = ObjCAPIModule(protocols: [Fixtures.protocolInfo(name: "Drawing", protocols: [Self.coding])])

        #expect(differ.diff(old: oldModule, new: newModule).hasBreakingChange)
    }

    @Test("A class that adopts a protocol with required members stays compatible")
    func classAdoptionIsCompatible() {
        let oldModule = ObjCAPIModule(classes: [Fixtures.classInfo(name: "Widget")], protocols: [Self.coding])
        let newModule = ObjCAPIModule(classes: [Fixtures.classInfo(name: "Widget", protocols: [Self.coding])], protocols: [Self.coding])

        #expect(!differ.diff(old: oldModule, new: newModule).hasBreakingChange)
    }

    @Test("The evolution judges a protocol's new adoption as the two-sided diff does")
    func evolutionAgreesWithTwoSidedDiff() throws {
        let oldSnapshot = differ.snapshot(of: ObjCAPIModule(protocols: [Fixtures.protocolInfo(name: "Drawing"), Self.coding]))
        let newSnapshot = differ.snapshot(of: ObjCAPIModule(protocols: [Fixtures.protocolInfo(name: "Drawing", protocols: [Self.coding]), Self.coding]))

        let evolution = try ObjCAPIEvolutionBuilder().evolution(
            of: [oldSnapshot, newSnapshot],
            versions: [ObjCAPIVersionDescriptor(label: "v1"), ObjCAPIVersionDescriptor(label: "v2")]
        )

        #expect(evolution.hasBreakingChange)
    }
}
