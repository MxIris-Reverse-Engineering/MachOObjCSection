import Testing
@testable import ObjCDeclarationRendering

/// `ObjCSwiftImportNotes` as a value: what is empty, and how two hosts' notes
/// about one declaration combine — RuntimeViewer merges the notes it infers
/// from the Swift side with the ones the SDK's API notes give.
@Suite("Swift import notes values")
struct ObjCSwiftImportNotesTests {
    @Test("notes with a note about the declaration alone are not empty")
    func declarationNoteMakesNotesNonEmpty() {
        var notes = ObjCSwiftImportNotes()
        #expect(notes.isEmpty)
        notes.declarationNote = .init(isRefinedForSwift: true)
        #expect(!notes.isEmpty)
    }

    @Test("merging keeps every member of both, and the argument wins field by field")
    func mergingKeepsBothSourcesAndTheArgumentWinsPerField() {
        var inferred = ObjCSwiftImportNotes()
        inferred[.property(name: "settings")] = .init(isRefinedForSwift: true)
        inferred[.method(selector: "shared", isClassMethod: true)] = .init(isRefinedForSwift: true, swiftName: "inferredShared()")
        inferred.declarationNote = .init(isRefinedForSwift: true)

        var declared = ObjCSwiftImportNotes()
        declared[.method(selector: "shared", isClassMethod: true)] = .init(swiftName: "makeShared()")
        declared[.method(selector: "reload")] = .init(swiftName: "reloadAll()")
        declared.declarationNote = .init(swiftName: "SwiftSample")

        let merged = inferred.merging(declared)
        #expect(merged[.property(name: "settings")] == .init(isRefinedForSwift: true))
        #expect(merged[.method(selector: "shared", isClassMethod: true)] == .init(isRefinedForSwift: true, swiftName: "makeShared()"))
        #expect(merged[.method(selector: "reload")] == .init(swiftName: "reloadAll()"))
        #expect(merged.declarationNote == .init(isRefinedForSwift: true, swiftName: "SwiftSample"))
    }

    @Test("merging with empty notes changes nothing")
    func mergingWithEmptyNotesChangesNothing() {
        var notes = ObjCSwiftImportNotes()
        notes[.method(selector: "reload")] = .init(swiftName: "reloadAll()")
        #expect(notes.merging(ObjCSwiftImportNotes()) == notes)
        #expect(ObjCSwiftImportNotes().merging(notes) == notes)
    }
}
