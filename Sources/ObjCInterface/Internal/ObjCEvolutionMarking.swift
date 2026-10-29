import Foundation
import ObjCDiffing
import Semantic

/// One declaration's lifecycle as the evolution interface phrases it: its
/// presence bitmap and the events at the transitions where it changed.
///
/// The facts come from one `ObjCAPIEvolution` lineage. Only the text of a
/// `modified` event's two sides is the renderer's own: the line each version
/// rendered for the declaration, where the lineage carries snapshot
/// signatures.
struct ObjCEvolutionAnnotation: Equatable {
    struct Event: Equatable {
        enum Change: Equatable {
            case added
            case removed
            /// The two sides as rendered, `nil` when not worth showing: a
            /// change no rendered line makes visible keeps the bare phrase.
            case modified(old: String?, new: String?)
            /// The declaration changed images, in an evolution of image groups.
            case moved(ObjCImageMove)
        }

        /// The version the transition arrives at; `versions[versionIndex - 1]`
        /// is the one before it.
        let versionIndex: Int
        let change: Change
        /// The adopted protocol the member came with, as the lineage event
        /// names it (`ObjCLineageEvent.viaProtocolName`).
        var viaProtocolName: String? = nil
    }

    /// What the annotation is about when it does not trail its own
    /// declaration line: `superclass`, `adopts <NSCoding>`. `nil` for a
    /// declaration's own annotation.
    let subject: String?
    /// One entry per version on the axis.
    let presence: [Bool]
    /// Ordered by version; never empty — a declaration without events carries
    /// no annotation at all.
    let events: [Event]
}

/// One output line of the evolution interface: the line's text without its
/// structural indentation, the indentation level, and the annotation that
/// trails it.
struct ObjCEvolutionLine {
    /// Exactly one line; `content.string` never contains a newline.
    let content: SemanticString
    let indentLevel: Int
    let annotation: ObjCEvolutionAnnotation?

    init(content: SemanticString, indentLevel: Int = 0, annotation: ObjCEvolutionAnnotation? = nil) {
        self.content = content
        self.indentLevel = indentLevel
        self.annotation = annotation
    }

    /// An empty line, as between two groups of members.
    static let blank = ObjCEvolutionLine(content: SemanticString())
}

/// The format layer of the evolution interface: how an annotation becomes a
/// comment, how a lifecycle becomes an availability macro, and how the lines
/// of the declarations become the final text. Mirrors the rules of
/// MachOSwiftSection's Swift evolution interface (its `EvolutionMarking`), so
/// the two views of one module read alike. Pure functions of their inputs.
enum ObjCEvolutionMarking {
    /// Structural indentation width per level, as the declaration renderers
    /// indent an ivar block.
    static let indentWidth = 4

    /// Within one declaration, annotations align at `min(cap, longest
    /// annotated code line + gutter)`; a line whose code runs past that column
    /// gets its annotation on the next line instead, one level deeper.
    static let annotationColumnCap = 72

    /// The minimum gap between a line's code and its annotation.
    static let annotationGutterWidth = 2

    // MARK: - Lines

    /// Splits a rendering into its lines. Each line keeps the semantic types
    /// of the text it holds; an empty `source` has no lines.
    static func lines(of source: SemanticString) -> [SemanticString] {
        if source.isEmpty { return [] }
        var lineComponents: [[AtomicComponent]] = [[]]
        for component in source.components {
            let pieces = component.string.split(separator: "\n", omittingEmptySubsequences: false)
            for (pieceIndex, piece) in pieces.enumerated() {
                if pieceIndex > 0 {
                    lineComponents.append([])
                }
                if !piece.isEmpty {
                    lineComponents[lineComponents.count - 1].append(AtomicComponent(string: String(piece), type: component.type))
                }
            }
        }
        return lineComponents.map { SemanticString(components: $0) }
    }

    /// A rendering on one line, for the two sides of a `modified` phrase: the
    /// lines of an inline-expanded struct joined by single spaces.
    static func singleLine(_ source: SemanticString) -> String {
        source.string
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Annotation text

    /// `[●●○]`, one position per version on the axis.
    static func bitmap(_ presence: [Bool]) -> String {
        "[" + presence.map { $0 ? "●" : "○" }.joined() + "]"
    }

    /// One event phrased against the version axis, naming the protocol a
    /// member came with (`added in 13.0 via <NSAKLayoutItem>`). A `modified`
    /// event whose two sides read the same keeps the bare phrase: `A → A`
    /// says nothing.
    static func phrase(for event: ObjCEvolutionAnnotation.Event, versions: [ObjCAPIVersionDescriptor]) -> String {
        let label = versions.indices.contains(event.versionIndex)
            ? versions[event.versionIndex].label
            : "v\(event.versionIndex + 1)"
        let protocolPhrase = event.viaProtocolName.map { " via <\($0)>" } ?? ""
        switch event.change {
        case .added:
            return "added in \(label)\(protocolPhrase)"
        case .removed:
            return "removed in \(label)\(protocolPhrase)"
        case .modified(let old, let new):
            guard let old, let new, old != new else {
                return "modified in \(label)\(protocolPhrase)"
            }
            return "modified in \(label)\(protocolPhrase): \(old) → \(new)"
        case .moved(let move):
            return move.phrase(versionLabel: label)
        }
    }

    /// The whole comment: `// [●●○] removed in 14.0`, or with a subject
    /// `// [●●○] adopts <NSCoding> removed in 14.0`; several events are joined
    /// by ` · `.
    static func annotationText(for annotation: ObjCEvolutionAnnotation, versions: [ObjCAPIVersionDescriptor]) -> String {
        var text = "// " + bitmap(annotation.presence)
        if let subject = annotation.subject {
            text += " " + subject
        }
        let phrases = annotation.events.map { phrase(for: $0, versions: versions) }
        if !phrases.isEmpty {
            text += " " + phrases.joined(separator: " · ")
        }
        return text
    }

    // MARK: - Availability

    /// The SDK macro that tells a declaration's whole presence story, or `nil`
    /// when no single macro can:
    ///
    /// - Present from some point on the axis to its end:
    ///   `API_AVAILABLE(macos(13.0))`.
    /// - Present from some point on the axis, then gone:
    ///   `API_OBSOLETED("Removed", macos(13.0, 14.0, 14.0))`. The macro takes
    ///   the introduced, deprecated and obsoleted versions; the axis knows no
    ///   deprecation, so it is the removal, as the SDK writes an API deprecated
    ///   and removed in one release.
    /// - Nothing otherwise: present on the whole axis (modified or not),
    ///   present more than once (`●○●`), or present from the axis start and
    ///   later removed — `API_OBSOLETED` needs an introduction version and the
    ///   axis does not know it. The Swift view writes that last case as
    ///   `@available(macOS, obsoleted:)`; the SDK macro has no such form.
    /// - Nothing, either, when a version involved has a label that is not one
    ///   to three dot-separated numbers.
    static func availabilityMacro(presence: [Bool], versions: [ObjCAPIVersionDescriptor], platform: String) -> String? {
        guard presence.count == versions.count,
              let firstPresentIndex = presence.firstIndex(of: true),
              firstPresentIndex > 0,
              let introducedVersion = availabilityVersion(fromLabel: versions[firstPresentIndex].label)
        else { return nil }
        guard let firstAbsentIndex = presence[firstPresentIndex...].firstIndex(of: false) else {
            return "API_AVAILABLE(\(platform)(\(introducedVersion)))"
        }
        guard !presence[firstAbsentIndex...].contains(true),
              let obsoletedVersion = availabilityVersion(fromLabel: versions[firstAbsentIndex].label)
        else { return nil }
        return "API_OBSOLETED(\"Removed\", \(platform)(\(introducedVersion), \(obsoletedVersion), \(obsoletedVersion)))"
    }

    /// A label usable as an availability version: one to three dot-separated
    /// runs of ASCII digits (`13`, `13.0`, `12.0.1`), returned verbatim.
    static func availabilityVersion(fromLabel label: String) -> String? {
        let components = label.split(separator: ".", omittingEmptySubsequences: false)
        guard (1 ... 3).contains(components.count) else { return nil }
        for component in components {
            guard !component.isEmpty, component.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        }
        return label
    }

    /// A method or property declaration with `macro` before its closing `;`,
    /// where the SDK headers put it. Unchanged when `macro` is `nil` or the
    /// declaration does not end in `;`.
    static func declaration(_ declaration: SemanticString, withAvailabilityMacro macro: String?) -> SemanticString {
        guard let macro,
              let lastComponent = declaration.components.last,
              lastComponent.string.hasSuffix(";")
        else { return declaration }
        var components = Array(declaration.components.dropLast())
        let textBeforeSemicolon = String(lastComponent.string.dropLast())
        if !textBeforeSemicolon.isEmpty {
            components.append(AtomicComponent(string: textBeforeSemicolon, type: lastComponent.type))
        }
        components.append(AtomicComponent(string: " ", type: .standard))
        components.append(AtomicComponent(string: macro, type: .keyword))
        components.append(AtomicComponent(string: ";", type: lastComponent.type))
        return SemanticString(components: components)
    }

    // MARK: - Document

    /// The finished interface: the legend, the declarations separated by blank
    /// lines, and — when some version had identity-key collisions — the
    /// warnings `ObjCAPIEvolutionReporter` lists, as comments.
    static func renderInterface(
        blocks: [[ObjCEvolutionLine]],
        evolution: ObjCAPIEvolution,
        availabilityPlatform: String?
    ) -> SemanticString {
        var result = legendLines(versions: evolution.versions, availabilityPlatform: availabilityPlatform)
        for block in blocks {
            let renderedBlock = renderBlock(block, versions: evolution.versions)
            if renderedBlock.isEmpty { continue }
            result.append("\n\n", type: .standard)
            result.append(renderedBlock)
        }
        if let warnings = warningsLines(for: evolution) {
            result.append("\n\n", type: .standard)
            result.append(warnings)
        }
        return result
    }

    /// The axis and what each bitmap position stands for; for image groups,
    /// each image with the versions holding it, as the lineage report lists
    /// them; with availability macros on, a line saying what their versions
    /// mean, once, so no macro in the body claims more than the axis knows.
    static func legendLines(versions: [ObjCAPIVersionDescriptor], availabilityPlatform: String?) -> SemanticString {
        let labels = versions.map(\.label)
        var result = SemanticString()
        result.append("// ObjC API evolution across \(labels.count) versions: \(labels.joined(separator: " → "))", type: .comment)
        result.append("\n", type: .standard)
        result.append(
            "// Bitmap positions: " + labels.enumerated().map { "[\($0 + 1)] \($1)" }.joined(separator: "  "),
            type: .comment
        )
        if let imageGroupPresence = versions.imageGroupPresence {
            result.append("\n", type: .standard)
            result.append("// Image group:", type: .comment)
            for image in imageGroupPresence {
                result.append("\n", type: .standard)
                result.append("//   \(bitmap(image.presence)) \(image.imageName)", type: .comment)
            }
        }
        if availabilityPlatform != nil {
            result.append("\n", type: .standard)
            result.append(
                "// API_AVAILABLE and API_OBSOLETED versions are axis points: the introduced version is the first axis point carrying a declaration, the obsoleted version the first one without it — not necessarily the releases that really introduced or removed it.",
                type: .comment
            )
        }
        return result
    }

    /// One declaration's lines. Annotations align on the declaration's own
    /// column (see ``annotationColumnCap``); an empty line writes nothing, not
    /// even its indentation.
    static func renderBlock(_ block: [ObjCEvolutionLine], versions: [ObjCAPIVersionDescriptor]) -> SemanticString {
        let annotatedWidths = block.compactMap { line in
            line.annotation != nil ? codeWidth(of: line) : nil
        }
        let annotationColumn = min(annotationColumnCap, (annotatedWidths.max() ?? 0) + annotationGutterWidth)

        var result = SemanticString()
        for (lineIndex, line) in block.enumerated() {
            if lineIndex > 0 {
                result.append("\n", type: .standard)
            }
            if !line.content.isEmpty {
                if line.indentLevel > 0 {
                    result.append(String(repeating: " ", count: line.indentLevel * indentWidth), type: .standard)
                }
                result.append(line.content)
            }

            guard let annotation = line.annotation else { continue }
            let text = annotationText(for: annotation, versions: versions)
            let width = codeWidth(of: line)
            if width + annotationGutterWidth <= annotationColumn {
                result.append(String(repeating: " ", count: annotationColumn - width), type: .standard)
            } else {
                result.append("\n", type: .standard)
                result.append(String(repeating: " ", count: (max(0, line.indentLevel) + 1) * indentWidth), type: .standard)
            }
            result.append(text, type: .comment)
        }
        return result
    }

    /// The identity-key collisions, worded as `ObjCAPIEvolutionReporter`
    /// words them, or `nil` when there are none.
    static func warningsLines(for evolution: ObjCAPIEvolution) -> SemanticString? {
        guard let keyCollisionsByVersion = evolution.keyCollisionsByVersion else { return nil }
        var result = SemanticString()
        result.append("// " + ObjCAPIKeyCollision.warningsHeading, type: .comment)
        for (versionIndex, collisions) in keyCollisionsByVersion.enumerated() {
            for collision in collisions {
                let scope = collision.containerName.map { "\($0) · " } ?? ""
                result.append("\n", type: .standard)
                result.append(
                    "//   \(evolution.versions[versionIndex].label) · \(scope)\(collision.recordsDescription)",
                    type: .comment
                )
            }
        }
        return result
    }

    /// The width of a line's code: indentation plus content.
    private static func codeWidth(of line: ObjCEvolutionLine) -> Int {
        max(0, line.indentLevel) * indentWidth + line.content.string.count
    }
}
