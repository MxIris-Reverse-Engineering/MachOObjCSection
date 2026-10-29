import Testing
@testable import ObjCDiffing

@Suite("Reporters")
struct ObjCAPIReporterTests {
    @Test func diffReportRendersSectionsSigilsAndWarnings() {
        let diff = ObjCAPIDiff(
            classes: [
                ObjCContainerChange(
                    key: ObjCAPIKey(rawValue: "class:Widget"),
                    name: "Widget",
                    containerKind: .class,
                    status: .modified,
                    memberChanges: [
                        ObjCMemberChange(key: ObjCAPIKey(rawValue: "method:-gain"), kind: .instanceMethod, status: .added, oldSignature: nil, newSignature: "- (void)gain;"),
                        ObjCMemberChange(key: ObjCAPIKey(rawValue: "method:-retype"), kind: .instanceMethod, status: .modified, oldSignature: "- (void)retype;", newSignature: "- (long long)retype;"),
                    ]
                ),
            ],
            protocols: [
                ObjCContainerChange(
                    key: ObjCAPIKey(rawValue: "protocol:Gone"),
                    name: "Gone",
                    containerKind: .protocol,
                    status: .removed,
                    memberChanges: []
                ),
            ],
            diagnostics: ObjCAPIDiffDiagnostics(
                oldSideKeyCollisions: [
                    ObjCAPIKeyCollision(key: ObjCAPIKey(rawValue: "class:Twin"), containerName: nil, droppedSignatures: ["Twin"]),
                ],
                newSideKeyCollisions: []
            )
        )
        let report = ObjCAPIDiffReporter().report(diff)
        let expected = """
        Classes:
          ~ Widget
              + - (void)gain;
              ~ - (void)retype; → - (long long)retype;

        Protocols:
          - Gone

        Warnings — identity-key collisions (first record kept, later ones not compared):
          old · dropped: Twin
        """
        #expect(report == expected)
    }

    @Test func emptyDiffReportsNoChanges() {
        #expect(ObjCAPIDiffReporter().report(ObjCAPIDiff()) == "No ObjC API changes.")
    }

    @Test func evolutionReportRendersTimelineWithBitmaps() throws {
        let baseline = ObjCAPISnapshot(classes: [
            Fixtures.containerSnapshot(key: "class:Widget", name: "Widget", members: [
                Fixtures.record(identity: "method:-run", payload: "enc:v16@0:8", signature: "- (void)run;"),
            ]),
        ])
        let withoutMethod = ObjCAPISnapshot(classes: [
            Fixtures.containerSnapshot(key: "class:Widget", name: "Widget", members: []),
        ])
        let evolution = try ObjCAPIEvolutionBuilder().evolution(
            of: [baseline, withoutMethod],
            versions: [ObjCAPIVersionDescriptor(label: "17.0"), ObjCAPIVersionDescriptor(label: "26.0")]
        )
        let report = ObjCAPIEvolutionReporter().report(evolution)
        let expected = """
        ObjC API evolution across 2 versions: 17.0 → 26.0

        Transitions:
          17.0 → 26.0: 1 removed · API-breaking
        First API-breaking transition: 17.0 → 26.0

        Classes:
          [●●] Widget
              [●○] - (void)run;
                  - removed in 26.0
        """
        #expect(report == expected)
    }

    @Test func evolutionSummaryIsHeaderAndTransitionsOnly() throws {
        let evolution = try ObjCAPIEvolutionBuilder().evolution(
            of: [ObjCAPISnapshot(), ObjCAPISnapshot()],
            versions: [ObjCAPIVersionDescriptor(label: "1"), ObjCAPIVersionDescriptor(label: "2")]
        )
        let summary = ObjCAPIEvolutionReporter().summary(evolution)
        let expected = """
        ObjC API evolution across 2 versions: 1 → 2

        Transitions:
          1 → 2: no changes
        """
        #expect(summary == expected)
    }

    // MARK: - Image groups

    /// AppKit, UIFoundation and CollectionViewCore over three versions:
    /// classes and a category move, one method moves and changes at once,
    /// another only moves, and a selector is declared twice.
    private static func imageGroupEvolution() -> ObjCAPIEvolution {
        func move(_ versionIndex: Int, _ oldImageNames: [String], _ newImageNames: [String]) -> ObjCImageMove {
            ObjCImageMove(versionIndex: versionIndex, oldImageNames: oldImageNames, newImageNames: newImageNames)
        }
        let groupWithoutCollectionViewCore = ["AppKit", "UIFoundation"]
        let fullGroup = ["AppKit", "UIFoundation", "CollectionViewCore"]
        return ObjCAPIEvolution(
            versions: [
                ObjCAPIVersionDescriptor(label: "13.0", imageNames: groupWithoutCollectionViewCore),
                ObjCAPIVersionDescriptor(label: "14.0", imageNames: fullGroup),
                ObjCAPIVersionDescriptor(label: "15.0", imageNames: fullGroup),
            ],
            classes: [
                ObjCContainerLineage(
                    key: ObjCAPIKey(rawValue: "class:NSBar"), name: "NSBar", containerKind: .class,
                    presence: [false, true, true],
                    events: [ObjCLineageEvent(versionIndex: 1, status: .added)],
                    memberLineages: []
                ),
                ObjCContainerLineage(
                    key: ObjCAPIKey(rawValue: "class:NSFoo"), name: "NSFoo", containerKind: .class,
                    presence: [true, true, true],
                    events: [],
                    memberLineages: [],
                    imageMoves: [move(1, ["AppKit"], ["CollectionViewCore"])]
                ),
            ],
            categories: [
                ObjCContainerLineage(
                    key: ObjCAPIKey(rawValue: "category:NSString(Drawing)"), name: "NSString(Drawing)", containerKind: .category,
                    presence: [true, true, true],
                    events: [],
                    memberLineages: [
                        ObjCMemberLineage(
                            key: ObjCAPIKey(rawValue: "method:-leaves"), kind: .instanceMethod,
                            presence: [true, true, true],
                            events: [ObjCLineageEvent(versionIndex: 1, status: .modified, oldSignature: "- (void)leaves;", newSignature: "- (BOOL)leaves;")],
                            imageMoves: [move(1, ["AppKit"], ["UIFoundation"])]
                        ),
                        ObjCMemberLineage(
                            key: ObjCAPIKey(rawValue: "method:-measure"), kind: .instanceMethod,
                            presence: [true, true, true],
                            events: [],
                            imageMoves: [move(2, ["UIFoundation"], ["CollectionViewCore"])],
                            latestSignature: "- (void)measure;"
                        ),
                    ],
                    imageMoves: [
                        move(1, ["AppKit"], ["AppKit", "UIFoundation"]),
                        move(2, ["AppKit", "UIFoundation"], fullGroup),
                    ]
                ),
            ],
            keyCollisionsByVersion: [
                [],
                [],
                [ObjCAPIKeyCollision(
                    key: ObjCAPIKey(rawValue: "method:-draw"),
                    containerName: "NSString(Drawing)",
                    droppedSignatures: ["- (void)draw;"],
                    droppedImageNames: ["CollectionViewCore"]
                )],
            ]
        )
    }

    @Test("An image group's report shows each image's versions, the moves after the events, and the moved count")
    func imageGroupReportShowsImagesAndMoves() {
        let expected = """
        ObjC API evolution across 3 versions: 13.0 → 14.0 → 15.0
        Image group:
          [●●●] AppKit
          [●●●] UIFoundation
          [○●●] CollectionViewCore

        Transitions:
          13.0 → 14.0: 1 added · 1 modified · 3 moved · API-breaking
          14.0 → 15.0: 2 moved · additive
        First API-breaking transition: 13.0 → 14.0

        Classes:
          [○●●] NSBar
              + added in 14.0
          [●●●] NSFoo
              > moved in 14.0: AppKit → CollectionViewCore

        Categories:
          [●●●] NSString(Drawing)
              > moved in 14.0: AppKit → AppKit + UIFoundation
              > moved in 15.0: AppKit + UIFoundation → AppKit + UIFoundation + CollectionViewCore
              [●●●] - (BOOL)leaves;
                  ~ modified in 14.0: - (void)leaves; → - (BOOL)leaves;
                  > moved in 14.0: AppKit → UIFoundation
              [●●●] - (void)measure;
                  > moved in 15.0: UIFoundation → CollectionViewCore

        Warnings — identity-key collisions (first record kept, later ones not compared):
          15.0 · NSString(Drawing) · dropped: - (void)draw; (CollectionViewCore)
        """
        #expect(ObjCAPIEvolutionReporter().report(Self.imageGroupEvolution()) == expected)
    }

    @Test("An image group's summary keeps the image group under the header")
    func imageGroupSummaryKeepsTheImageGroup() {
        let expected = """
        ObjC API evolution across 3 versions: 13.0 → 14.0 → 15.0
        Image group:
          [●●●] AppKit
          [●●●] UIFoundation
          [○●●] CollectionViewCore

        Transitions:
          13.0 → 14.0: 1 added · 1 modified · 3 moved · API-breaking
          14.0 → 15.0: 2 moved · additive
        First API-breaking transition: 13.0 → 14.0
        """
        #expect(ObjCAPIEvolutionReporter().summary(Self.imageGroupEvolution()) == expected)
    }
}
