import Testing
import Foundation
import MachOKit
import MachOObjCSection
import ObjCDeclarationRendering
import ObjCDiffing
import ObjCDump
import ObjCIndexing
import ObjCInterface
import ObjCMetadataSource
import Semantic

/// How the classes a host supplies render, and that they reach the API
/// snapshot (proposal "host-supplied classes").
@Suite("Supplied classes in declarations and snapshots")
struct SuppliedClassRenderingTests {
    private typealias VisibilityOption = ObjCGenerationOptions.VisibilityOption

    private static func templateIndexer() async throws -> (indexer: ObjCInterfaceIndexer<MachOFile>, machO: MachOFile, suppliedClass: ObjCSuppliedClass) {
        let machO = try SuppliedClassFixture.loadMachOFile(at: try TemplateReadOnlyDataFixture.libraryURL())
        let suppliedClass = TemplateReadOnlyDataFixture.suppliedClass(
            readOnlyDataOffset: try SuppliedClassFixture.fileOffset(ofSymbolNamed: "_" + TemplateReadOnlyDataFixture.readOnlyDataSymbolName, in: machO),
            metaclassReadOnlyDataOffset: try SuppliedClassFixture.fileOffset(ofSymbolNamed: "_" + TemplateReadOnlyDataFixture.metaclassReadOnlyDataSymbolName, in: machO)
        )
        let indexer = ObjCInterfaceIndexer(machO: machO, imagePath: machO.imagePath, suppliedClasses: [suppliedClass])
        try await indexer.prepare()
        return (indexer, machO, suppliedClass)
    }

    @Test("A supplied class renders under a line naming its kind")
    func kindComment() async throws {
        let (indexer, machO, suppliedClass) = try await Self.templateIndexer()
        let builder = ObjCInterfaceBuilder(indexer: indexer, machO: machO)

        let lines = try #require(builder.classInterface(named: suppliedClass.name)).string.components(separatedBy: "\n")
        #expect(lines.first == "// Generic Swift class, instantiated at runtime")
        #expect(lines.dropFirst().first?.hasPrefix("@interface TemplateFixture.TemplateClass<A> : NSObject") == true)

        let markedLines = try #require(builder.markedClassInterface(named: suppliedClass.name)).string.components(separatedBy: "\n")
        #expect(markedLines.first == "// Generic Swift class, instantiated at runtime")
    }

    @Test("The kind comment names each kind")
    func kindCommentForEachKind() async throws {
        let (_, machO, templateClass) = try await Self.templateIndexer()
        let kinds: [(ObjCSuppliedClass.Kind, String)] = [
            (.genericSwiftClass, "// Generic Swift class, instantiated at runtime"),
            (.swiftClassWithResilientAncestry, "// Swift class with resilient ancestry, registered through __objc_stublist"),
            (.swiftClassWithGenericAncestry, "// Swift class with generic ancestry, registered through __objc_stublist"),
        ]
        for (kind, comment) in kinds {
            var suppliedClass = templateClass
            suppliedClass.kind = kind
            let indexer = ObjCInterfaceIndexer(machO: machO, imagePath: machO.imagePath, suppliedClasses: [suppliedClass])
            try await indexer.prepare()
            let rendering = ObjCInterfaceBuilder(indexer: indexer, machO: machO).classInterface(named: suppliedClass.name)
            #expect(rendering?.string.components(separatedBy: "\n").first == comment)
        }
    }

    @Test("An ivar of unknown offset says so, whatever builds the other offsets' comments")
    func unknownOffsetComment() async throws {
        let (indexer, machO, suppliedClass) = try await Self.templateIndexer()
        let builder = ObjCInterfaceBuilder(indexer: indexer, machO: machO)
        var options = ObjCGenerationOptions.default
        options.addIvarOffsetComments = true

        let rendering = try #require(builder.classInterface(named: suppliedClass.name, options: options)).string
        #expect(rendering.contains("knownField; // offset: 8\n"))
        #expect(rendering.contains("unknownField; // offset: unknown\n"))

        // Rendered outside `#require`, whose expansion cannot pass a closure on.
        let customInterface = builder.classInterface(named: suppliedClass.name, options: options, ivarOffsetCommentBuilder: { "at \($0)" })
        let customRendering = try #require(customInterface).string
        #expect(customRendering.contains("knownField; // at 8\n"))
        #expect(customRendering.contains("unknownField; // offset: unknown\n"))

        options.addIvarOffsetComments = false
        let uncommented = try #require(builder.classInterface(named: suppliedClass.name, options: options)).string
        #expect(uncommented.contains("unknownField;\n"))
        #expect(!uncommented.contains("offset"))
    }

    /// The contract of proposal 0011, for a supplied class: its marked
    /// rendering, projected to some switches, reads as the plain rendering
    /// with those switches.
    @Test("A supplied class's marked rendering projects to its plain renderings")
    func markedRenderingProjects() async throws {
        let (templateIndexer, templateMachO, templateClass) = try await Self.templateIndexer()
        #expect(Self.projectionMismatches(of: templateClass.name, builder: ObjCInterfaceBuilder(indexer: templateIndexer, machO: templateMachO)) == [])

        // A stand-in for one of Foundation's classes, under a superclass of
        // Foundation's, so that `stripOverrides` has members to strip.
        let image = try #require(MachOImage(name: "Foundation"))
        let plainIndexer = ObjCInterfaceIndexer(machO: image, imagePath: image.imagePath)
        try await plainIndexer.prepare()
        let sourceGroup = try #require(plainIndexer.classGroup(forName: "NSMutableString"))
        let sourceClass = try #require(sourceGroup.objcClass as? ObjCClass64)
        let readOnlyData = try #require(StandInScenario.readOnlyData(of: sourceClass, in: image))
        let (metaclassImage, metaclass) = try #require(sourceClass.metaClass(in: image))
        let metaclassReadOnlyData = try #require(StandInScenario.readOnlyData(of: metaclass, in: metaclassImage))
        let standIn = ObjCSuppliedClass(
            name: "SuppliedMutableString",
            superClassName: "NSString",
            readOnlyDataOffset: readOnlyData.offset,
            metaclassReadOnlyDataOffset: metaclassReadOnlyData.offset,
            kind: .swiftClassWithResilientAncestry
        )
        let indexer = ObjCInterfaceIndexer(machO: image, imagePath: image.imagePath, suppliedClasses: [standIn])
        try await indexer.prepare()
        #expect((indexer.suppliedClassGroup(forName: standIn.name)?.info.count ?? 0) > 1)
        #expect(Self.projectionMismatches(of: standIn.name, builder: ObjCInterfaceBuilder(indexer: indexer, machO: image)) == [])
    }

    @Test("The API snapshot holds the supplied classes")
    func snapshotHoldsSuppliedClasses() async throws {
        let (indexer, _, suppliedClass) = try await Self.templateIndexer()
        let snapshotBuilder = ObjCAPISnapshotBuilder(indexer: indexer)

        let moduleClass = try #require(snapshotBuilder.module().classes.first)
        #expect(moduleClass == indexer.suppliedClassGroup(forName: suppliedClass.name)?.info.first)
        #expect(snapshotBuilder.snapshot().classes.map(\.name) == [suppliedClass.name])
    }

    // MARK: - Projection

    private static func options(enabling enabled: Set<VisibilityOption>) -> ObjCGenerationOptions {
        ObjCGenerationOptions(
            stripProtocolConformance: enabled.contains(.stripProtocolConformance),
            stripOverrides: enabled.contains(.stripOverrides),
            stripSynthesizedIvars: enabled.contains(.stripSynthesizedIvars),
            stripSynthesizedMethods: enabled.contains(.stripSynthesizedMethods),
            stripCtorMethod: enabled.contains(.stripCtorMethod),
            stripDtorMethod: enabled.contains(.stripDtorMethod),
            addIvarOffsetComments: enabled.contains(.addIvarOffsetComments),
            addPropertyAttributesComments: enabled.contains(.addPropertyAttributesComments),
            addMethodIMPAddressComments: enabled.contains(.addMethodIMPAddressComments),
            addPropertyAccessorAddressComments: enabled.contains(.addPropertyAccessorAddressComments)
        )
    }

    /// Everything off, everything on, and each switch alone.
    private static let optionCombinations: [ObjCGenerationOptions] =
        [options(enabling: []), options(enabling: Set(VisibilityOption.allCases))]
            + VisibilityOption.allCases.map { options(enabling: [$0]) }

    private static func projectionMismatches<MachO: ObjCMetadataSource>(of name: String, builder: ObjCInterfaceBuilder<MachO>) -> [String] {
        guard let marked = builder.markedClassInterface(named: name) else { return ["\(name): no marked rendering"] }
        let separated = marked.frozen().separatingVisibilityRegions()
        var mismatches: [String] = []
        for options in optionCombinations {
            let projected = separated.regions.projection(of: separated.text, where: options.isVisibilityOptionEnabled).text
            guard let plain = builder.classInterface(named: name, options: options)?.frozen() else {
                mismatches.append("\(name): no plain rendering")
                continue
            }
            if projected != plain {
                mismatches.append("\(name) under \(VisibilityOption.allCases.filter(options.isEnabled).map(\.rawValue)):\n\(projected.string)\n--- expected ---\n\(plain.string)")
            }
        }
        return mismatches
    }
}
