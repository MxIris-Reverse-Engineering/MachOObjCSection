import Testing
import MachOKit
import ObjCDeclarationRendering
import ObjCIndexing
import Semantic
@testable import ObjCInterface

/// A builder made with `marksCommentStructure`, over every declaration of
/// Foundation: separating the marks gives back exactly what the builder
/// renders without them, plain and marked alike, so a host can turn the
/// switch on without anything else about the output changing.
@Suite("Comment structure marking across Foundation")
struct ObjCCommentStructureMarkingTests {
    private static let everyComment = ObjCGenerationOptions(
        addIvarOffsetComments: true,
        addPropertyAttributesComments: true,
        addMethodIMPAddressComments: true,
        addPropertyAccessorAddressComments: true
    )

    private static func makeBuilders() async throws -> (plain: ObjCInterfaceBuilder<MachOImage>, marking: ObjCInterfaceBuilder<MachOImage>, indexer: ObjCInterfaceIndexer<MachOImage>) {
        let (indexer, machO) = try await ObjCInterfaceTests.SharedFixture.shared.load()
        return (
            ObjCInterfaceBuilder(indexer: indexer, machO: machO),
            ObjCInterfaceBuilder(indexer: indexer, machO: machO, marksCommentStructure: true),
            indexer
        )
    }

    /// The first few declarations whose marked rendering, its marks
    /// separated, is not the rendering without them, described; and the
    /// kinds of comment the marked renderings carry.
    private static func check(
        _ names: [String],
        marking: (String) -> SemanticString?,
        plain: (String) -> SemanticString?
    ) -> (mismatches: [String], kinds: Set<AnnotationRegion.Kind>) {
        var mismatches: [String] = []
        var kinds: Set<AnnotationRegion.Kind> = []
        for name in names {
            guard let markedRendering = marking(name), let plainRendering = plain(name) else {
                mismatches.append("\(name): no rendering")
                continue
            }
            let (separated, annotations) = markedRendering.frozen().separatingAnnotationRegions()
            kinds.formUnion(annotations.regions.map(\.kind))
            if separated != plainRendering.frozen() {
                mismatches.append("\(name):\n\(separated.string)\n--- expected ---\n\(plainRendering.string)")
            }
            if mismatches.count >= 5 { break }
        }
        return (mismatches, kinds)
    }

    @Test("Every declaration separates to its rendering without marks")
    func plainRenderings() async throws {
        let (plain, marking, indexer) = try await Self.makeBuilders()
        let checks = [
            Self.check(indexer.classNames) {
                marking.classInterface(named: $0, options: Self.everyComment)
            } plain: {
                plain.classInterface(named: $0, options: Self.everyComment)
            },
            Self.check(indexer.protocolNames) {
                marking.protocolInterface(named: $0, options: Self.everyComment)
            } plain: {
                plain.protocolInterface(named: $0, options: Self.everyComment)
            },
            Self.check(indexer.categoryNames) {
                marking.categoryInterface(uniqueName: $0, options: Self.everyComment)
            } plain: {
                plain.categoryInterface(uniqueName: $0, options: Self.everyComment)
            },
            Self.check(indexer.structNames) { marking.structInterface(named: $0) } plain: { plain.structInterface(named: $0) },
            Self.check(indexer.unionNames) { marking.unionInterface(named: $0) } plain: { plain.unionInterface(named: $0) },
        ]
        let mismatches = checks.flatMap(\.mismatches)
        let kinds = checks.reduce(into: Set<AnnotationRegion.Kind>()) { $0.formUnion($1.kinds) }

        #expect(mismatches.isEmpty, "\(mismatches.joined(separator: "\n\n"))")
        // The comparison proves something only if there were comments to mark.
        #expect(kinds.isSuperset(of: [.impAddress, .ivarOffset, .propertySynthesis, .typeNote]), "\(kinds.map(\.rawValue).sorted())")
    }

    /// A marked rendering carries `VisibilityRegion`s, and a class the export
    /// filter leaves out is marked visible only with the filter off after it
    /// is rendered, over the comment marks.
    @Test("Every marked rendering separates to the marked rendering without comment marks")
    func markedRenderings() async throws {
        let (plain, marking, indexer) = try await Self.makeBuilders()
        let checks = [
            Self.check(indexer.classNames) { marking.markedClassInterface(named: $0) } plain: { plain.markedClassInterface(named: $0) },
            Self.check(indexer.protocolNames) { marking.markedProtocolInterface(named: $0) } plain: { plain.markedProtocolInterface(named: $0) },
            Self.check(indexer.categoryNames) { marking.markedCategoryInterface(uniqueName: $0) } plain: { plain.markedCategoryInterface(uniqueName: $0) },
        ]
        let unexportedClassCount = indexer.classNames.count { indexer.exportStatus(ofClassNamed: $0)?.isDefinitelyNotExported == true }

        #expect(checks.flatMap(\.mismatches).isEmpty, "\(checks.flatMap(\.mismatches).joined(separator: "\n\n"))")
        #expect(unexportedClassCount > 0, "no class of Foundation is left out by the export filter")
    }
}
