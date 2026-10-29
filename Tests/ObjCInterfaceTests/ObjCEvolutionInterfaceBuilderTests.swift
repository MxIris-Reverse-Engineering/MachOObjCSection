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

    // MARK: - Image groups

    /// The declarations between the legend and the warnings.
    private static func declarations(of interface: String) -> String {
        let afterLegend = interface.components(separatedBy: "\n\n").dropFirst().joined(separator: "\n\n")
        return afterLegend.components(separatedBy: "\n\n// Warnings — ")[0]
    }

    @Test("The images of a group render as the evolution merges them: each declaration from the first image holding it")
    func imageGroupRendersTheComparedCopies() async throws {
        let (indexer, machO) = try await ObjCInterfaceTests.SharedFixture.shared.load()
        var singleImageBuilder = ObjCEvolutionInterfaceBuilder()
        var imageGroupBuilder = ObjCEvolutionInterfaceBuilder()
        // The same image twice in one group: every class, category member and
        // C type is declared by both images, and every protocol carried by both.
        let group = [
            ObjCEvolutionInterfaceImage(imageName: "Foundation", indexer: indexer, machO: machO),
            ObjCEvolutionInterfaceImage(imageName: "Copy", indexer: indexer, machO: machO),
        ]
        for label in ["1.0", "2.0"] {
            singleImageBuilder.addVersion(indexer: indexer, machO: machO, version: ObjCAPIVersionDescriptor(label: label))
            imageGroupBuilder.addVersion(images: group, version: ObjCAPIVersionDescriptor(label: label))
        }
        let singleImage = try singleImageBuilder.build()
        let imageGroup = try imageGroupBuilder.build()

        #expect(imageGroup.evolution.isEmpty)
        #expect(Self.declarations(of: imageGroup.interface.string) == Self.declarations(of: singleImage.interface.string))

        let lines = imageGroup.interface.string.components(separatedBy: "\n")
        #expect(lines.contains("//   [●●] Copy"))
        // The class `objc dump` checks its strip switches on, dropped from the second image.
        #expect(lines.contains("//   1.0 · dropped: NSError (Copy)"))
        #expect(!lines.contains { $0.hasPrefix("//   1.0 · dropped: NSCopying") })
    }

    @Test("A class or category that moves to another image carries the move, and its members do not repeat it")
    func movedDeclarationsCarryTheMove() async throws {
        let (indexer, machO) = try await ObjCInterfaceTests.SharedFixture.shared.load()
        var builder = ObjCEvolutionInterfaceBuilder()
        builder.addVersion(images: [ObjCEvolutionInterfaceImage(imageName: "Primary", indexer: indexer, machO: machO)], version: ObjCAPIVersionDescriptor(label: "1.0"))
        builder.addVersion(images: [ObjCEvolutionInterfaceImage(imageName: "Secondary", indexer: indexer, machO: machO)], version: ObjCAPIVersionDescriptor(label: "2.0"))
        let merged = try builder.build()

        let snapshot = ObjCAPISnapshotBuilder(indexer: indexer).snapshot()
        let move = ObjCImageMove(versionIndex: 1, oldImageNames: ["Primary"], newImageNames: ["Secondary"])
        let movedContainers = merged.evolution.classes + merged.evolution.categories
        try #require(!snapshot.classes.isEmpty && !snapshot.categories.isEmpty)
        #expect(movedContainers.count == snapshot.classes.count + snapshot.categories.count)
        #expect(movedContainers.allSatisfy { $0.imageMoves == [move] && $0.events.isEmpty && $0.memberLineages.isEmpty })
        #expect(merged.evolution.protocols.isEmpty)

        let lines = merged.interface.string.components(separatedBy: "\n")
        #expect(Array(lines[2 ... 4]) == ["// Image group:", "//   [●○] Primary", "//   [○●] Secondary"])
        let moveAnnotationCount = lines.count { $0.hasSuffix("// [●●] moved in 2.0: Primary → Secondary") }
        #expect(moveAnnotationCount == movedContainers.count)
    }

    @Test("A builder given both single images and image groups does not build")
    func singleImagesAndImageGroupsDoNotMix() async throws {
        let (indexer, machO) = try await ObjCInterfaceTests.SharedFixture.shared.load()
        var builder = ObjCEvolutionInterfaceBuilder()
        builder.addVersion(indexer: indexer, machO: machO, version: ObjCAPIVersionDescriptor(label: "1.0"))
        builder.addVersion(images: [ObjCEvolutionInterfaceImage(imageName: "Foundation", indexer: indexer, machO: machO)], version: ObjCAPIVersionDescriptor(label: "2.0"))
        #expect(throws: ObjCEvolutionInterfaceError.singleImageVersionsMixedWithImageGroups) {
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
