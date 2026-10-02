import Testing
import Foundation
import MachOKit
import ObjCDeclarationRendering
import ObjCIndexing
@testable import ObjCInterface

/// `stripProtocolConformance` drops every member a class's adopted protocols
/// declare — required and optional, along the whole protocol inheritance
/// chain — and keeps the `<Protocol, …>` list, the way a hand-written header
/// reads (evolution proposal 0012).
///
/// The fixture is a dylib compiled on the fly: a class adopting a protocol
/// that inherits another, which inherits `NSObject`, with required and
/// optional members at each level. Before the fix only the required members
/// of the directly adopted protocol were dropped.
@Suite("stripProtocolConformance", .serialized)
struct StripProtocolConformanceTests {
    private static let fixtureSource = """
    #import <Foundation/Foundation.h>

    @protocol StripFixtureBaseProtocol <NSObject>
    - (void)baseRequiredMethod;
    @optional
    - (void)baseOptionalMethod;
    @end

    @protocol StripFixtureDerivedProtocol <StripFixtureBaseProtocol>
    @property (nonatomic, readonly) NSInteger derivedRequiredProperty;
    - (void)derivedRequiredMethod;
    @optional
    @property (nonatomic, readonly) NSInteger derivedOptionalProperty;
    - (void)derivedOptionalMethod;
    + (void)derivedOptionalClassMethod;
    @end

    // Redeclares a member of its grandparent, which the derived protocol's
    // own lists do not carry.
    @protocol StripFixtureRedeclaringProtocol <StripFixtureDerivedProtocol>
    - (void)baseRequiredMethod;
    - (void)redeclaringOwnMethod;
    @end

    @interface StripFixtureConformingObject : NSObject <StripFixtureDerivedProtocol>
    @property (nonatomic) NSInteger ownProperty;
    - (void)ownMethod;
    @end

    @implementation StripFixtureConformingObject
    @synthesize derivedRequiredProperty = _derivedRequiredProperty;
    @synthesize derivedOptionalProperty = _derivedOptionalProperty;
    - (void)baseRequiredMethod {}
    - (void)baseOptionalMethod {}
    - (void)derivedRequiredMethod {}
    - (void)derivedOptionalMethod {}
    + (void)derivedOptionalClassMethod {}
    - (void)ownMethod {}
    @end

    // A protocol no class adopts is emitted only when referenced.
    Protocol *StripFixtureRedeclaringProtocolReference(void) {
        return @protocol(StripFixtureRedeclaringProtocol);
    }
    """

    private enum WorkingDirectoryCleanup {
        nonisolated(unsafe) static var directories: [URL] = []
        static let registration: Void = {
            atexit {
                for directory in WorkingDirectoryCleanup.directories {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
        }()
    }

    private struct FixtureCompilationError: Swift.Error, CustomStringConvertible {
        let diagnostics: String
        var description: String { "strip fixture compilation failed:\n\(diagnostics)" }
    }

    /// Compiled once per process.
    private static let fixtureCompilationResult: Result<URL, Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("StripProtocolConformanceFixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = WorkingDirectoryCleanup.registration
            WorkingDirectoryCleanup.directories.append(workingDirectory)

            let sourceURL = workingDirectory.appendingPathComponent("Fixture.m")
            let libraryURL = workingDirectory.appendingPathComponent("libStripFixture.dylib")
            try fixtureSource.write(to: sourceURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["clang", "-dynamiclib", "-fobjc-arc", "-framework", "Foundation", sourceURL.path, "-o", libraryURL.path]
            let standardErrorPipe = Pipe()
            process.standardError = standardErrorPipe
            try process.run()
            // Drain BEFORE waitUntilExit, or a long diagnostic deadlocks both sides.
            let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw FixtureCompilationError(diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
            }
            return libraryURL
        }
    }()

    private static func makeBuilder() async throws -> ObjCInterfaceBuilder<MachOFile> {
        let libraryURL = try fixtureCompilationResult.get()
        let machOFile: MachOFile
        switch try MachOKit.loadFromFile(url: libraryURL) {
        case .machO(let thinFile):
            machOFile = thinFile
        case .fat(let fatFile):
            machOFile = try #require(try fatFile.machOFiles().first, "fixture has no slice")
        }
        let indexer = ObjCInterfaceIndexer(machO: machOFile, imagePath: libraryURL.path)
        try await indexer.prepare()
        return ObjCInterfaceBuilder(indexer: indexer, machO: machOFile)
    }

    private static var strippingOptions: ObjCGenerationOptions {
        var options = ObjCGenerationOptions.default
        options.stripProtocolConformance = true
        return options
    }

    /// Whether `rendered` declares a property or a method named `name`.
    private func declaresMember(named name: String, in rendered: String) -> Bool {
        rendered.split(separator: "\n").contains { line in
            let declaration = line.trimmingCharacters(in: .whitespaces)
            if declaration.hasPrefix("@property ") {
                return declaration.hasSuffix(" \(name);") || declaration.hasSuffix("*\(name);")
            }
            guard declaration.hasPrefix("- ") || declaration.hasPrefix("+ "),
                  let returnTypeEnd = declaration.firstIndex(of: ")") else { return false }
            let selectorPart = declaration[declaration.index(after: returnTypeEnd)...]
            return selectorPart == "\(name);" || selectorPart.hasPrefix("\(name):")
        }
    }

    /// Every member a protocol of the chain declares: required and optional,
    /// instance and class, the derived protocol's and its ancestors' —
    /// `NSObject` included.
    private static let protocolDeclaredMemberNames = [
        "derivedRequiredProperty", "derivedRequiredMethod",
        "derivedOptionalProperty", "derivedOptionalMethod", "derivedOptionalClassMethod",
        "baseRequiredMethod", "baseOptionalMethod",
        "hash", "superclass", "description", "debugDescription",
    ]

    @Test("A class declaration drops every member its protocol chain declares")
    func classDeclarationDropsEveryProtocolMember() async throws {
        let builder = try await Self.makeBuilder()
        let plain = try #require(builder.classInterface(named: "StripFixtureConformingObject")).string
        let stripped = try #require(builder.classInterface(named: "StripFixtureConformingObject", options: Self.strippingOptions)).string

        // The premise: each member is there to strip.
        let missingFromPlain = Self.protocolDeclaredMemberNames.filter { !declaresMember(named: $0, in: plain) }
        try #require(missingFromPlain.isEmpty, "the unstripped class lacks \(missingFromPlain)\n\(plain)")

        let survivors = Self.protocolDeclaredMemberNames.filter { declaresMember(named: $0, in: stripped) }
        #expect(survivors.isEmpty, "members the protocols declare survived: \(survivors)\n\(stripped)")
        for ownMemberName in ["ownProperty", "ownMethod", "setOwnProperty"] {
            #expect(declaresMember(named: ownMemberName, in: stripped), "the class's own \(ownMemberName) must stay\n\(stripped)")
        }
    }

    /// The list stays: a hand-written header names the protocols it adopts.
    @Test("A class declaration keeps its conformance list")
    func classDeclarationKeepsTheConformanceList() async throws {
        let builder = try await Self.makeBuilder()
        let stripped = try #require(builder.classInterface(named: "StripFixtureConformingObject", options: Self.strippingOptions)).string
        #expect(stripped.hasPrefix("@interface StripFixtureConformingObject : NSObject <StripFixtureDerivedProtocol>"), "\(stripped)")
    }

    /// A protocol drops what any ancestor declares — the grandparent's
    /// member included — and keeps its own.
    @Test("A protocol declaration drops members redeclared from any ancestor")
    func protocolDeclarationDropsMembersRedeclaredFromAnyAncestor() async throws {
        let builder = try await Self.makeBuilder()
        let plain = try #require(builder.protocolInterface(named: "StripFixtureRedeclaringProtocol")).string
        let stripped = try #require(builder.protocolInterface(named: "StripFixtureRedeclaringProtocol", options: Self.strippingOptions)).string

        try #require(declaresMember(named: "baseRequiredMethod", in: plain), "\(plain)")
        #expect(!declaresMember(named: "baseRequiredMethod", in: stripped), "\(stripped)")
        #expect(declaresMember(named: "redeclaringOwnMethod", in: stripped), "\(stripped)")
        #expect(stripped.hasPrefix("@protocol StripFixtureRedeclaringProtocol <StripFixtureDerivedProtocol>"), "\(stripped)")
    }
}
