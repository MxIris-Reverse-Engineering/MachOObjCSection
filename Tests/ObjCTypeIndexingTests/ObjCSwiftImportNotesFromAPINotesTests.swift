#if os(macOS)

import Foundation
import ObjCDeclarationRendering
import Testing
import TypeIndexing
@testable import ObjCTypeIndexing

/// The notes a class's or protocol's API notes give, through a
/// `TypeDatabase` over this Mac's macOS SDK plus a supplementary file.
@available(macOS 13.0, *)
@Suite("Swift import notes from API notes")
struct ObjCSwiftImportNotesFromAPINotesTests {
    private static let supplementaryAPINotesYAML = """
    Name: SampleKit
    Classes:
    - Name: SMPDrawing
      SwiftName: SMPDrawingReference
      Methods:
      - Selector: 'initWithData:error:'
        MethodKind: Instance
        SwiftPrivate: true
      - Selector: 'drawingWithStrokes:'
        MethodKind: Class
        SwiftName: 'init(strokes:)'
      Properties:
      - Name: strokes
        PropertyKind: Instance
        SwiftName: allStrokes
    Protocols:
    - Name: SMPDrawingDelegate
      SwiftPrivate: true
    """

    private static func makeTypeDatabase() async throws -> (typeDatabase: TypeDatabase, temporaryDirectoryURL: URL) {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appending(component: "ObjCSwiftImportNotesFromAPINotesTests-\(UUID().uuidString)")
        let apiNotesDirectoryURL = temporaryDirectoryURL.appending(component: "APINotes")
        try FileManager.default.createDirectory(at: apiNotesDirectoryURL, withIntermediateDirectories: true)
        try supplementaryAPINotesYAML.write(to: apiNotesDirectoryURL.appending(component: "SampleKit.apinotes"), atomically: true, encoding: .utf8)
        let typeDatabase = TypeDatabase(
            platform: .macOS,
            cacheDirectory: temporaryDirectoryURL.appending(component: "Cache"),
            supplementaryAPINotesURLs: [apiNotesDirectoryURL]
        )
        try await typeDatabase.index(dependencies: [], moduleFilter: { _ in false })
        return (typeDatabase, temporaryDirectoryURL)
    }

    @Test
    func apiNotesForClassBecomeNotes() async throws {
        let (typeDatabase, temporaryDirectoryURL) = try await Self.makeTypeDatabase()
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        let notes = await ObjCSwiftImportNotes(apiNotesForClassNamed: "SMPDrawing", in: typeDatabase)
        #expect(notes.declarationNote == .init(swiftName: "SMPDrawingReference"))
        #expect(notes[.method(selector: "initWithData:error:")] == .init(isRefinedForSwift: true))
        #expect(notes[.method(selector: "drawingWithStrokes:", isClassMethod: true)] == .init(swiftName: "init(strokes:)"))
        #expect(notes[.property(name: "strokes")] == .init(swiftName: "allStrokes"))
    }

    @Test
    func apiNotesForProtocolBecomeNotes() async throws {
        let (typeDatabase, temporaryDirectoryURL) = try await Self.makeTypeDatabase()
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        let notes = await ObjCSwiftImportNotes(apiNotesForProtocolNamed: "SMPDrawingDelegate", in: typeDatabase)
        #expect(notes.declarationNote == .init(isRefinedForSwift: true))
        #expect(await ObjCSwiftImportNotes(apiNotesForClassNamed: "SMPDrawingDelegate", in: typeDatabase).isEmpty)
    }

    @Test
    func classTheAPINotesDoNotMentionHasNoNotes() async throws {
        let (typeDatabase, temporaryDirectoryURL) = try await Self.makeTypeDatabase()
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        #expect(await ObjCSwiftImportNotes(apiNotesForClassNamed: "SMPUnknown", in: typeDatabase).isEmpty)
    }

    /// From the SDK itself: PencilKit's `PKDrawing` is
    /// `SwiftName: PKDrawingReference`.
    @Test
    func sdkClassSwiftNameBecomesTheDeclarationNote() async throws {
        let (typeDatabase, temporaryDirectoryURL) = try await Self.makeTypeDatabase()
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        let notes = await ObjCSwiftImportNotes(apiNotesForClassNamed: "PKDrawing", in: typeDatabase)
        #expect(notes.declarationNote?.swiftName == "PKDrawingReference")
    }
}

#endif
