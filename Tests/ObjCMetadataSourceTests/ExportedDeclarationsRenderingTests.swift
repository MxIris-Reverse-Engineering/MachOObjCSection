import Testing
import Foundation
import MachOKit
import ObjCDeclarationRendering
import ObjCIndexing
import ObjCInterface
import ObjCMetadataSource
import Semantic

/// `printExportedDeclarationsOnly` on the compiled fixtures: what a plain
/// rendering leaves out, and that a marked rendering projects to it under
/// every combination of the switches, in both modes.
@Suite("Printing exported declarations only")
struct ExportedDeclarationsRenderingTests {
    private typealias SwiftClassName = ExportedDeclarationsFixture.SwiftClassName
    private typealias ObjectiveCName = ExportedDeclarationsFixture.ObjectiveCName
    private typealias VisibilityOption = ObjCGenerationOptions.VisibilityOption

    private static let exportedOnly = ObjCGenerationOptions(printExportedDeclarationsOnly: true)

    private static func preparedBuilder<MachO: ObjCMetadataSource>(of machO: MachO) async throws -> (builder: ObjCInterfaceBuilder<MachO>, indexer: ObjCInterfaceIndexer<MachO>) {
        let indexer = ObjCInterfaceIndexer(machO: machO, imagePath: machO.imagePath)
        try await indexer.prepare()
        return (ObjCInterfaceBuilder(indexer: indexer, machO: machO), indexer)
    }

    // MARK: - Plain Rendering

    private static func expectSwiftImageFiltered<MachO: ObjCMetadataSource>(in machO: MachO) async throws {
        let (builder, _) = try await preparedBuilder(of: machO)

        for className in [SwiftClassName.internalSwiftRoot, SwiftClassName.internalObjCSubclass] {
            let rendering = try #require(builder.classInterface(named: className, options: exportedOnly), "\(className)")
            #expect(rendering.string.isEmpty, "\(className) should render empty:\n\(rendering.string)")
            #expect(builder.classInterface(named: className)?.string.isEmpty == false, "\(className) without the switch")
        }
        for className in [SwiftClassName.publicSwiftRoot, SwiftClassName.publicObjCSubclass] {
            let everything = try #require(builder.classInterface(named: className)?.string, "\(className)")
            let exported = try #require(builder.classInterface(named: className, options: exportedOnly)?.string, "\(className)")
            #expect(everything.contains("internalValue") && everything.contains("publicValue"), "\(className):\n\(everything)")
            #expect(exported.contains("publicValue"), "\(className):\n\(exported)")
            #expect(!exported.contains("internalValue"), "\(className):\n\(exported)")
        }
    }

    private static func expectObjectiveCImageFiltered<MachO: ObjCMetadataSource>(in machO: MachO) async throws {
        let (builder, _) = try await preparedBuilder(of: machO)

        let hidden = try #require(builder.classInterface(named: ObjectiveCName.hiddenClass, options: exportedOnly))
        #expect(hidden.string.isEmpty, "\(hidden.string)")

        let everything = try #require(builder.classInterface(named: ObjectiveCName.exportedClass)?.string)
        let exported = try #require(builder.classInterface(named: ObjectiveCName.exportedClass, options: exportedOnly)?.string)
        #expect(everything.contains("privateIvar") && everything.contains("publicIvar"), "\(everything)")
        #expect(exported.contains("publicIvar"), "\(exported)")
        #expect(!exported.contains("privateIvar"), "\(exported)")

        let categoryOnHiddenClass = try #require(builder.categoryInterface(uniqueName: ObjectiveCName.categoryOnHiddenClass, options: exportedOnly))
        #expect(categoryOnHiddenClass.string.isEmpty, "\(categoryOnHiddenClass.string)")
        for categoryName in [ObjectiveCName.categoryOnExportedClass, ObjectiveCName.categoryOnAnotherImagesClass] {
            let category = try #require(builder.categoryInterface(uniqueName: categoryName, options: exportedOnly), "\(categoryName)")
            #expect(category.string == builder.categoryInterface(uniqueName: categoryName)?.string, "\(categoryName) should stay whole")
        }
    }

    @Test("The Swift image without what it does not export, read from the file")
    func swiftImageInFile() async throws {
        try await Self.expectSwiftImageFiltered(in: try ExportedDeclarationsFixture.swiftLibraryFile())
    }

    @Test("The Swift image without what it does not export, loaded")
    func swiftImageLoaded() async throws {
        try await Self.expectSwiftImageFiltered(in: try ExportedDeclarationsFixture.swiftLibraryImage())
    }

    @Test("The Objective-C image without what it does not export, read from the file")
    func objectiveCImageInFile() async throws {
        try await Self.expectObjectiveCImageFiltered(in: try ExportedDeclarationsFixture.objectiveCLibraryFile())
    }

    @Test("The Objective-C image without what it does not export, loaded")
    func objectiveCImageLoaded() async throws {
        try await Self.expectObjectiveCImageFiltered(in: try ExportedDeclarationsFixture.objectiveCLibraryImage())
    }

    // MARK: - Marked Rendering

    /// Every combination of the switches the Foundation-wide projection test
    /// tries: everything off, everything on, each switch alone, each left out.
    private static let optionCombinations: [ObjCGenerationOptions] = {
        func options(enabling enabled: Set<VisibilityOption>) -> ObjCGenerationOptions {
            var options = ObjCGenerationOptions()
            options.stripProtocolConformance = enabled.contains(.stripProtocolConformance)
            options.stripOverrides = enabled.contains(.stripOverrides)
            options.stripSynthesizedIvars = enabled.contains(.stripSynthesizedIvars)
            options.stripSynthesizedMethods = enabled.contains(.stripSynthesizedMethods)
            options.stripCtorMethod = enabled.contains(.stripCtorMethod)
            options.stripDtorMethod = enabled.contains(.stripDtorMethod)
            options.addIvarOffsetComments = enabled.contains(.addIvarOffsetComments)
            options.addPropertyAttributesComments = enabled.contains(.addPropertyAttributesComments)
            options.addMethodIMPAddressComments = enabled.contains(.addMethodIMPAddressComments)
            options.addPropertyAccessorAddressComments = enabled.contains(.addPropertyAccessorAddressComments)
            options.printExportedDeclarationsOnly = enabled.contains(.printExportedDeclarationsOnly)
            return options
        }
        let allOptions = Set(VisibilityOption.allCases)
        var combinations = [options(enabling: []), options(enabling: allOptions)]
        for option in VisibilityOption.allCases {
            combinations.append(options(enabling: [option]))
            combinations.append(options(enabling: allOptions.subtracting([option])))
        }
        return combinations
    }()

    /// The first few declarations whose marked rendering does not project to
    /// their plain rendering, described; and every declaration the export
    /// filter leaves out must project to nothing at all, which RuntimeViewer's
    /// Find takes as the declaration not being there.
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
            for options in optionCombinations {
                let projected = separated.regions.projection(of: separated.text, where: options.isVisibilityOptionEnabled).text
                guard let rendered = plain(name, options)?.frozen() else {
                    mismatches.append("\(name): no plain rendering")
                    break
                }
                if projected != rendered {
                    mismatches.append("\(name) under \(VisibilityOption.allCases.filter(options.isEnabled).map(\.rawValue)):\n\(projected.string)\n--- expected ---\n\(rendered.string)")
                    break
                }
                if rendered.string.isEmpty, !projected.string.isEmpty {
                    mismatches.append("\(name) projects to \(projected.string.debugDescription) where it renders empty")
                    break
                }
            }
        }
        return mismatches
    }

    private static func expectMarkedRenderingsProject<MachO: ObjCMetadataSource>(in machO: MachO) async throws {
        let (builder, indexer) = try await preparedBuilder(of: machO)
        let classMismatches = mismatches(of: indexer.classNames) {
            builder.markedClassInterface(named: $0)
        } plain: {
            builder.classInterface(named: $0, options: $1)
        }
        let categoryMismatches = mismatches(of: indexer.categoryNames) {
            builder.markedCategoryInterface(uniqueName: $0)
        } plain: {
            builder.categoryInterface(uniqueName: $0, options: $1)
        }
        #expect(classMismatches.isEmpty, "\(classMismatches.joined(separator: "\n\n"))")
        #expect(categoryMismatches.isEmpty, "\(categoryMismatches.joined(separator: "\n\n"))")
    }

    @Test("The Swift image's marked renderings project to its plain ones, read from the file")
    func swiftImageMarkedInFile() async throws {
        try await Self.expectMarkedRenderingsProject(in: try ExportedDeclarationsFixture.swiftLibraryFile())
    }

    @Test("The Swift image's marked renderings project to its plain ones, loaded")
    func swiftImageMarkedLoaded() async throws {
        try await Self.expectMarkedRenderingsProject(in: try ExportedDeclarationsFixture.swiftLibraryImage())
    }

    @Test("The Objective-C image's marked renderings project to its plain ones, read from the file")
    func objectiveCImageMarkedInFile() async throws {
        try await Self.expectMarkedRenderingsProject(in: try ExportedDeclarationsFixture.objectiveCLibraryFile())
    }

    @Test("The Objective-C image's marked renderings project to its plain ones, loaded")
    func objectiveCImageMarkedLoaded() async throws {
        try await Self.expectMarkedRenderingsProject(in: try ExportedDeclarationsFixture.objectiveCLibraryImage())
    }

    // MARK: - Settings

    /// Settings saved before the switch existed read with it off; saved with
    /// it, they keep it.
    @Test("Saved settings without the switch decode with it off")
    func savedSettingsDecode() throws {
        let saved = Data(#"{"stripOverrides":true}"#.utf8)
        let decoded = try JSONDecoder().decode(ObjCGenerationOptions.self, from: saved)
        #expect(decoded.stripOverrides)
        #expect(!decoded.printExportedDeclarationsOnly)

        let roundTripped = try JSONDecoder().decode(ObjCGenerationOptions.self, from: try JSONEncoder().encode(Self.exportedOnly))
        #expect(roundTripped == Self.exportedOnly)
    }
}
