#if os(macOS)

import Foundation
import MachOKit
import Testing
import TypeIndexing
import ObjCIndexing
internal import MachOKitExtensions
@testable import ObjCTypeIndexing

/// `ObjCDeclaredTypeNames` over Foundation as loaded into this process.
@Suite("Declared type names")
struct ObjCDeclaredTypeNamesTests {
    enum FixtureError: Swift.Error {
        case foundationImageUnavailable
    }

    private static func foundationImage() throws -> MachOImage {
        guard let machO = MachOImage(name: "Foundation") else {
            throw FixtureError.foundationImageUnavailable
        }
        return machO
    }

    private static func foundationSource() throws -> ObjCDeclaredTypeNames<MachOImage> {
        let machO = try foundationImage()
        return ObjCDeclaredTypeNames(machO: machO, imagePath: machO.imagePath)
    }

    /// Exactly the classes, protocols, structs and unions an indexer of the
    /// image lists — compared with the indexer rather than spelled out, so
    /// the test does not hang on what one release of Foundation declares.
    @Test
    func declaredTypeNamesListFoundationClassesProtocolsAndStructs() async throws {
        let declaredNames = try await Self.foundationSource().declaredTypeNames()
        let machO = try Self.foundationImage()
        let interfaceIndexer = ObjCInterfaceIndexer(machO: machO, imagePath: machO.imagePath)
        try await interfaceIndexer.prepare()
        let indexedNames = interfaceIndexer.classNames + interfaceIndexer.protocolNames + interfaceIndexer.structNames + interfaceIndexer.unionNames
        #expect(Set(declaredNames) == Set(indexedNames))
        #expect(declaredNames.contains("NSError"))
        #expect(!interfaceIndexer.protocolNames.isEmpty)
        #expect(!interfaceIndexer.structNames.isEmpty)
    }

    /// A private class no SDK file mentions resolves to Foundation through the
    /// runtime-metadata layer. The name is taken from the image itself, so the
    /// test does not hang on one OS version's private classes.
    @Test
    func typeDatabaseAttributesPrivateClassThroughObjCDeclaredTypeNames() async throws {
        guard #available(macOS 13.0, *) else { return }
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
