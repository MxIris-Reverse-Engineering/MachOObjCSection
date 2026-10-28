import Foundation
import MachOKit
import ObjCDiffing
import ObjCIndexing
import Semantic
import Testing
@testable import ObjCInterface

/// The merged header over an image already loaded into this process, and the
/// order rule that decides where a removed member stays. What the
/// annotations say across real versions is pinned by
/// `ObjCEvolutionInterfaceArchivedCacheTests`.
@Suite("ObjCEvolutionInterfaceBuilder")
struct ObjCEvolutionInterfaceBuilderTests {
    /// `objc dump` is the reference. The one place the merged header may
    /// differ is a member the image lists twice under one identity — a
    /// property a class extension redeclares, say: the snapshot compares only
    /// the first, so the merged header writes only the first, and names the
    /// others among the identity-key collisions at its end.
    @Test("The same image twice reads as objc dump writes it, with no annotation")
    func sameImageTwiceReadsAsTheDump() async throws {
        let (indexer, machO) = try await ObjCInterfaceTests.SharedFixture.shared.load()
        var builder = ObjCEvolutionInterfaceBuilder()
        builder.addVersion(indexer: indexer, machO: machO, version: ObjCAPIVersionDescriptor(label: "1.0"))
        builder.addVersion(indexer: indexer, machO: machO, version: ObjCAPIVersionDescriptor(label: "2.0"))
        let merged = try builder.build(availabilityPlatform: "macos")

        #expect(merged.evolution.isEmpty)

        let interfaceBuilder = ObjCInterfaceBuilder(indexer: indexer, machO: machO)
        let containerDeclarations = indexer.classNames.sorted().compactMap { interfaceBuilder.classInterface(named: $0)?.string }
            + indexer.protocolNames.sorted().compactMap { interfaceBuilder.protocolInterface(named: $0)?.string }
            + indexer.categoryNames.sorted().compactMap { interfaceBuilder.categoryInterface(uniqueName: $0)?.string }
        let cDefinitions = indexer.structNames.sorted().compactMap { interfaceBuilder.structInterface(named: $0)?.string }
            + indexer.unionNames.sorted().compactMap { interfaceBuilder.unionInterface(named: $0)?.string }
        try #require(!containerDeclarations.isEmpty && !cDefinitions.isEmpty)

        let legend = """
        // ObjC API evolution across 2 versions: 1.0 → 2.0
        // Bitmap positions: [1] 1.0  [2] 2.0
        // API_AVAILABLE and API_OBSOLETED versions are axis points: the introduced version is the first axis point carrying a declaration, the obsoleted version the first one without it — not necessarily the releases that really introduced or removed it.
        """
        let cDefinitionsComment = "// C structs and unions, each as the newest version that has it defines it. They are not tracked across versions."
        let expectedInterface = ([legend] + containerDeclarations + [cDefinitionsComment] + cDefinitions).joined(separator: "\n\n")

        let mergedLines = merged.interface.string.components(separatedBy: "\n")
        let dumpLines = expectedInterface.components(separatedBy: "\n")

        // Walk the dump: a line the merged header has next is shared; any
        // other line is one the merged header left out.
        var mergedLineIndex = 0
        var leftOutLines: [String] = []
        for dumpLine in dumpLines {
            if mergedLineIndex < mergedLines.count, mergedLines[mergedLineIndex] == dumpLine {
                mergedLineIndex += 1
            } else {
                leftOutLines.append(dumpLine)
            }
        }

        let droppedRecordCount = merged.evolution.keyCollisionsByVersion?.first?.reduce(0) { $0 + $1.droppedSignatures.count } ?? 0
        #expect(leftOutLines.count == droppedRecordCount, "left out: \(leftOutLines.prefix(5))")
        #expect(leftOutLines.allSatisfy { $0.hasPrefix("@property ") || $0.hasPrefix("- (") || $0.hasPrefix("+ (") || $0.hasPrefix("    ") })

        let trailingLines = Array(mergedLines[mergedLineIndex...])
        if droppedRecordCount == 0 {
            #expect(trailingLines.isEmpty)
        } else {
            #expect(trailingLines.first == "")
            #expect(trailingLines.dropFirst().first == "// Warnings — identity-key collisions (first record kept, later ones not compared):")
        }
    }

    @Test("Fewer than two versions build nothing")
    func needsTwoVersions() async throws {
        let (indexer, machO) = try await ObjCInterfaceTests.SharedFixture.shared.load()
        var builder = ObjCEvolutionInterfaceBuilder()
        builder.addVersion(indexer: indexer, machO: machO, version: ObjCAPIVersionDescriptor(label: "1.0"))
        #expect(throws: ObjCAPIEvolutionError.fewerThanTwoVersions(versionCount: 1)) {
            try builder.build()
        }
    }

    // MARK: - Member order

    private static func key(_ rawValue: String) -> ObjCAPIKey {
        ObjCAPIKey(rawValue: rawValue)
    }

    @Test("A key the merged order lacks goes right after the key that preceded it")
    func insertsAfterPredecessor() {
        let merged = ObjCEvolutionMemberLayout.interleaving(
            [Self.key("a"), Self.key("b"), Self.key("c"), Self.key("d")],
            into: [Self.key("a"), Self.key("d"), Self.key("x")]
        )
        #expect(merged == [Self.key("a"), Self.key("b"), Self.key("c"), Self.key("d"), Self.key("x")])
    }

    @Test("A key with nothing before it goes right before the key after it, or last")
    func insertsBeforeSuccessorOrLast() {
        let beforeSuccessor = ObjCEvolutionMemberLayout.interleaving(
            [Self.key("a"), Self.key("b")],
            into: [Self.key("x"), Self.key("b")]
        )
        #expect(beforeSuccessor == [Self.key("x"), Self.key("a"), Self.key("b")])

        let last = ObjCEvolutionMemberLayout.interleaving([Self.key("a")], into: [Self.key("x")])
        #expect(last == [Self.key("x"), Self.key("a")])
    }

    @Test("The newest version decides the order and the group; a removed member stays where it last was")
    func newestVersionDecidesOrderAndGroup() {
        func method(_ selector: String, isOptional: Bool) -> ObjCMemberRecord {
            ObjCMemberRecord(
                identityKey: Self.key("method:-\(selector)"),
                payloadKey: Self.key("enc:v16@0:8|optional:\(isOptional ? 1 : 0)"),
                kind: .instanceMethod,
                signature: "- (void)\(selector);",
                isOptionalRequirement: isOptional
            )
        }
        func protocolSnapshot(_ members: [ObjCMemberRecord]) -> ObjCContainerSnapshot {
            ObjCContainerSnapshot(key: Self.key("protocol:Example"), name: "Example", kind: .protocol, members: members)
        }
        let layout = ObjCEvolutionMemberLayout(perVersion: [
            protocolSnapshot([method("first", isOptional: false), method("removed", isOptional: false), method("moved", isOptional: false), method("last", isOptional: false)]),
            nil,
            protocolSnapshot([method("last", isOptional: false), method("first", isOptional: false), method("moved", isOptional: true)]),
        ])

        #expect(layout.mergedKeys(of: .methods) == [Self.key("method:-last"), Self.key("method:-first"), Self.key("method:-removed")])
        #expect(layout.mergedKeys(of: .optionalMethods) == [Self.key("method:-moved")])
        #expect(layout.isOptionalRequirement(Self.key("method:-moved"), atVersion: 0) == false)
        #expect(layout.isOptionalRequirement(Self.key("method:-moved"), atVersion: 1) == nil)
        #expect(layout.isOptionalRequirement(Self.key("method:-moved"), atVersion: 2) == true)
    }
}
