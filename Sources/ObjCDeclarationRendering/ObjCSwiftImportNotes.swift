import Foundation
import Semantic

/// What a header says about how Swift imports a class's members — the
/// attributes Clang reads off macros such as `NS_REFINED_FOR_SWIFT`, of which
/// a binary keeps no trace. A host that reads the class's Swift side recovers
/// some of them (MachOSwiftSection, for a class Swift implements or extends)
/// and hands them to `ObjCInterfaceBuilder`, which prints each as its macro at
/// the end of the member's declaration:
///
/// ```objc
/// @property (nonatomic, strong) SHScenePresentationSettings *settings NS_REFINED_FOR_SWIFT;
/// ```
///
/// Shaped like a class's entry in a Clang API notes file: a method is keyed by
/// its selector and whether it is a class method, a property by its name and
/// whether it is a class property, and what is noted about a member is a value
/// with one property per attribute — `NS_SWIFT_NAME` would be another one.
///
/// ```swift
/// var notes = ObjCSwiftImportNotes()
/// notes[.property(name: "settings")] = .init(isRefinedForSwift: true)
/// let header = builder.classInterface(named: "SHScenePresentation", swiftImportNotes: notes)
/// ```
public struct ObjCSwiftImportNotes: Sendable, Hashable {
    /// The member a note is about, keyed as an API notes file keys it.
    public enum Member: Sendable, Hashable {
        /// A property by its name, the one `@property` declares.
        case property(name: String, isClassProperty: Bool = false)
        /// A method by its selector (`initWithDomain:code:userInfo:`).
        case method(selector: String, isClassMethod: Bool = false)
    }

    /// What the header says about one member.
    public struct Note: Sendable, Hashable {
        /// `NS_REFINED_FOR_SWIFT` — `SwiftPrivate` in API notes. Swift
        /// imports the member under a name with `__` in front (a property's
        /// name, a method's base name, an initializer's first argument
        /// label), which leaves the plain name to a Swift declaration that
        /// wraps it.
        public var isRefinedForSwift: Bool

        public init(isRefinedForSwift: Bool = false) {
            self.isRefinedForSwift = isRefinedForSwift
        }
    }

    private var notesByMember: [Member: Note]

    /// No notes: the header says nothing about any member.
    public init() {
        notesByMember = [:]
    }

    public init(_ notesByMember: [Member: Note]) {
        self.notesByMember = notesByMember
    }

    /// The note about `member`; `nil` when there is none, and setting `nil`
    /// removes it.
    public subscript(member: Member) -> Note? {
        get { notesByMember[member] }
        set { notesByMember[member] = newValue }
    }

    /// Whether no member has a note.
    public var isEmpty: Bool {
        notesByMember.isEmpty
    }
}

extension ObjCRenderingContext {
    /// The macros `swiftImportNotes` puts at the end of `member`'s
    /// declaration, each after a space, ahead of the `;`; nothing when there
    /// is no note about it. Not optional content: a host that supplies a note
    /// wants it shown under every switch, so a marked rendering carries it
    /// unmarked and its projections read as the plain renderings do.
    @SemanticStringBuilder
    package func swiftImportAttributes(of member: ObjCSwiftImportNotes.Member) -> SemanticString {
        if let note = swiftImportNotes[member], note.isRefinedForSwift {
            Space()
            Keyword("NS_REFINED_FOR_SWIFT")
        }
    }
}
