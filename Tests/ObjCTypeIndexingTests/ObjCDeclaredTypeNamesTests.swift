#if os(macOS)

import Foundation
import MachOKit
import Testing
import TypeIndexing
internal import MachOKitExtensions
@testable import ObjCTypeIndexing

/// `ObjCDeclaredTypeNames` over Foundation as loaded into this process.
@Suite("Declared type names")
struct ObjCDeclaredTypeNamesTests {
    enum FixtureError: Swift.Error {
        case foundationImageUnavailable
    }

    private static func foundationSource() throws -> ObjCDeclaredTypeNames<MachOImage> {
        guard let machO = MachOImage(name: "Foundation") else {
            throw FixtureError.foundationImageUnavailable
        }
        return ObjCDeclaredTypeNames(machO: machO, imagePath: machO.imagePath)
    }

    @Test
    func declaredTypeNamesListFoundationClassesProtocolsAndStructs() async throws {
        let declaredNames = Set(try await Self.foundationSource().declaredTypeNames())
        #expect(declaredNames.contains("NSURLSession"))
        #expect(declaredNames.contains("NSURLSessionDelegate"))
        #expect(declaredNames.contains("_NSRange"))
    }

    /// A private class no SDK file mentions resolves to Foundation through the
    /// runtime-metadata layer. The name is taken from the image itself, so the
    /// test does not hang on one OS version's private classes.
    @available(macOS 13.0, *)
    @Test
    func typeDatabaseAttributesPrivateClassThroughObjCDeclaredTypeNames() async throws {
        let source = try Self.foundationSource()
        let privateClassName = try #require(
            try await source.declaredTypeNames().first { $0.hasPrefix("__NS") || $0.hasPrefix("_NS") }
        )
        let cacheDirectoryURL = FileManager.default.temporaryDirectory
            .appending(component: "ObjCDeclaredTypeNamesTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: cacheDirectoryURL) }

        let typeDatabase = TypeDatabase(platform: .macOS, cacheDirectory: cacheDirectoryURL)
        try await typeDatabase.index(dependencies: [source], moduleFilter: { _ in false })
        #expect(await typeDatabase.moduleName(forTypeName: privateClassName) == "Foundation")
    }
}

#endif
