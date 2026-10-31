import Testing
import MachOKit
import ObjCDump
import Semantic
@testable import ObjCDeclarationRendering

/// The comments a declaration rendering adds, atom by atom. A host colors and
/// lays out a rendering by its atoms, so each comment stays the atoms it has
/// always been: one `.comment` atom, or, for an IMP that resolves to nothing,
/// a `.comment` atom followed by the raw value as an `.error` atom.
@Suite("Comment atoms")
struct CommentAtomTests {
    private static func foundationImage() throws -> MachOImage {
        try CommentFixtures.foundationImage()
    }

    private static let everyComment = CommentFixtures.everyComment

    private static func resolvableIMP(in machO: MachOImage) -> UInt64 {
        CommentFixtures.resolvableIMP(in: machO)
    }

    /// The atoms of `rendering` a host draws as comments, errors included.
    private static func commentAtoms(of rendering: SemanticString) -> [AtomicComponent] {
        rendering.components.filter { $0.type == .comment || $0.type == .error }
    }

    private static func comment(_ string: String) -> AtomicComponent {
        AtomicComponent(string: string, type: .comment)
    }

    private static func error(_ string: String) -> AtomicComponent {
        AtomicComponent(string: string, type: .error)
    }

    enum IvarOffsetWording: CaseIterable, Sendable {
        case recorded
        case unknown
        case wordedByHost
    }

    @Test("An ivar offset comment is one comment atom", arguments: IvarOffsetWording.allCases)
    func ivarOffsetComment(wording: IvarOffsetWording) throws {
        let context = ObjCRenderingContext(machO: try Self.foundationImage(), options: Self.everyComment)
        let expectedComment: String
        switch wording {
        case .recorded:
            expectedComment = "// offset: 8"
        case .unknown:
            context.ivarNamesWithUnknownOffset = ["_width"]
            expectedComment = "// offset: unknown"
        case .wordedByHost:
            context.ivarOffsetCommentBuilder = { "ivar offset: 0x\(String($0, radix: 16, uppercase: true))" }
            expectedComment = "// ivar offset: 0x8"
        }

        let rendering = ObjCIvarInfo(name: "_width", typeEncoding: "d", offset: 8).semanticString(using: context)

        #expect(rendering.string == "double _width; \(expectedComment)")
        #expect(Self.commentAtoms(of: rendering) == [Self.comment(expectedComment)])
    }

    @Test("A property's synthesis and accessor address comments are one atom each, on one line")
    func propertySynthesisAndAccessorComments() throws {
        let machO = try Self.foundationImage()
        let context = ObjCRenderingContext(machO: machO, options: Self.everyComment)
        let getterIMP = Self.resolvableIMP(in: machO)
        context.methodIMPs = ["width": getterIMP, "setWidth:": 1]
        let getterAddress = try #require(machO.formattedAddress(forRawValue: getterIMP))

        let rendering = ObjCPropertyInfo(name: "width", attributesString: "Td,N,V_width", isClassProperty: false)
            .semanticString(using: context)

        #expect(rendering.string == "@property (nonatomic) double width; // @synthesize width = _width // getter IMP: \(getterAddress) // setter IMP: <invalid 0x1>")
        #expect(Self.commentAtoms(of: rendering) == [
            Self.comment("// @synthesize width = _width"),
            Self.comment("// getter IMP: \(getterAddress)"),
            Self.comment("// setter IMP: "),
            Self.error("<invalid 0x1>"),
        ])
    }

    struct PropertyAttributeCase: Sendable, CustomTestStringConvertible {
        let name: String
        let attributesString: String
        let expectedLine: String
        let expectedComment: String

        var testDescription: String { expectedComment }
    }

    @Test("A property's other attribute comments are one atom each", arguments: [
        PropertyAttributeCase(
            name: "height",
            attributesString: "Td,N,Vheight",
            expectedLine: "@property (nonatomic) double height; // @synthesize height",
            expectedComment: "// @synthesize height"
        ),
        PropertyAttributeCase(
            name: "title",
            attributesString: #"T@"NSString",C,D,N"#,
            expectedLine: "@property (nonatomic, copy) NSString *title; // @dynamic title",
            expectedComment: "// @dynamic title"
        ),
    ])
    func propertyAttributeComment(propertyCase: PropertyAttributeCase) throws {
        let context = ObjCRenderingContext(machO: try Self.foundationImage(), options: Self.everyComment)

        let rendering = ObjCPropertyInfo(name: propertyCase.name, attributesString: propertyCase.attributesString, isClassProperty: false)
            .semanticString(using: context)

        #expect(rendering.string == propertyCase.expectedLine)
        #expect(Self.commentAtoms(of: rendering) == [Self.comment(propertyCase.expectedComment)])
    }

    @Test("A method's IMP comment is one comment atom")
    func methodIMPComment() throws {
        let machO = try Self.foundationImage()
        let context = ObjCRenderingContext(machO: machO, options: Self.everyComment)
        let imp = Self.resolvableIMP(in: machO)
        let address = try #require(machO.formattedAddress(forRawValue: imp))

        let rendering = ObjCMethodInfo(name: "width", typeEncoding: "d16@0:8", isClassMethod: false, imp: imp)
            .semanticString(using: context)

        #expect(rendering.string == "- (double)width; // IMP: \(address)")
        #expect(Self.commentAtoms(of: rendering) == [Self.comment("// IMP: \(address)")])
    }

    @Test("An IMP that resolves to nothing is a comment atom and an error atom")
    func unresolvableMethodIMPComment() throws {
        let context = ObjCRenderingContext(machO: try Self.foundationImage(), options: Self.everyComment)

        let rendering = ObjCMethodInfo(name: "reset", typeEncoding: "v16@0:8", isClassMethod: false, imp: 0)
            .semanticString(using: context)

        #expect(rendering.string == "- (void)reset; // IMP: <invalid 0x0>")
        #expect(Self.commentAtoms(of: rendering) == [Self.comment("// IMP: "), Self.error("<invalid 0x0>")])
    }

    @Test("A note on a type with no signature is one inline comment atom", arguments: [
        ("@?", "id /* block */ _value;", "/* block */"),
        ("^?", "void * /* function pointer */ _value;", "/* function pointer */"),
    ])
    func typeNote(typeEncoding: String, expectedLine: String, expectedComment: String) throws {
        let context = ObjCRenderingContext(machO: try Self.foundationImage())

        let rendering = ObjCIvarInfo(name: "_value", typeEncoding: typeEncoding, offset: 8).semanticString(using: context)

        #expect(rendering.string == expectedLine)
        #expect(Self.commentAtoms(of: rendering) == [Self.comment(expectedComment)])
    }
}
