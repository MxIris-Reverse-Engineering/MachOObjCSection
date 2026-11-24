import Foundation
import Semantic

/// What a header says about how Swift imports a class or protocol and its
/// members — the attributes Clang reads off `NS_SWIFT_NAME(...)` and
/// `NS_REFINED_FOR_SWIFT`, of which a binary keeps no trace. A host recovers
/// them and hands them to `ObjCInterfaceBuilder`, which prints each as its
/// macro: a member's at the end of its declaration, the class's or protocol's
/// on a line of its own above `@interface` / `@protocol`:
///
/// ```objc
/// NS_SWIFT_NAME(PKDrawingReference)
/// @interface PKDrawing : NSObject <NSCopying, NSSecureCoding>
/// @property (nonatomic, strong) SHScenePresentationSettings *settings NS_REFINED_FOR_SWIFT;
/// - (void)reload NS_SWIFT_NAME(reloadAll());
/// ```
///
/// Two hosts supply them: MachOSwiftSection infers `NS_REFINED_FOR_SWIFT` from
/// a class's Swift side (for a class Swift implements or extends), and
/// `ObjCTypeIndexing` reads both macros from the SDK's API notes; `merging(_:)`
/// combines the two.
///
/// Shaped like a class's entry in a Clang API notes file: a method is keyed by
/// its selector and whether it is a class method, a property by its name and
/// whether it is a class property, and what is noted about a declaration is a
/// value with one property per attribute.
///
/// ```swift
/// var notes = ObjCSwiftImportNotes()
/// notes.declarationNote = .init(swiftName: "PKDrawingReference")
/// notes[.property(name: "settings")] = .init(isRefinedForSwift: true)
/// let header = builder.classInterface(named: "PKDrawing", swiftImportNotes: notes)
/// ```
public struct ObjCSwiftImportNotes: Sendable, Hashable {
    /// The member a note is about, keyed as an API notes file keys it.
    public enum Member: Sendable, Hashable {
        /// A property by its name, the one `@property` declares.
        case property(name: String, isClassProperty: Bool = false)
        /// A method by its selector (`initWithDomain:code:userInfo:`).
        case method(selector: String, isClassMethod: Bool = false)
    }

    /// What the header says about one declaration.
    public struct Note: Sendable, Hashable {
        /// `NS_REFINED_FOR_SWIFT` — `SwiftPrivate` in API notes. Swift
        /// imports the declaration under a name with `__` in front (a type's
        /// or property's name, a method's base name, an initializer's first
        /// argument label), which leaves the plain name to a Swift declaration
        /// that wraps it.
        public var isRefinedForSwift: Bool

        /// `NS_SWIFT_NAME(...)` — `SwiftName` in API notes: the name Swift
        /// imports the declaration under, as written (`PKDrawingReference`,
        /// `reloadAll()`).
        public var swiftName: String?

        public init(isRefinedForSwift: Bool = false, swiftName: String? = nil) {
            self.isRefinedForSwift = isRefinedForSwift
            self.swiftName = swiftName
        }

        /// Whether the note prints nothing.
        public var isEmpty: Bool {
            !isRefinedForSwift && swiftName == nil
        }

        /// This note with `other`'s attributes on top: `other`'s Swift name
        /// when it has one, and refined for Swift when either note is.
        public func merging(_ other: Note) -> Note {
            Note(isRefinedForSwift: isRefinedForSwift || other.isRefinedForSwift, swiftName: other.swiftName ?? swiftName)
        }
    }

    private var notesByMember: [Member: Note]

    /// What the header says about the class or protocol itself, printed on a
    /// line of its own above its `@interface` / `@protocol`. A category is no
    /// declaration of its class, so a category's rendering leaves it out.
    public var declarationNote: Note?

    /// No notes: the header says nothing about the declaration or any member.
    public init() {
        notesByMember = [:]
        declarationNote = nil
    }

    public init(_ notesByMember: [Member: Note], declarationNote: Note? = nil) {
        self.notesByMember = notesByMember
        self.declarationNote = declarationNote
    }

    /// The note about `member`; `nil` when there is none, and setting `nil`
    /// removes it.
    public subscript(member: Member) -> Note? {
        get { notesByMember[member] }
        set { notesByMember[member] = newValue }
    }

    /// Whether neither the declaration nor any member has a note.
    public var isEmpty: Bool {
        notesByMember.isEmpty && declarationNote == nil
    }

    /// These notes with `other`'s on top, declaration and member by member:
    /// a note only one side has is kept, and two notes about the same
    /// declaration merge as `Note.merging(_:)` does — `other`'s Swift name
    /// wins, and either side's `NS_REFINED_FOR_SWIFT` stays.
    public func merging(_ other: ObjCSwiftImportNotes) -> ObjCSwiftImportNotes {
        var merged = self
        for (member, otherNote) in other.notesByMember {
            merged.notesByMember[member] = merged.notesByMember[member].map { $0.merging(otherNote) } ?? otherNote
        }
        if let otherDeclarationNote = other.declarationNote {
            merged.declarationNote = merged.declarationNote.map { $0.merging(otherDeclarationNote) } ?? otherDeclarationNote
        }
        return merged
    }
}

extension ObjCRenderingContext {
    /// The macros `swiftImportNotes` puts at the end of `member`'s
    /// declaration, each after a space, ahead of the `;`; nothing when there
    /// is no note about it. `NS_SWIFT_NAME(...)` comes first, as Apple's
    /// headers write it. Not optional content: a host that supplies a note
    /// wants it shown under every switch, so a marked rendering carries it
    /// unmarked and its projections read as the plain renderings do.
    ///
    /// The macros are `.macro` runs, not keywords: Xcode colours both in an
    /// SDK header with its macro colour (`xcode.syntax.identifier.macro.system`).
    @SemanticStringBuilder
    package func swiftImportAttributes(of member: ObjCSwiftImportNotes.Member) -> SemanticString {
        if let note = swiftImportNotes[member] {
            if let swiftName = note.swiftName {
                Space()
                Self.swiftNameMacro(swiftName)
            }
            if note.isRefinedForSwift {
                Space()
                Macro("NS_REFINED_FOR_SWIFT")
            }
        }
    }

    /// The line `swiftImportNotes.declarationNote` puts above a class's or
    /// protocol's `@interface` / `@protocol` — its macros separated by a
    /// space, then a line break; nothing when there is no such note. Not
    /// optional content, for the reason `swiftImportAttributes(of:)` gives.
    @SemanticStringBuilder
    package func swiftImportDeclarationAttributes() -> SemanticString {
        if let note = swiftImportNotes.declarationNote, !note.isEmpty {
            if let swiftName = note.swiftName {
                Self.swiftNameMacro(swiftName)
                if note.isRefinedForSwift {
                    Space()
                }
            }
            if note.isRefinedForSwift {
                Macro("NS_REFINED_FOR_SWIFT")
            }
            BreakLine()
        }
    }

    /// `NS_SWIFT_NAME(name)`: the macro, then the Swift name as plain text,
    /// which Xcode does not colour either.
    @SemanticStringBuilder
    private static func swiftNameMacro(_ swiftName: String) -> SemanticString {
        Macro("NS_SWIFT_NAME")
        "("
        Standard(swiftName)
        ")"
    }
}
