import Testing
import Foundation
import MachOKit
import ObjCDeclarationRendering
import ObjCIndexing
import Semantic
@testable import ObjCInterface

/// A marked rendering, projected to any combination of the ten switches,
/// reads exactly as the plain rendering with those switches — checked for
/// every class, protocol and category of Foundation. RuntimeViewer's Find
/// searches one marked rendering per declaration under whatever switches the
/// user displays with, so this is the contract it stands on.
@Suite("Marked ObjC interfaces")
struct ObjCMarkedInterfaceTests {
    private typealias VisibilityOption = ObjCGenerationOptions.VisibilityOption

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

    /// Everything off, everything on, each switch alone, each switch left
    /// out, and the strip and comment halves on their own.
    private static let optionCombinations: [ObjCGenerationOptions] = {
        let allOptions = Set(VisibilityOption.allCases)
        var combinations = [options(enabling: []), options(enabling: allOptions)]
        for option in VisibilityOption.allCases {
            combinations.append(options(enabling: [option]))
            combinations.append(options(enabling: allOptions.subtracting([option])))
        }
        combinations.append(options(enabling: allOptions.filter { $0.rawValue.hasPrefix("objc.strip") }))
        combinations.append(options(enabling: allOptions.filter { $0.rawValue.hasPrefix("objc.add") }))
        return combinations
    }()

    /// The plain rendering a marked one reads as before any projection:
    /// nothing stripped, every comment added.
    private static let everythingShown = options(enabling: Set(VisibilityOption.allCases.filter { $0.rawValue.hasPrefix("objc.add") }))

    private static func makeBuilder() async throws -> (builder: ObjCInterfaceBuilder<MachOImage>, indexer: ObjCInterfaceIndexer<MachOImage>) {
        let (indexer, machO) = try await ObjCInterfaceTests.SharedFixture.shared.load()
        return (ObjCInterfaceBuilder(indexer: indexer, machO: machO), indexer)
    }

    /// Compares every declaration's projections with its plain renderings
    /// and returns the first few that differ, described.
    private static func mismatches(
        of names: [String],
        marked: (String) -> SemanticString?,
        plain: (String, ObjCGenerationOptions) -> SemanticString?
    ) -> [String] {
        var mismatches: [String] = []
        for name in names {
            guard let markedRendering = marked(name) else {
                mismatches.append("\(name): no marked rendering")
                continue
            }
            let separated = markedRendering.frozen().separatingVisibilityRegions()
            if let everything = plain(name, everythingShown)?.frozen(), separated.text != everything {
                mismatches.append("\(name): the marked rendering does not read as everything shown")
            }
            for options in optionCombinations {
                let projected = separated.regions.projection(of: separated.text, where: options.isVisibilityOptionEnabled).text
                guard let rendered = plain(name, options)?.frozen() else { continue }
                if projected != rendered {
                    mismatches.append("\(name) under \(VisibilityOption.allCases.filter(options.isEnabled).map(\.rawValue)):\n\(projected.string)\n--- expected ---\n\(rendered.string)")
                    break
                }
            }
            if mismatches.count >= 5 { break }
        }
        return mismatches
    }

    @Test("every class projects to its plain rendering under every switch combination")
    func classes() async throws {
        let (builder, indexer) = try await Self.makeBuilder()
        let mismatches = Self.mismatches(of: indexer.classNames) {
            builder.markedClassInterface(named: $0)
        } plain: {
            builder.classInterface(named: $0, options: $1)
        }
        #expect(mismatches.isEmpty, "\(mismatches.joined(separator: "\n\n"))")
    }

    @Test("every protocol projects to its plain rendering under every switch combination")
    func protocols() async throws {
        let (builder, indexer) = try await Self.makeBuilder()
        let mismatches = Self.mismatches(of: indexer.protocolNames) {
            builder.markedProtocolInterface(named: $0)
        } plain: {
            builder.protocolInterface(named: $0, options: $1)
        }
        #expect(mismatches.isEmpty, "\(mismatches.joined(separator: "\n\n"))")
    }

    @Test("every category projects to its plain rendering under every switch combination")
    func categories() async throws {
        let (builder, indexer) = try await Self.makeBuilder()
        let mismatches = Self.mismatches(of: indexer.categoryNames) {
            builder.markedCategoryInterface(uniqueName: $0)
        } plain: {
            builder.categoryInterface(uniqueName: $0, options: $1)
        }
        #expect(mismatches.isEmpty, "\(mismatches.joined(separator: "\n\n"))")
    }

    @Test("a customized ivar offset comment and C type spelling project the same way")
    func transformedRendering() async throws {
        let (builder, indexer) = try await Self.makeBuilder()
        let replacements: [ObjCPrimitiveTypePattern: String] = [.double: "CGFloat"]
        let offsetComment: @Sendable (Int) -> String = { "at byte \($0)" }
        let classesWithIvars = indexer.classNames.filter { indexer.classGroup(forName: $0)?.info.first?.ivars.isEmpty == false }.prefix(200)
        let mismatches = Self.mismatches(of: Array(classesWithIvars)) {
            builder.markedClassInterface(named: $0, cTypeReplacements: replacements, ivarOffsetCommentBuilder: offsetComment)
        } plain: {
            builder.classInterface(named: $0, options: $1, cTypeReplacements: replacements, ivarOffsetCommentBuilder: offsetComment)
        }
        #expect(mismatches.isEmpty, "\(mismatches.joined(separator: "\n\n"))")
    }
}
