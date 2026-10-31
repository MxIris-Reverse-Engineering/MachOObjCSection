import Semantic

/// A comment a declaration rendering writes, described once: the text it
/// reads as, split into the segments a host draws apart — the comment
/// marker, a label, a separator, a value.
///
/// Rendered plain, each run of adjacent segments of one semantic type is one
/// atom, which is what these comments have always been: `// offset: 8` is one
/// `.comment` atom, and `// IMP: <invalid 0x0>` a `.comment` atom followed by
/// an `.error` one. With its structure marked, the same atoms come in pieces
/// inside annotation regions, and separating the regions gives the plain
/// rendering back, span for span.
package struct ObjCComment: Sendable {
    package struct Segment: Sendable {
        package let role: AnnotationSegment.Role
        package let text: String
        package let type: SemanticType

        package init(_ role: AnnotationSegment.Role, _ text: String, type: SemanticType = .comment) {
            self.role = role
            self.text = text
            self.type = type
        }

        static let lineCommentMarker = Segment(.marker, "// ")
        static let inlineCommentStartMarker = Segment(.marker, "/* ")
        static let inlineCommentEndMarker = Segment(.marker, " */")
        static let colonSeparator = Segment(.separator, ": ")
    }

    package let kind: AnnotationRegion.Kind
    package let segments: [Segment]

    package init(kind: AnnotationRegion.Kind, segments: [Segment]) {
        self.kind = kind
        self.segments = segments
    }

    /// The segments that render anything, in runs of one semantic type: the
    /// atoms of the plain rendering.
    private var atomRuns: [(type: SemanticType, segments: [Segment])] {
        var runs: [(type: SemanticType, segments: [Segment])] = []
        for segment in segments where !segment.text.isEmpty {
            if let lastRun = runs.last, lastRun.type == segment.type {
                runs[runs.count - 1].segments.append(segment)
            } else {
                runs.append((segment.type, [segment]))
            }
        }
        return runs
    }

    /// The comment as plain text: each run of adjacent segments of one
    /// semantic type is one atom.
    package var plainRendering: SemanticString {
        var rendering = SemanticString()
        for run in atomRuns {
            rendering.append(run.segments.map(\.text).joined(), type: run.type)
        }
        return rendering
    }

    /// The comment with its structure marked: an `AnnotationRegion` of its
    /// kind around it, an `AnnotatedAtom` for each atom of the plain
    /// rendering, and an `AnnotationSegment` of its role around each segment.
    @SemanticStringBuilder
    package var markedRendering: SemanticString {
        let atomRuns = atomRuns
        AnnotationRegion(kind) {
            for run in atomRuns {
                AnnotatedAtom(type: run.type) {
                    for segment in run.segments {
                        AnnotationSegment(segment.role) {
                            segment.text
                        }
                    }
                }
            }
        }
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
    /// (``ObjCRenderingContext/ivarOffsetCommentBuilder``), in segments by
    /// one rule, since the wording is the host's: up to the first `: ` is the
    /// label, the rest the value, and wording without `: ` is all value.
    /// `Transformer.ObjCIvarOffset`'s own templates — `offset: ${offset}`,
    /// `ivar offset: ${offset}`, `${offset}` — split exactly so.
    package static func ivarOffset(wordedByHost body: String) -> ObjCComment {
        guard let separatorRange = body.range(of: ": ") else {
            return ObjCComment(kind: .ivarOffset, segments: [.lineCommentMarker, Segment(.value, body)])
        }
        return ObjCComment(kind: .ivarOffset, segments: [
            .lineCommentMarker,
            Segment(.label, String(body[..<separatorRange.lowerBound])),
            .colonSeparator,
            Segment(.value, String(body[separatorRange.upperBound...])),
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
    /// `comment` as this rendering writes it: marked with its structure when
    /// ``marksCommentStructure`` is set, plain otherwise. Every comment a
    /// declaration rendering adds goes through here.
    package func comment(_ comment: ObjCComment) -> SemanticString {
        marksCommentStructure ? comment.markedRendering : comment.plainRendering
    }
}
