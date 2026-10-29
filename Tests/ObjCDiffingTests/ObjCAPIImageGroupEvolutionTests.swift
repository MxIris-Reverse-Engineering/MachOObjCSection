import Testing
@testable import ObjCDiffing

/// `ObjCAPIEvolutionBuilder.evolution(ofImageGroups:versions:)`: several
/// images per version tracked as one API surface.
@Suite("Evolution of image groups")
struct ObjCAPIImageGroupEvolutionTests {
    private let builder = ObjCAPIEvolutionBuilder()

    private func versions(_ labels: [String]) -> [ObjCAPIVersionDescriptor] {
        labels.map { ObjCAPIVersionDescriptor(label: $0) }
    }

    private func image(
        _ imageName: String,
        classes: [ObjCContainerSnapshot] = [],
        protocols: [ObjCContainerSnapshot] = [],
        categories: [ObjCContainerSnapshot] = []
    ) -> ObjCAPIImageSnapshot {
        ObjCAPIImageSnapshot(imageName: imageName, snapshot: ObjCAPISnapshot(classes: classes, protocols: protocols, categories: categories))
    }

    private func method(_ selector: String, payload: String = "enc:v16@0:8") -> ObjCMemberRecord {
        Fixtures.record(identity: "method:-\(selector)", payload: payload, signature: "- (void)\(selector);")
    }

    private func classSnapshot(_ name: String, members: [ObjCMemberRecord] = []) -> ObjCContainerSnapshot {
        Fixtures.containerSnapshot(key: "class:\(name)", name: name, members: members)
    }

    private func protocolSnapshot(_ name: String, members: [ObjCMemberRecord] = []) -> ObjCContainerSnapshot {
        Fixtures.containerSnapshot(key: "protocol:\(name)", name: name, kind: .protocol, members: members)
    }

    private func categorySnapshot(_ uniqueName: String, members: [ObjCMemberRecord] = []) -> ObjCContainerSnapshot {
        Fixtures.containerSnapshot(key: "category:\(uniqueName)", name: uniqueName, kind: .category, members: members)
    }

    private func key(_ rawValue: String) -> ObjCAPIKey {
        ObjCAPIKey(rawValue: rawValue)
    }

    // MARK: - Moves

    @Test("A class that moves to another image is one move, which its members do not repeat")
    func classMovesAsOne() throws {
        let evolution = try builder.evolution(
            ofImageGroups: [
                [image("AppKit", classes: [classSnapshot("NSFoo", members: [method("run")])])],
                [image("AppKit"), image("UIFoundation", classes: [classSnapshot("NSFoo", members: [method("run")])])],
            ],
            versions: versions(["13.0", "14.0"])
        )
        #expect(evolution.classes == [
            ObjCContainerLineage(
                key: key("class:NSFoo"),
                name: "NSFoo",
                containerKind: .class,
                presence: [true, true],
                events: [],
                memberLineages: [],
                imageMoves: [ObjCImageMove(versionIndex: 1, oldImageNames: ["AppKit"], newImageNames: ["UIFoundation"])]
            ),
        ])
        #expect(evolution.transitionCompatibilities == [.additive])
    }

    @Test("A category split across two images records the methods that changed image, with their newest rendering")
    func categorySplitRecordsMovedMethods() throws {
        let evolution = try builder.evolution(
            ofImageGroups: [
                [image("AppKit", categories: [categorySnapshot("NSString(Drawing)", members: [method("stays"), method("leaves")])])],
                [
                    image("AppKit", categories: [categorySnapshot("NSString(Drawing)", members: [method("stays")])]),
                    image("UIFoundation", categories: [categorySnapshot("NSString(Drawing)", members: [method("leaves")])]),
                ],
            ],
            versions: versions(["13.0", "14.0"])
        )
        #expect(evolution.categories == [
            ObjCContainerLineage(
                key: key("category:NSString(Drawing)"),
                name: "NSString(Drawing)",
                containerKind: .category,
                presence: [true, true],
                events: [],
                memberLineages: [
                    ObjCMemberLineage(
                        key: key("method:-leaves"),
                        kind: .instanceMethod,
                        presence: [true, true],
                        events: [],
                        imageMoves: [ObjCImageMove(versionIndex: 1, oldImageNames: ["AppKit"], newImageNames: ["UIFoundation"])],
                        latestSignature: "- (void)leaves;"
                    ),
                ],
                imageMoves: [ObjCImageMove(versionIndex: 1, oldImageNames: ["AppKit"], newImageNames: ["AppKit", "UIFoundation"])]
            ),
        ])
    }

    @Test("A member that moves and changes in one transition has both, its signature coming from the event")
    func memberMovesAndChanges() throws {
        let evolution = try builder.evolution(
            ofImageGroups: [
                [image("AppKit", categories: [categorySnapshot("NSString(Drawing)", members: [method("draw")])])],
                [
                    image("AppKit", categories: [categorySnapshot("NSString(Drawing)")]),
                    image("UIFoundation", categories: [categorySnapshot("NSString(Drawing)", members: [method("draw", payload: "enc:B16@0:8")])]),
                ],
            ],
            versions: versions(["13.0", "14.0"])
        )
        let memberLineage = try #require(evolution.categories.first?.memberLineages.first)
        #expect(memberLineage.events.map(\.status) == [.modified])
        #expect(memberLineage.imageMoves == [ObjCImageMove(versionIndex: 1, oldImageNames: ["AppKit"], newImageNames: ["UIFoundation"])])
        #expect(memberLineage.latestSignature == nil)
    }

    @Test("Images named in another group order are no move")
    func groupOrderIsNoMove() throws {
        let evolution = try builder.evolution(
            ofImageGroups: [
                [
                    image("AppKit", categories: [categorySnapshot("NSString(Drawing)", members: [method("first")])]),
                    image("UIFoundation", categories: [categorySnapshot("NSString(Drawing)", members: [method("second")])]),
                ],
                [
                    image("UIFoundation", categories: [categorySnapshot("NSString(Drawing)", members: [method("second")])]),
                    image("AppKit", categories: [categorySnapshot("NSString(Drawing)", members: [method("first")])]),
                ],
            ],
            versions: versions(["13.0", "14.0"])
        )
        #expect(evolution.isEmpty)
    }

    @Test("A declaration absent on one side of a transition is added or removed there, not moved")
    func presenceChangesAreNotMoves() throws {
        let evolution = try builder.evolution(
            ofImageGroups: [
                [image("AppKit", classes: [classSnapshot("NSFoo")])],
                [],
                [image("AppKit"), image("CollectionViewCore", classes: [classSnapshot("NSFoo")])],
            ],
            versions: versions(["12.0", "13.0", "14.0"])
        )
        let lineage = try #require(evolution.classes.first)
        #expect(lineage.events.map(\.status) == [.removed, .added])
        #expect(lineage.imageMoves == nil)
        #expect(evolution.versions.map(\.imageNames) == [["AppKit"], [], ["AppKit", "CollectionViewCore"]])
    }

    // MARK: - Merging one version's images

    @Test("A protocol every image carries is compared once, and never moves")
    func protocolCopiesAreOneProtocol() throws {
        let copy = protocolSnapshot("NSCopying", members: [method("copyWithZone:")])
        let evolution = try builder.evolution(
            ofImageGroups: [
                [image("AppKit", protocols: [copy]), image("UIFoundation", protocols: [copy])],
                [image("AppKit"), image("UIFoundation", protocols: [copy])],
            ],
            versions: versions(["13.0", "14.0"])
        )
        #expect(evolution.isEmpty)
        #expect(evolution.keyCollisionsByVersion == nil)
    }

    @Test("Of two differing copies of a protocol, the first image's is compared and the collision names the other")
    func differingProtocolCopiesCollide() throws {
        let group = [
            image("AppKit", protocols: [protocolSnapshot("NSTextAttachmentContainer", members: [method("first")])]),
            image("UIFoundation", protocols: [protocolSnapshot("NSTextAttachmentContainer", members: [method("second")])]),
        ]
        let evolution = try builder.evolution(ofImageGroups: [group, group], versions: versions(["13.0", "14.0"]))
        let collision = ObjCAPIKeyCollision(
            key: key("protocol:NSTextAttachmentContainer"),
            containerName: nil,
            droppedSignatures: ["NSTextAttachmentContainer"],
            droppedImageNames: ["UIFoundation"]
        )
        #expect(evolution.isEmpty)
        #expect(evolution.keyCollisionsByVersion == [[collision], [collision]])
    }

    @Test("A class two images hold is the first image's, and the collision names the other image")
    func duplicatedClassKeepsTheFirstImage() throws {
        let evolution = try builder.evolution(
            ofImageGroups: [
                [image("AppKit", classes: [classSnapshot("NSFoo", members: [method("run")])])],
                [
                    image("AppKit", classes: [classSnapshot("NSFoo", members: [method("run")])]),
                    image("UIFoundation", classes: [classSnapshot("NSFoo", members: [method("other")])]),
                ],
            ],
            versions: versions(["13.0", "14.0"])
        )
        #expect(evolution.classes.map(\.memberLineages) == [[]])
        #expect(evolution.classes.map(\.imageMoves) == [[ObjCImageMove(versionIndex: 1, oldImageNames: ["AppKit"], newImageNames: ["AppKit", "UIFoundation"])]])
        #expect(evolution.keyCollisionsByVersion == [
            [],
            [ObjCAPIKeyCollision(key: key("class:NSFoo"), containerName: nil, droppedSignatures: ["NSFoo"], droppedImageNames: ["UIFoundation"])],
        ])
    }

    @Test("A selector two images both add to one category collides as a member, naming the second image")
    func categoryMemberDeclaredTwiceCollides() throws {
        let group = [
            image("AppKit", categories: [categorySnapshot("NSString(Drawing)", members: [method("draw")])]),
            image("UIFoundation", categories: [categorySnapshot("NSString(Drawing)", members: [method("draw")])]),
        ]
        let evolution = try builder.evolution(ofImageGroups: [group, group], versions: versions(["13.0", "14.0"]))
        let collision = ObjCAPIKeyCollision(
            key: key("method:-draw"),
            containerName: "NSString(Drawing)",
            droppedSignatures: ["- (void)draw;"],
            droppedImageNames: ["UIFoundation"]
        )
        #expect(evolution.keyCollisionsByVersion == [[collision], [collision]])
    }

    // MARK: - Agreement with one image per version

    @Test("One image per version tracks what the single-image entry does, and names the image")
    func oneImagePerVersionMatchesSingleImageEntry() throws {
        let oldSnapshot = ObjCAPISnapshot(classes: [classSnapshot("NSFoo", members: [method("run"), method("stop")])])
        let newSnapshot = ObjCAPISnapshot(classes: [classSnapshot("NSFoo", members: [method("run", payload: "enc:B16@0:8")])])
        let singleImage = try builder.evolution(of: [oldSnapshot, newSnapshot], versions: versions(["1.0", "2.0"]))
        let imageGroups = try builder.evolution(
            ofImageGroups: [
                [ObjCAPIImageSnapshot(imageName: "AppKit", snapshot: oldSnapshot)],
                [ObjCAPIImageSnapshot(imageName: "AppKit", snapshot: newSnapshot)],
            ],
            versions: versions(["1.0", "2.0"])
        )
        #expect(imageGroups.classes == singleImage.classes)
        #expect(imageGroups.versions.map(\.imageNames) == [["AppKit"], ["AppKit"]])
        #expect(singleImage.versions.map(\.imageNames) == [nil, nil])
    }

    // MARK: - Input validation

    @Test("Fewer than two image groups are rejected")
    func fewerThanTwoGroupsIsRejected() {
        #expect(throws: ObjCAPIEvolutionError.fewerThanTwoVersions(versionCount: 1)) {
            try builder.evolution(ofImageGroups: [[image("AppKit")]], versions: versions(["1.0"]))
        }
    }

    @Test("A version count that differs from the group count is rejected")
    func groupCountMismatchIsRejected() {
        #expect(throws: ObjCAPIEvolutionError.labelCountMismatch(labelCount: 1, versionCount: 2)) {
            try builder.evolution(ofImageGroups: [[image("AppKit")], [image("AppKit")]], versions: versions(["1.0"]))
        }
    }
}
