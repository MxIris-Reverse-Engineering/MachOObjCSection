import Testing
import Foundation
import MachOKit
import ObjCDeclarationRendering
import ObjCDump
import ObjCIndexing
import Semantic
@testable import ObjCInterface

/// The Swift import notes a host supplies (`ObjCSwiftImportNotes`) print as
/// the header's macros: `NS_REFINED_FOR_SWIFT` ahead of the `;` of exactly
/// the members noted, and nowhere else. Over Foundation's `NSError`, with the
/// members picked from its metadata rather than spelled out, so the suite
/// does not depend on what one release of Foundation declares.
@Suite("Swift import notes")
struct SwiftImportNotesRenderingTests {
    private static let sampleClass = "NSError"

    private static let refinedSuffix = " NS_REFINED_FOR_SWIFT;"

    private struct Sample {
        let builder: ObjCInterfaceBuilder<MachOImage>
        let property: ObjCPropertyInfo
        let instanceMethod: ObjCMethodInfo
        let classMethod: ObjCMethodInfo

        /// A note on each of the three sample members.
        var notes: ObjCSwiftImportNotes {
            var notes = ObjCSwiftImportNotes()
            notes[.property(name: property.name, isClassProperty: property.isClassProperty)] = .init(isRefinedForSwift: true)
            notes[.method(selector: instanceMethod.name)] = .init(isRefinedForSwift: true)
            notes[.method(selector: classMethod.name, isClassMethod: true)] = .init(isRefinedForSwift: true)
            return notes
        }
    }

    private static func sample() async throws -> Sample {
        let (indexer, machO) = try await ObjCInterfaceTests.SharedFixture.shared.load()
        let classInfo = try #require(indexer.classGroup(forName: sampleClass)?.info.first)
        let property = try #require(classInfo.properties.first)
        // A method with arguments, so the macro has to follow the last one.
        let instanceMethod = try #require(classInfo.methods.first { $0.name.hasSuffix(":") })
        let classMethod = try #require(classInfo.classMethods.first)
        return Sample(builder: ObjCInterfaceBuilder(indexer: indexer, machO: machO), property: property, instanceMethod: instanceMethod, classMethod: classMethod)
    }

    private static func options(enabling enabled: Set<ObjCGenerationOptions.VisibilityOption>) -> ObjCGenerationOptions {
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
            addPropertyAccessorAddressComments: enabled.contains(.addPropertyAccessorAddressComments),
            printExportedDeclarationsOnly: enabled.contains(.printExportedDeclarationsOnly)
        )
    }

    private static func lines(of rendering: SemanticString?) throws -> [String] {
        try #require(rendering).string.components(separatedBy: "\n")
    }

    @Test("a noted property, instance method and class method end their declarations with NS_REFINED_FOR_SWIFT, and nothing else changes")
    func notedMembersCarryTheMacro() async throws {
        let sample = try await Self.sample()
        let plainLines = try Self.lines(of: sample.builder.classInterface(named: Self.sampleClass))
        let notedLines = try Self.lines(of: sample.builder.classInterface(named: Self.sampleClass, swiftImportNotes: sample.notes))

        #expect(plainLines.count == notedLines.count)
        let changedLines = zip(plainLines, notedLines).filter { $0.0 != $0.1 }
        for (plainLine, notedLine) in changedLines {
            #expect(notedLine == String(plainLine.dropLast()) + Self.refinedSuffix, "\(plainLine) → \(notedLine)")
        }
        let changedNotedLines = changedLines.map { $0.1 }
        #expect(changedNotedLines.contains { $0.hasPrefix("@property") && $0.hasSuffix(sample.property.name + Self.refinedSuffix) }, "\(changedNotedLines)")
        #expect(changedNotedLines.contains { $0.hasPrefix("- (") && $0.contains(sample.instanceMethod.name.components(separatedBy: ":")[0] + ":") }, "\(changedNotedLines)")
        #expect(changedNotedLines.contains { $0.hasPrefix("+ (") }, "\(changedNotedLines)")
    }

    @Test("the macro sits ahead of the semicolon and the comments follow it")
    func macroPrecedesTheComments() async throws {
        let sample = try await Self.sample()
        var options = ObjCGenerationOptions.default
        options.addMethodIMPAddressComments = true
        options.addPropertyAccessorAddressComments = true
        let rendered = try #require(sample.builder.classInterface(named: Self.sampleClass, options: options, swiftImportNotes: sample.notes)).string
        #expect(rendered.contains("NS_REFINED_FOR_SWIFT; // IMP:"), "\(rendered)")
    }

    @Test("a note about another kind of member, or a member the class lacks, prints nothing")
    func unmatchedNotesPrintNothing() async throws {
        let sample = try await Self.sample()
        let plain = try #require(sample.builder.classInterface(named: Self.sampleClass)).string
        var notes = ObjCSwiftImportNotes()
        // The class method's selector as an instance method — unless the
        // class has an instance method of that selector too.
        let classMethodIsAlsoAnInstanceMethod = plain.components(separatedBy: "\n").contains { $0.hasPrefix("- (") && $0.contains(")" + sample.classMethod.name.components(separatedBy: ":")[0]) }
        if !classMethodIsAlsoAnInstanceMethod {
            notes[.method(selector: sample.classMethod.name)] = .init(isRefinedForSwift: true)
        }
        notes[.property(name: sample.property.name, isClassProperty: !sample.property.isClassProperty)] = .init(isRefinedForSwift: true)
        notes[.property(name: "propertyNoClassDeclares")] = .init(isRefinedForSwift: true)
        notes[.method(selector: "selectorNoClassDeclares:", isClassMethod: true)] = .init(isRefinedForSwift: true)
        notes[.method(selector: sample.instanceMethod.name)] = .init(isRefinedForSwift: false)

        let noted = try #require(sample.builder.classInterface(named: Self.sampleClass, swiftImportNotes: notes)).string
        #expect(noted == plain)
    }

    @Test("a marked rendering carries the macro and still projects to the plain rendering under every switch")
    func markedRenderingProjectsWithTheMacro() async throws {
        let sample = try await Self.sample()
        let notes = sample.notes
        let marked = try #require(sample.builder.markedClassInterface(named: Self.sampleClass, swiftImportNotes: notes))
        let separated = marked.frozen().separatingVisibilityRegions()
        #expect(separated.text.string.contains(Self.refinedSuffix))

        let combinations = [Self.options(enabling: [])] + ObjCGenerationOptions.VisibilityOption.allCases.map { Self.options(enabling: [$0]) }
        for options in combinations {
            let projected = separated.regions.projection(of: separated.text, where: options.isVisibilityOptionEnabled).text
            let plain = try #require(sample.builder.classInterface(named: Self.sampleClass, options: options, swiftImportNotes: notes)).frozen()
            #expect(projected == plain, "\(ObjCGenerationOptions.VisibilityOption.allCases.filter(options.isEnabled).map(\.rawValue))")
        }
    }

    // MARK: - Swift names and the declaration itself

    @Test("a member's Swift name prints as NS_SWIFT_NAME, ahead of NS_REFINED_FOR_SWIFT")
    func memberSwiftNamePrintsBeforeRefinedForSwift() async throws {
        let sample = try await Self.sample()
        var notes = ObjCSwiftImportNotes()
        notes[.method(selector: sample.instanceMethod.name)] = .init(isRefinedForSwift: true, swiftName: "renamedMethod(_:)")
        notes[.property(name: sample.property.name, isClassProperty: sample.property.isClassProperty)] = .init(swiftName: "renamedProperty")
        let plainLines = try Self.lines(of: sample.builder.classInterface(named: Self.sampleClass))
        let notedLines = try Self.lines(of: sample.builder.classInterface(named: Self.sampleClass, swiftImportNotes: notes))

        let changedNotedLines = zip(plainLines, notedLines).filter { $0.0 != $0.1 }.map { $0.1 }
        #expect(changedNotedLines.count == 2, "\(changedNotedLines)")
        #expect(changedNotedLines.contains { $0.hasPrefix("- (") && $0.hasSuffix(" NS_SWIFT_NAME(renamedMethod(_:)) NS_REFINED_FOR_SWIFT;") }, "\(changedNotedLines)")
        #expect(changedNotedLines.contains { $0.hasPrefix("@property") && $0.hasSuffix(" NS_SWIFT_NAME(renamedProperty);") }, "\(changedNotedLines)")
    }

    @Test("a note about the class prints on its own line above @interface, and nothing else changes")
    func classDeclarationNotePrintsOnItsOwnLineAboveInterface() async throws {
        let sample = try await Self.sample()
        var notes = ObjCSwiftImportNotes()
        notes.declarationNote = .init(isRefinedForSwift: true, swiftName: "SwiftError")
        let plainLines = try Self.lines(of: sample.builder.classInterface(named: Self.sampleClass))
        let notedLines = try Self.lines(of: sample.builder.classInterface(named: Self.sampleClass, swiftImportNotes: notes))

        #expect(notedLines.first == "NS_SWIFT_NAME(SwiftError) NS_REFINED_FOR_SWIFT")
        #expect(Array(notedLines.dropFirst()) == plainLines)

        var refinedOnly = ObjCSwiftImportNotes()
        refinedOnly.declarationNote = .init(isRefinedForSwift: true)
        let refinedLines = try Self.lines(of: sample.builder.classInterface(named: Self.sampleClass, swiftImportNotes: refinedOnly))
        #expect(refinedLines.first == "NS_REFINED_FOR_SWIFT")
        #expect(refinedLines.dropFirst().first?.hasPrefix("@interface \(Self.sampleClass)") == true)
    }

    @Test("a protocol prints its own note and its members' notes")
    func protocolInterfaceTakesNotes() async throws {
        let (indexer, machO) = try await ObjCInterfaceTests.SharedFixture.shared.load()
        let builder = ObjCInterfaceBuilder(indexer: indexer, machO: machO)
        var protocolSample: (name: String, method: ObjCMethodInfo)?
        for protocolName in indexer.protocolNames.sorted() {
            if let method = indexer.protocolGroup(forName: protocolName)?.info.methods.first {
                protocolSample = (protocolName, method)
                break
            }
        }
        let (protocolName, method) = try #require(protocolSample)
        var notes = ObjCSwiftImportNotes()
        notes.declarationNote = .init(swiftName: "RenamedProtocol")
        notes[.method(selector: method.name)] = .init(isRefinedForSwift: true)

        let plainLines = try Self.lines(of: builder.protocolInterface(named: protocolName))
        let notedLines = try Self.lines(of: builder.protocolInterface(named: protocolName, swiftImportNotes: notes))
        #expect(notedLines.first == "NS_SWIFT_NAME(RenamedProtocol)")
        #expect(notedLines.dropFirst().first?.hasPrefix("@protocol \(protocolName)") == true)
        let changedNotedLines = zip(plainLines, notedLines.dropFirst()).filter { $0.0 != $0.1 }.map { $0.1 }
        #expect(changedNotedLines.count == 1, "\(changedNotedLines)")
        #expect(changedNotedLines.first?.hasSuffix(Self.refinedSuffix) == true, "\(changedNotedLines)")
    }

    @Test("a category prints its members' notes, but not a note about the class it extends")
    func categoryMembersTakeNotes() async throws {
        let (indexer, machO) = try await ObjCInterfaceTests.SharedFixture.shared.load()
        let builder = ObjCInterfaceBuilder(indexer: indexer, machO: machO)
        var categorySample: (name: String, method: ObjCMethodInfo)?
        for categoryName in indexer.categoryNames.sorted() {
            if let method = indexer.categoryGroup(forName: categoryName)?.info.methods.first {
                categorySample = (categoryName, method)
                break
            }
        }
        let (categoryName, method) = try #require(categorySample)
        var notes = ObjCSwiftImportNotes()
        notes.declarationNote = .init(isRefinedForSwift: true)
        notes[.method(selector: method.name)] = .init(isRefinedForSwift: true)

        let plainLines = try Self.lines(of: builder.categoryInterface(uniqueName: categoryName))
        let notedLines = try Self.lines(of: builder.categoryInterface(uniqueName: categoryName, swiftImportNotes: notes))
        #expect(notedLines.count == plainLines.count)
        #expect(notedLines.first?.hasPrefix("@interface") == true)
        let changedNotedLines = zip(plainLines, notedLines).filter { $0.0 != $0.1 }.map { $0.1 }
        #expect(changedNotedLines.count == 1, "\(changedNotedLines)")
        #expect(changedNotedLines.first?.hasSuffix(Self.refinedSuffix) == true, "\(changedNotedLines)")
    }

    @Test("a marked rendering with a note about the class still projects to the plain rendering")
    func markedRenderingWithDeclarationNoteProjects() async throws {
        let sample = try await Self.sample()
        var notes = sample.notes
        notes.declarationNote = .init(isRefinedForSwift: true, swiftName: "SwiftError")
        let marked = try #require(sample.builder.markedClassInterface(named: Self.sampleClass, swiftImportNotes: notes))
        let separated = marked.frozen().separatingVisibilityRegions()

        let combinations = [Self.options(enabling: [])] + ObjCGenerationOptions.VisibilityOption.allCases.map { Self.options(enabling: [$0]) }
        for options in combinations {
            let projected = separated.regions.projection(of: separated.text, where: options.isVisibilityOptionEnabled).text
            let plain = try #require(sample.builder.classInterface(named: Self.sampleClass, options: options, swiftImportNotes: notes)).frozen()
            #expect(projected == plain, "\(ObjCGenerationOptions.VisibilityOption.allCases.filter(options.isEnabled).map(\.rawValue))")
        }
    }
}
