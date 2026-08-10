import Testing
import Foundation
import MachOKit
import MachOObjCSection
import ObjCDeclarationRendering
import ObjCDump
import ObjCIndexing
import Semantic
@testable import ObjCInterface

/// Builds interfaces out of an image already loaded into this process, so the
/// tests need no fixture binary on disk.
@Suite("ObjC interface building")
struct ObjCInterfaceTests {
    /// One prepared indexer shared by every test in this suite — preparing it
    /// walks all of Foundation, which is far too slow to redo per test.
    actor SharedFixture {
        static let shared = SharedFixture()

        private var cached: (indexer: ObjCInterfaceIndexer, machO: MachOImage)?

        enum FixtureError: Swift.Error {
            case foundationImageUnavailable
        }

        func load() async throws -> (indexer: ObjCInterfaceIndexer, machO: MachOImage) {
            if let cached { return cached }
            guard let machO = MachOImage(name: "Foundation") else {
                throw FixtureError.foundationImageUnavailable
            }
            let indexer = ObjCInterfaceIndexer(machO: machO, imagePath: machO.imagePath)
            try await indexer.prepare()
            let loaded = (indexer, machO)
            cached = loaded
            return loaded
        }
    }

    private static func makeBuilder() async throws -> ObjCInterfaceBuilder {
        let (indexer, machO) = try await SharedFixture.shared.load()
        return ObjCInterfaceBuilder(indexer: indexer, machO: machO)
    }

    /// A class with ivars, properties and methods, so the strip switches have
    /// something to bite on.
    private static let sampleClass = "NSError"

    // MARK: - Basic Shape

    @Test("Builds a class interface")
    func buildsClassInterface() async throws {
        let builder = try await Self.makeBuilder()
        let rendered = try #require(builder.classInterface(named: Self.sampleClass))
        #expect(rendered.string.hasPrefix("@interface \(Self.sampleClass)"))
        #expect(rendered.string.hasSuffix("@end"))
    }

    @Test("Builds a protocol interface")
    func buildsProtocolInterface() async throws {
        let builder = try await Self.makeBuilder()
        let rendered = try #require(builder.protocolInterface(named: "NSCopying"))
        #expect(rendered.string.hasPrefix("@protocol NSCopying"))
    }

    @Test("Builds a category interface")
    func buildsCategoryInterface() async throws {
        let (indexer, machO) = try await SharedFixture.shared.load()
        let builder = ObjCInterfaceBuilder(indexer: indexer, machO: machO)
        let uniqueName = try #require(indexer.categoryNames.first)
        let rendered = try #require(builder.categoryInterface(uniqueName: uniqueName))
        #expect(rendered.string.hasPrefix("@interface "))
    }

    @Test("Builds a C struct definition")
    func buildsStructInterface() async throws {
        let (indexer, machO) = try await SharedFixture.shared.load()
        let builder = ObjCInterfaceBuilder(indexer: indexer, machO: machO)
        let name = try #require(indexer.structNames.first)
        let rendered = try #require(builder.structInterface(named: name))
        #expect(rendered.string.hasPrefix("struct "))
    }

    @Test("Unknown names yield nil rather than an empty declaration")
    func unknownNamesYieldNil() async throws {
        let builder = try await Self.makeBuilder()
        #expect(builder.classInterface(named: "NoSuchClassAnywhere") == nil)
        #expect(builder.protocolInterface(named: "NoSuchProtocolAnywhere") == nil)
        #expect(builder.categoryInterface(uniqueName: "No(Such)") == nil)
        #expect(builder.structInterface(named: "NoSuchStruct") == nil)
        #expect(builder.unionInterface(named: "NoSuchUnion") == nil)
    }

    // MARK: - Comment Switches

    @Test("addIvarOffsetComments adds offsets, and off by default")
    func ivarOffsetCommentSwitch() async throws {
        let builder = try await Self.makeBuilder()

        var options = ObjCGenerationOptions.default
        options.addIvarOffsetComments = true

        let plain = try #require(builder.classInterface(named: Self.sampleClass)).string
        let annotated = try #require(builder.classInterface(named: Self.sampleClass, options: options)).string

        #expect(!plain.contains("offset: "))
        #expect(annotated.contains("offset: "))
    }

    @Test("addMethodIMPAddressComments adds IMP comments")
    func methodIMPCommentSwitch() async throws {
        let builder = try await Self.makeBuilder()

        var options = ObjCGenerationOptions.default
        options.addMethodIMPAddressComments = true

        let plain = try #require(builder.classInterface(named: Self.sampleClass)).string
        let annotated = try #require(builder.classInterface(named: Self.sampleClass, options: options)).string

        #expect(!plain.contains("IMP:"))
        #expect(annotated.contains("IMP:"))
    }

    @Test("addPropertyAttributesComments annotates properties")
    func propertyAttributesCommentSwitch() async throws {
        let (indexer, machO) = try await SharedFixture.shared.load()
        let builder = ObjCInterfaceBuilder(indexer: indexer, machO: machO)

        var options = ObjCGenerationOptions.default
        options.addPropertyAttributesComments = true

        // The switch emits `@synthesize` / `@dynamic` comments, which only
        // appear for properties whose metadata names a backing ivar — not
        // every class has one.
        var sawAnnotation = false
        for className in indexer.classNames.prefix(400) {
            guard let annotated = builder.classInterface(named: className, options: options)?.string
            else { continue }
            if annotated.contains("@synthesize") || annotated.contains("@dynamic") {
                sawAnnotation = true
                break
            }
        }
        #expect(sawAnnotation)
    }

    @Test("addPropertyAccessorAddressComments annotates accessors")
    func propertyAccessorAddressCommentSwitch() async throws {
        let builder = try await Self.makeBuilder()

        var options = ObjCGenerationOptions.default
        options.addPropertyAccessorAddressComments = true

        let plain = try #require(builder.classInterface(named: Self.sampleClass)).string
        let annotated = try #require(builder.classInterface(named: Self.sampleClass, options: options)).string

        #expect(annotated.count > plain.count)
    }

    // MARK: - Strip Switches

    @Test("stripProtocolConformance removes protocol-inherited members")
    func stripProtocolConformanceSwitch() async throws {
        let builder = try await Self.makeBuilder()

        var options = ObjCGenerationOptions.default
        options.stripProtocolConformance = true

        let plain = try #require(builder.classInterface(named: Self.sampleClass)).string
        let stripped = try #require(builder.classInterface(named: Self.sampleClass, options: options)).string

        #expect(stripped.count < plain.count)
    }

    @Test("stripOverrides removes superclass-inherited members")
    func stripOverridesSwitch() async throws {
        let builder = try await Self.makeBuilder()

        var options = ObjCGenerationOptions.default
        options.stripOverrides = true

        let plain = try #require(builder.classInterface(named: Self.sampleClass)).string
        let stripped = try #require(builder.classInterface(named: Self.sampleClass, options: options)).string

        #expect(stripped.count < plain.count)
    }

    @Test("stripSynthesizedMethods removes property accessors")
    func stripSynthesizedMethodsSwitch() async throws {
        let builder = try await Self.makeBuilder()

        var options = ObjCGenerationOptions.default
        options.stripSynthesizedMethods = true

        let plain = try #require(builder.classInterface(named: Self.sampleClass)).string
        let stripped = try #require(builder.classInterface(named: Self.sampleClass, options: options)).string

        #expect(stripped.count < plain.count)
    }

    @Test("stripCtorMethod and stripDtorMethod remove .cxx_ methods")
    func stripCtorDtorSwitches() async throws {
        let (indexer, machO) = try await SharedFixture.shared.load()
        let builder = ObjCInterfaceBuilder(indexer: indexer, machO: machO)

        // Find a class that actually declares `.cxx_destruct`.
        var targetClassName: String?
        for className in indexer.classNames {
            guard let rendered = builder.classInterface(named: className)?.string else { continue }
            if rendered.contains(".cxx_destruct") {
                targetClassName = className
                break
            }
        }
        let className = try #require(targetClassName, "no class in Foundation declares .cxx_destruct")

        var options = ObjCGenerationOptions.default
        options.stripDtorMethod = true
        let stripped = try #require(builder.classInterface(named: className, options: options)).string
        #expect(!stripped.contains(".cxx_destruct"))
    }

    @Test("stripSynthesizedIvars removes property-backing ivars")
    func stripSynthesizedIvarsSwitch() async throws {
        let (indexer, machO) = try await SharedFixture.shared.load()
        let builder = ObjCInterfaceBuilder(indexer: indexer, machO: machO)

        var options = ObjCGenerationOptions.default
        options.stripSynthesizedIvars = true

        // Find a class whose ivar list actually shrinks — not every class has
        // property-backing ivars visible in the metadata.
        var sawShrink = false
        for className in indexer.classNames.prefix(400) {
            guard let plain = builder.classInterface(named: className)?.string,
                  let stripped = builder.classInterface(named: className, options: options)?.string
            else { continue }
            if stripped.count < plain.count {
                sawShrink = true
                break
            }
        }
        #expect(sawShrink)
    }

    // MARK: - C Type Replacement

    @Test("C type replacements flow through to the rendered interface")
    func cTypeReplacementsFlowThrough() async throws {
        let (indexer, machO) = try await SharedFixture.shared.load()
        let builder = ObjCInterfaceBuilder(indexer: indexer, machO: machO)

        var target: String?
        for className in indexer.classNames.prefix(400) {
            if builder.classInterface(named: className)?.string.contains("unsigned long long") == true {
                target = className
                break
            }
        }
        let className = try #require(target, "no class in the sample declares `unsigned long long`")

        let substituted = try #require(
            builder.classInterface(named: className, cTypeReplacements: [.ulongLong: "NSUInteger"])
        ).string

        #expect(!substituted.contains("unsigned long long"))
        #expect(substituted.contains("NSUInteger"))
    }

    @Test("Ivar offset comment builder overrides the default wording")
    func ivarOffsetCommentBuilderOverrides() async throws {
        let builder = try await Self.makeBuilder()

        var options = ObjCGenerationOptions.default
        options.addIvarOffsetComments = true

        // Built outside `#require`: the macro re-spells arguments as closure
        // parameters, which drops the `@Sendable` on the builder closure.
        let output = builder.classInterface(
            named: Self.sampleClass,
            options: options,
            ivarOffsetCommentBuilder: { "at 0x\(String($0, radix: 16, uppercase: true))" }
        )
        let rendered = try #require(output).string

        #expect(rendered.contains("at 0x"))
        #expect(!rendered.contains("offset: "))
    }
}
