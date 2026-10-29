import ObjCDiffing
import Semantic
import Testing
@testable import ObjCInterface

/// The format rules of the evolution interface, on synthetic lines: what an
/// annotation says, when an availability macro can be written, and how the
/// annotations line up. The rendering of real declarations is pinned by
/// `ObjCEvolutionInterfaceBuilderTests`.
@Suite("Evolution interface marking")
struct ObjCEvolutionMarkingTests {
    private typealias Event = ObjCEvolutionAnnotation.Event

    private static let threeVersions = ["12.0.1", "13.0", "14.0"].map { ObjCAPIVersionDescriptor(label: $0) }
    private static let twoVersions = ["12.0", "13.0"].map { ObjCAPIVersionDescriptor(label: $0) }

    private static func line(_ text: String, indentLevel: Int = 0, annotation: ObjCEvolutionAnnotation? = nil) -> ObjCEvolutionLine {
        ObjCEvolutionLine(content: SemanticString(stringLiteral: text), indentLevel: indentLevel, annotation: annotation)
    }

    private static let addedInSecondVersion = ObjCEvolutionAnnotation(
        subject: nil,
        presence: [false, true],
        events: [Event(versionIndex: 1, change: .added)]
    )

    // MARK: - Annotation text

    @Test("A bitmap has one position per version")
    func bitmap() {
        #expect(ObjCEvolutionMarking.bitmap([true, false, true]) == "[●○●]")
    }

    @Test("Events are phrased against the axis and joined in order")
    func eventsAreJoined() {
        let annotation = ObjCEvolutionAnnotation(
            subject: nil,
            presence: [true, false, true],
            events: [Event(versionIndex: 1, change: .removed), Event(versionIndex: 2, change: .added)]
        )
        #expect(ObjCEvolutionMarking.annotationText(for: annotation, versions: Self.threeVersions) == "// [●○●] removed in 13.0 · added in 14.0")
    }

    @Test("A modified event shows its two sides only when they differ")
    func modifiedPhrase() {
        let differing = Event(versionIndex: 1, change: .modified(old: "- (id)title;", new: "- (NSString *)title;"))
        let identical = Event(versionIndex: 1, change: .modified(old: "- (id)title;", new: "- (id)title;"))
        let unknown = Event(versionIndex: 2, change: .modified(old: nil, new: nil))
        #expect(ObjCEvolutionMarking.phrase(for: differing, versions: Self.threeVersions) == "modified in 13.0: - (id)title; → - (NSString *)title;")
        #expect(ObjCEvolutionMarking.phrase(for: identical, versions: Self.threeVersions) == "modified in 13.0")
        #expect(ObjCEvolutionMarking.phrase(for: unknown, versions: Self.threeVersions) == "modified in 14.0")
    }

    @Test("A subject leads an annotation that stands on a line of its own")
    func subjectLeads() {
        let annotation = ObjCEvolutionAnnotation(
            subject: "adopts <NSCoding>",
            presence: [true, true, false],
            events: [Event(versionIndex: 2, change: .removed)]
        )
        #expect(ObjCEvolutionMarking.annotationText(for: annotation, versions: Self.threeVersions) == "// [●●○] adopts <NSCoding> removed in 14.0")
    }

    // MARK: - Availability

    struct AvailabilityCase: Sendable, CustomTestStringConvertible {
        let presence: [Bool]
        let labels: [String]
        let expectedMacro: String?

        var testDescription: String {
            ObjCEvolutionMarking.bitmap(presence) + " over " + labels.joined(separator: ", ")
        }
    }

    @Test("An availability macro is written only when it tells the whole story", arguments: [
        AvailabilityCase(presence: [false, true, true], labels: ["12.0.1", "13.0", "14.0"], expectedMacro: "API_AVAILABLE(macos(13.0))"),
        AvailabilityCase(presence: [false, false, true], labels: ["12.0", "13.0", "14.0.1"], expectedMacro: "API_AVAILABLE(macos(14.0.1))"),
        AvailabilityCase(presence: [false, true, false], labels: ["12.0.1", "13.0", "14.0"], expectedMacro: "API_OBSOLETED(\"Removed\", macos(13.0, 14.0, 14.0))"),
        // Present from the axis start: the introduction is unknown.
        AvailabilityCase(presence: [true, true, false], labels: ["12.0.1", "13.0", "14.0"], expectedMacro: nil),
        AvailabilityCase(presence: [true, true, true], labels: ["12.0.1", "13.0", "14.0"], expectedMacro: nil),
        // Two presence runs fit no single macro.
        AvailabilityCase(presence: [false, true, false, true], labels: ["12.0", "13.0", "14.0", "15.0"], expectedMacro: nil),
        // A label that is not a version cannot become one.
        AvailabilityCase(presence: [false, true, true], labels: ["12.0.1", "13.0 beta", "14.0"], expectedMacro: nil),
        AvailabilityCase(presence: [false, true, false], labels: ["12.0.1", "13.0", "AppKit-2"], expectedMacro: nil),
    ])
    func availabilityMacro(_ availabilityCase: AvailabilityCase) {
        let versions = availabilityCase.labels.map { ObjCAPIVersionDescriptor(label: $0) }
        #expect(ObjCEvolutionMarking.availabilityMacro(presence: availabilityCase.presence, versions: versions, platform: "macos") == availabilityCase.expectedMacro)
    }

    @Test("A member's availability macro goes before its closing semicolon")
    func macroBeforeSemicolon() {
        let declaration = SemanticString(stringLiteral: "- (void)reloadData;")
        #expect(
            ObjCEvolutionMarking.declaration(declaration, withAvailabilityMacro: "API_AVAILABLE(macos(13.0))").string
                == "- (void)reloadData API_AVAILABLE(macos(13.0));"
        )
        #expect(ObjCEvolutionMarking.declaration(declaration, withAvailabilityMacro: nil).string == "- (void)reloadData;")
    }

    // MARK: - Lines

    @Test("A rendering splits into its lines, empty ones included")
    func splitsIntoLines() {
        let lines = ObjCEvolutionMarking.lines(of: SemanticString(stringLiteral: "struct {\n    int a;\n\n} _flags;"))
        #expect(lines.map(\.string) == ["struct {", "    int a;", "", "} _flags;"])
        #expect(ObjCEvolutionMarking.lines(of: SemanticString()).isEmpty)
    }

    @Test("A multi-line rendering reads as one line in a modified phrase")
    func collapsesToOneLine() {
        #expect(ObjCEvolutionMarking.singleLine(SemanticString(stringLiteral: "struct {\n        int a;\n    } _flags;")) == "struct { int a; } _flags;")
    }

    // MARK: - Layout

    @Test("Annotations align one gutter past the longest annotated line")
    func annotationsAlign() {
        let block = [
            Self.line("- (void)a;", annotation: Self.addedInSecondVersion),
            Self.line("- (void)longer;", annotation: Self.addedInSecondVersion),
        ]
        #expect(
            ObjCEvolutionMarking.renderBlock(block, versions: Self.twoVersions).string
                == "- (void)a;       // [○●] added in 13.0\n- (void)longer;  // [○●] added in 13.0"
        )
    }

    @Test("An annotation that does not fit before the column cap moves to the next line")
    func annotationMovesToNextLine() {
        // 4 spaces of indentation and 67 characters: 71 columns, one short of
        // leaving the gutter before column 72.
        let longDeclaration = String(repeating: "x", count: 66) + ";"
        let block = [Self.line(longDeclaration, indentLevel: 1, annotation: Self.addedInSecondVersion)]
        #expect(
            ObjCEvolutionMarking.renderBlock(block, versions: Self.twoVersions).string
                == "    " + longDeclaration + "\n        // [○●] added in 13.0"
        )
    }

    @Test("Empty lines write nothing, and an ivar block keeps its indentation")
    func emptyLinesAndIndentation() {
        let block = [
            Self.line("@interface Example : NSObject {"),
            Self.line("int _count;", indentLevel: 1),
            Self.line("}"),
            ObjCEvolutionLine.blank,
            Self.line("@end"),
        ]
        #expect(
            ObjCEvolutionMarking.renderBlock(block, versions: Self.twoVersions).string
                == "@interface Example : NSObject {\n    int _count;\n}\n\n@end"
        )
    }

    // MARK: - Document

    @Test("The legend names the axis, and the availability note only when macros are on")
    func legend() {
        let plainLegend = ObjCEvolutionMarking.legendLines(versions: Self.threeVersions, availabilityPlatform: nil).string
        #expect(plainLegend == "// ObjC API evolution across 3 versions: 12.0.1 → 13.0 → 14.0\n// Bitmap positions: [1] 12.0.1  [2] 13.0  [3] 14.0")
        let legendWithMacros = ObjCEvolutionMarking.legendLines(versions: Self.threeVersions, availabilityPlatform: "macos").string
        #expect(legendWithMacros.hasPrefix(plainLegend + "\n// API_AVAILABLE and API_OBSOLETED versions are axis points"))
    }

    @Test("Identity-key collisions are listed as the lineage report lists them")
    func collisionWarnings() {
        let evolution = ObjCAPIEvolution(
            versions: Self.twoVersions,
            keyCollisionsByVersion: [
                [],
                [ObjCAPIKeyCollision(key: ObjCAPIKey(rawValue: "class:Duplicate"), containerName: nil, droppedSignatures: ["Duplicate"])],
            ]
        )
        #expect(
            ObjCEvolutionMarking.warningsLines(for: evolution)?.string
                == "// Warnings — identity-key collisions (first record kept, later ones not compared):\n//   13.0 · dropped: Duplicate"
        )
        #expect(ObjCEvolutionMarking.warningsLines(for: ObjCAPIEvolution(versions: Self.twoVersions)) == nil)
    }

    // MARK: - Image groups

    @Test("A move names each side's images, and follows an event at its version")
    func movePhrase() {
        let annotation = ObjCEvolutionAnnotation(
            subject: nil,
            presence: [true, true, true],
            events: [
                Event(versionIndex: 1, change: .modified(old: nil, new: nil)),
                Event(versionIndex: 1, change: .moved(ObjCImageMove(versionIndex: 1, oldImageNames: ["AppKit"], newImageNames: ["AppKit", "UIFoundation"]))),
            ]
        )
        #expect(
            ObjCEvolutionMarking.annotationText(for: annotation, versions: Self.threeVersions)
                == "// [●●●] modified in 13.0 · moved in 13.0: AppKit → AppKit + UIFoundation"
        )
    }

    @Test("The legend lists each image of a group under the bitmap positions, before the availability note")
    func imageGroupLegend() {
        let versions = [
            ObjCAPIVersionDescriptor(label: "12.0", imageNames: ["AppKit", "UIFoundation"]),
            ObjCAPIVersionDescriptor(label: "13.0", imageNames: ["AppKit", "UIFoundation", "CollectionViewCore"]),
        ]
        let legend = ObjCEvolutionMarking.legendLines(versions: versions, availabilityPlatform: "macos").string
        #expect(legend.hasPrefix("""
        // ObjC API evolution across 2 versions: 12.0 → 13.0
        // Bitmap positions: [1] 12.0  [2] 13.0
        // Image group:
        //   [●●] AppKit
        //   [●●] UIFoundation
        //   [○●] CollectionViewCore
        // API_AVAILABLE and API_OBSOLETED versions are axis points
        """))
    }

    @Test("A collision in an image group names the image of each dropped record")
    func imageGroupCollisionWarnings() {
        let evolution = ObjCAPIEvolution(
            versions: Self.twoVersions,
            keyCollisionsByVersion: [
                [],
                [ObjCAPIKeyCollision(key: ObjCAPIKey(rawValue: "class:Duplicate"), containerName: nil, droppedSignatures: ["Duplicate"], droppedImageNames: ["UIFoundation"])],
            ]
        )
        #expect(
            ObjCEvolutionMarking.warningsLines(for: evolution)?.string
                == "// Warnings — identity-key collisions (first record kept, later ones not compared):\n//   13.0 · dropped: Duplicate (UIFoundation)"
        )
    }
}
