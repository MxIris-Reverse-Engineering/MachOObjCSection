import Semantic

/// A comment a declaration rendering writes, described once: the text it
/// reads as, split into the segments a host draws apart — the comment
/// marker, a label, a separator, a value.
///
/// Rendered plain, each run of adjacent segments of one semantic type is one
/// atom, which is what these comments have always been: `// offset: 8` is one
/// `.comment` atom, and `// IMP: <invalid 0x0>` a `.comment` atom followed by
/// an `.error` one.
package struct ObjCComment: Sendable {
    /// What a comment says.
    package enum Kind: Sendable {
        /// `// IMP: 0x1A2B` after a method, `// getter IMP: 0x1A2B` and
        /// `// setter IMP: 0x1A2B` after a property.
        case impAddress
        /// `// offset: 8` after an ivar, or the host's wording of it.
        case ivarOffset
        /// `// offset: unknown` after an ivar whose offset the image does not
        /// record.
        case ivarOffsetUnknown
        /// `// @synthesize name`, or `// @synthesize name = ivar`.
        case propertySynthesis
        /// `// @dynamic name`.
        case propertyDynamic
        /// `/* block */` and `/* function pointer */` inside a type.
        case typeNote
        /// Explanatory text, such as the line above a host-supplied class.
        case note
    }

    /// What one segment of a comment is.
    package enum Role: Sendable {
        /// `// `, `/* ` or ` */`.
        case marker
        /// What the value is: `IMP`, `offset`, `@synthesize`.
        case label
        /// `: `, ` = `, or the space after `@synthesize`.
        case separator
        /// The name of the property a comment is about.
        case name
        /// An address, an offset, an ivar name.
        case value
        /// Explanatory text.
        case text
    }

    package struct Segment: Sendable {
        package let role: Role
        package let text: String
        package let type: SemanticType

        package init(_ role: Role, _ text: String, type: SemanticType = .comment) {
            self.role = role
            self.text = text
            self.type = type
        }

        static let lineCommentMarker = Segment(.marker, "// ")
        static let inlineCommentStartMarker = Segment(.marker, "/* ")
        static let inlineCommentEndMarker = Segment(.marker, " */")
        static let colonSeparator = Segment(.separator, ": ")
    }

    package let kind: Kind
    package let segments: [Segment]

    package init(kind: Kind, segments: [Segment]) {
        self.kind = kind
        self.segments = segments
    }

    /// The comment as plain text: each run of adjacent segments of one
    /// semantic type is one atom.
    package var plainRendering: SemanticString {
        var rendering = SemanticString()
        var runText = ""
        var runType: SemanticType?
        for segment in segments where !segment.text.isEmpty {
            if let runType, runType != segment.type {
                rendering.append(runText, type: runType)
                runText = ""
            }
            runType = segment.type
            runText += segment.text
        }
        if let runType {
            rendering.append(runText, type: runType)
        }
        return rendering
    }
}

// MARK: - Comments

extension ObjCComment {
    /// `// IMP: 0x1A2B`, labeled `IMP`, `getter IMP` or `setter IMP`.
    package static func impAddress(label: String, address: String) -> ObjCComment {
        ObjCComment(kind: .impAddress, segments: [
            .lineCommentMarker,
            Segment(.label, label),
            .colonSeparator,
            Segment(.value, address),
        ])
    }

    /// `// IMP: <invalid 0x0>`: an IMP field that holds no usable
    /// implementation pointer, its raw value written as an error.
    package static func impAddress(label: String, invalidAddress: String) -> ObjCComment {
        ObjCComment(kind: .impAddress, segments: [
            .lineCommentMarker,
            Segment(.label, label),
            .colonSeparator,
            Segment(.value, invalidAddress, type: .error),
        ])
    }

    /// `// offset: 8`.
    package static func ivarOffset(_ offset: Int) -> ObjCComment {
        ObjCComment(kind: .ivarOffset, segments: [
            .lineCommentMarker,
            Segment(.label, "offset"),
            .colonSeparator,
            Segment(.value, "\(offset)"),
        ])
    }

    /// The ivar offset comment as the host worded it
    /// (``ObjCRenderingContext/ivarOffsetCommentBuilder``).
    package static func ivarOffset(wordedByHost body: String) -> ObjCComment {
        ObjCComment(kind: .ivarOffset, segments: [
            .lineCommentMarker,
            Segment(.value, body),
        ])
    }

    /// `// offset: unknown`.
    package static let unknownIvarOffset = ObjCComment(kind: .ivarOffsetUnknown, segments: [
        .lineCommentMarker,
        Segment(.label, "offset"),
        .colonSeparator,
        Segment(.value, "unknown"),
    ])

    /// `// @synthesize name = ivar`, or `// @synthesize name` when the ivar
    /// has the property's name.
    package static func propertySynthesis(propertyName: String, ivarName: String) -> ObjCComment {
        var segments: [Segment] = [
            .lineCommentMarker,
            Segment(.label, "@synthesize"),
            Segment(.separator, " "),
            Segment(.name, propertyName),
        ]
        if ivarName != propertyName {
            segments.append(Segment(.separator, " = "))
            segments.append(Segment(.value, ivarName))
        }
        return ObjCComment(kind: .propertySynthesis, segments: segments)
    }

    /// `// @dynamic name`.
    package static func propertyDynamic(propertyName: String) -> ObjCComment {
        ObjCComment(kind: .propertyDynamic, segments: [
            .lineCommentMarker,
            Segment(.label, "@dynamic"),
            Segment(.separator, " "),
            Segment(.name, propertyName),
        ])
    }

    /// `/* block */` after `id`, `/* function pointer */` after `void *`: what
    /// a type the encoding gives no signature for really is.
    package static func typeNote(_ text: String) -> ObjCComment {
        ObjCComment(kind: .typeNote, segments: [
            .inlineCommentStartMarker,
            Segment(.text, text),
            .inlineCommentEndMarker,
        ])
    }

    /// `// <text>`.
    package static func note(_ text: String) -> ObjCComment {
        ObjCComment(kind: .note, segments: [
            .lineCommentMarker,
            Segment(.text, text),
        ])
    }
}

// MARK: - Rendering

extension ObjCRenderingContext {
    /// `comment` as this rendering writes it. Every comment a declaration
    /// rendering adds goes through here.
    package func comment(_ comment: ObjCComment) -> SemanticString {
        comment.plainRendering
    }
}
