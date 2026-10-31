import Testing
import MachOKit
import ObjCDump
import Semantic
@testable import ObjCDeclarationRendering

/// With `marksCommentStructure`, every comment a rendering adds is marked
/// with its kind and the role of each of its segments, and separating the
/// marks gives the rendering without them back. RuntimeViewer draws each
/// comment as a tag from these marks instead of parsing the text.
@Suite("Comment structure marking")
struct CommentStructureMarkingTests {
    /// One comment as the annotation table of a marked rendering describes
    /// it: its kind, the text its region covers, and its segments.
    struct MarkedComment: Equatable, CustomStringConvertible {
        let kind: AnnotationRegion.Kind
        let text: String
        let segments: [MarkedSegment]

        init(_ kind: AnnotationRegion.Kind, _ text: String, _ segments: [MarkedSegment]) {
            self.kind = kind
            self.text = text
            self.segments = segments
        }

        var description: String {
            "\(kind.rawValue) \"\(text)\" \(segments)"
        }
    }

    struct MarkedSegment: Equatable, CustomStringConvertible {
        let role: AnnotationSegment.Role
        let text: String

        init(_ role: AnnotationSegment.Role, _ text: String) {
            self.role = role
            self.text = text
        }

        var description: String {
            "\(role.rawValue) \"\(text)\""
        }
    }

    /// The comments of `rendering`, read back from its annotation table.
    private static func markedComments(of rendering: SemanticString) -> [MarkedComment] {
        let (text, annotations) = rendering.frozen().separatingAnnotationRegions()
        let bytes = Array(text.string.utf8)
        func string(at offset: UInt32, length: UInt32) -> String {
            String(decoding: bytes[Int(offset) ..< Int(offset) + Int(length)], as: UTF8.self)
        }
        return annotations.regions.indices.map { regionIndex in
            let region = annotations.regions[regionIndex]
            return MarkedComment(
                region.kind,
                string(at: region.utf8Offset, length: region.utf8Length),
                annotations.segments(inRegionAt: regionIndex).map { MarkedSegment($0.role, string(at: $0.utf8Offset, length: $0.utf8Length)) }
            )
        }
    }

    private static func markingContext(machO: MachOImage) -> ObjCRenderingContext<MachOImage> {
        ObjCRenderingContext(machO: machO, options: CommentFixtures.everyComment, marksCommentStructure: true)
    }

    // MARK: - Kinds and Segments

    enum IvarOffsetSource: CaseIterable, Sendable {
        case recorded
        case unknown
    }

    @Test("An ivar offset comment is marked as an offset, or as one the image does not record", arguments: IvarOffsetSource.allCases)
    func ivarOffset(source: IvarOffsetSource) throws {
        let context = Self.markingContext(machO: try CommentFixtures.foundationImage())
        let expected: MarkedComment
        switch source {
        case .recorded:
            expected = MarkedComment(.ivarOffset, "// offset: 8", [
                MarkedSegment(.marker, "// "), MarkedSegment(.label, "offset"), MarkedSegment(.separator, ": "), MarkedSegment(.value, "8"),
            ])
        case .unknown:
            context.ivarNamesWithUnknownOffset = ["_width"]
            expected = MarkedComment(.ivarOffsetUnknown, "// offset: unknown", [
                MarkedSegment(.marker, "// "), MarkedSegment(.label, "offset"), MarkedSegment(.separator, ": "), MarkedSegment(.value, "unknown"),
            ])
        }

        let rendering = ObjCIvarInfo(name: "_width", typeEncoding: "d", offset: 8).semanticString(using: context)

        #expect(Self.markedComments(of: rendering) == [expected])
    }

    @Test("An ivar offset comment the host worded splits at its first colon", arguments: [
        ("offset: 0x8", [MarkedSegment(.label, "offset"), MarkedSegment(.separator, ": "), MarkedSegment(.value, "0x8")]),
        ("ivar offset: 0x8", [MarkedSegment(.label, "ivar offset"), MarkedSegment(.separator, ": "), MarkedSegment(.value, "0x8")]),
        ("0x8", [MarkedSegment(.value, "0x8")]),
        ("8 bytes in", [MarkedSegment(.value, "8 bytes in")]),
    ])
    func ivarOffsetWordedByHost(wording: String, expectedSegments: [MarkedSegment]) throws {
        let context = Self.markingContext(machO: try CommentFixtures.foundationImage())
        context.ivarOffsetCommentBuilder = { _ in wording }

        let rendering = ObjCIvarInfo(name: "_width", typeEncoding: "d", offset: 8).semanticString(using: context)

        #expect(Self.markedComments(of: rendering) == [
            MarkedComment(.ivarOffset, "// \(wording)", [MarkedSegment(.marker, "// ")] + expectedSegments),
        ])
    }

    @Test("A property's synthesis and accessor addresses are one region each, the unresolvable address an error value")
    func propertySynthesisAndAccessors() throws {
        let machO = try CommentFixtures.foundationImage()
        let context = Self.markingContext(machO: machO)
        let getterIMP = CommentFixtures.resolvableIMP(in: machO)
        context.methodIMPs = ["width": getterIMP, "setWidth:": 1]
        let getterAddress = try #require(machO.formattedAddress(forRawValue: getterIMP))

        let rendering = ObjCPropertyInfo(name: "width", attributesString: "Td,N,V_width", isClassProperty: false)
            .semanticString(using: context)

        #expect(Self.markedComments(of: rendering) == [
            MarkedComment(.propertySynthesis, "// @synthesize width = _width", [
                MarkedSegment(.marker, "// "), MarkedSegment(.label, "@synthesize"), MarkedSegment(.separator, " "),
                MarkedSegment(.name, "width"), MarkedSegment(.separator, " = "), MarkedSegment(.value, "_width"),
            ]),
            MarkedComment(.impAddress, "// getter IMP: \(getterAddress)", [
                MarkedSegment(.marker, "// "), MarkedSegment(.label, "getter IMP"), MarkedSegment(.separator, ": "), MarkedSegment(.value, getterAddress),
            ]),
            MarkedComment(.impAddress, "// setter IMP: <invalid 0x1>", [
                MarkedSegment(.marker, "// "), MarkedSegment(.label, "setter IMP"), MarkedSegment(.separator, ": "), MarkedSegment(.value, "<invalid 0x1>"),
            ]),
        ])
    }

    @Test("A property synthesized into its own name, and a dynamic one, name the property", arguments: [
        ("height", "Td,N,Vheight", MarkedComment(.propertySynthesis, "// @synthesize height", [
            MarkedSegment(.marker, "// "), MarkedSegment(.label, "@synthesize"), MarkedSegment(.separator, " "), MarkedSegment(.name, "height"),
        ])),
        ("title", #"T@"NSString",C,D,N"#, MarkedComment(.propertyDynamic, "// @dynamic title", [
            MarkedSegment(.marker, "// "), MarkedSegment(.label, "@dynamic"), MarkedSegment(.separator, " "), MarkedSegment(.name, "title"),
        ])),
    ])
    func propertyAttribute(name: String, attributesString: String, expected: MarkedComment) throws {
        let context = Self.markingContext(machO: try CommentFixtures.foundationImage())

        let rendering = ObjCPropertyInfo(name: name, attributesString: attributesString, isClassProperty: false)
            .semanticString(using: context)

        #expect(Self.markedComments(of: rendering) == [expected])
    }

    @Test("A method's IMP is marked as an address")
    func methodIMP() throws {
        let machO = try CommentFixtures.foundationImage()
        let imp = CommentFixtures.resolvableIMP(in: machO)
        let address = try #require(machO.formattedAddress(forRawValue: imp))

        let rendering = ObjCMethodInfo(name: "width", typeEncoding: "d16@0:8", isClassMethod: false, imp: imp)
            .semanticString(using: Self.markingContext(machO: machO))

        #expect(Self.markedComments(of: rendering) == [
            MarkedComment(.impAddress, "// IMP: \(address)", [
                MarkedSegment(.marker, "// "), MarkedSegment(.label, "IMP"), MarkedSegment(.separator, ": "), MarkedSegment(.value, address),
            ]),
        ])
    }

    @Test("A note on a type with no signature is text between two markers", arguments: [
        ("@?", "block"),
        ("^?", "function pointer"),
    ])
    func typeNote(typeEncoding: String, note: String) throws {
        let context = Self.markingContext(machO: try CommentFixtures.foundationImage())
        context.options = .default

        let rendering = ObjCIvarInfo(name: "_value", typeEncoding: typeEncoding, offset: 8).semanticString(using: context)

        #expect(Self.markedComments(of: rendering) == [
            MarkedComment(.typeNote, "/* \(note) */", [
                MarkedSegment(.marker, "/* "), MarkedSegment(.text, note), MarkedSegment(.marker, " */"),
            ]),
        ])
    }

    // MARK: - Separation

    @Test("Separating the marks gives the rendering without them back, span for span")
    func separationGivesPlainRendering() throws {
        let machO = try CommentFixtures.foundationImage()
        let resolvableIMP = CommentFixtures.resolvableIMP(in: machO)
        let classInfo = ObjCClassInfo(
            name: "CommentFixture",
            version: 0,
            imageName: nil,
            instanceSize: 40,
            superClassName: "NSObject",
            protocols: [],
            ivars: [
                ObjCIvarInfo(name: "_width", typeEncoding: "d", offset: 8),
                ObjCIvarInfo(name: "_completionHandler", typeEncoding: "@?", offset: 16),
                ObjCIvarInfo(name: "_callback", typeEncoding: "^?", offset: 24),
            ],
            classProperties: [],
            properties: [
                ObjCPropertyInfo(name: "width", attributesString: "Td,N,V_width", isClassProperty: false),
                ObjCPropertyInfo(name: "title", attributesString: #"T@"NSString",C,D,N"#, isClassProperty: false),
            ],
            classMethods: [],
            methods: [
                ObjCMethodInfo(name: "width", typeEncoding: "d16@0:8", isClassMethod: false, imp: resolvableIMP),
                ObjCMethodInfo(name: "setWidth:", typeEncoding: "v24@0:8d16", isClassMethod: false, imp: 1),
            ]
        )
        func rendering(marksCommentStructure: Bool) -> FrozenSemanticString {
            let context = ObjCRenderingContext(machO: machO, options: CommentFixtures.everyComment, marksCommentStructure: marksCommentStructure)
            context.methodIMPs = ["width": resolvableIMP, "setWidth:": 1]
            context.ivarOffsetCommentBuilder = { "ivar offset: \($0)" }
            return classInfo.semanticString(using: context).frozen()
        }

        let (separated, annotations) = rendering(marksCommentStructure: true).separatingAnnotationRegions()

        #expect(separated == rendering(marksCommentStructure: false))
        // Three ivar offsets and two type notes, a synthesis, a dynamic
        // declaration and two accessor addresses, two method IMPs.
        #expect(annotations.regions.count == 11, "\(annotations.regions.map(\.kind.rawValue))")
    }
}
