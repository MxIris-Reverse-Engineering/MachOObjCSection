import Foundation
import Testing

/// What `ObjCCodeReferences` may and may not spell, checked on its source.
/// It reads image memory only through MachOKitExtensions'
/// `CrossReferenceMemory`, so that an image set made from files never reads
/// the process's memory; and it is the Objective-C layer, so it names no
/// Swift runtime function — those belong to MachOSwiftSection's Swift layer.
@Suite
struct SourceScanTests {
    @Test func objectiveCLayerReadsMemoryOnlyThroughCrossReferenceMemory() throws {
        var offendingLines: [String] = []
        for fileURL in try Self.moduleSourceFiles() {
            for (lineNumber, line) in try Self.lines(of: fileURL) {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), Self.turnsAnAddressIntoAPointer(code) else { continue }
                offendingLines.append("\(fileURL.lastPathComponent):\(lineNumber): \(code)")
            }
        }
        #expect(offendingLines.isEmpty, "read through `CrossReferenceMemory`:\n\(offendingLines.joined(separator: "\n"))")
    }

    @Test func objectiveCLayerSpellsNoSwiftRuntimeName() throws {
        var offendingLines: [String] = []
        for fileURL in try Self.moduleSourceFiles() {
            for (lineNumber, line) in try Self.lines(of: fileURL) where Self.spellsASwiftRuntimeName(line) {
                offendingLines.append("\(fileURL.lastPathComponent):\(lineNumber): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(offendingLines.isEmpty, "the Swift runtime's names belong to the Swift layer:\n\(offendingLines.joined(separator: "\n"))")
    }

    /// The scans must see what they look for, and nothing else — their
    /// silence proves nothing otherwise.
    @Test func theScansDiscriminate() {
        #expect(Self.turnsAnAddressIntoAPointer("guard let slot = UnsafeRawPointer(bitPattern: address) else {"))
        #expect(Self.turnsAnAddressIntoAPointer("let name = UnsafePointer<CChar>(bitPattern: string)"))
        #expect(!Self.turnsAnAddressIntoAPointer("let key = UInt(bitPattern: pointer)"))
        #expect(!Self.turnsAnAddressIntoAPointer("let raw = UnsafeRawPointer(bytes + index)"))

        #expect(Self.spellsASwiftRuntimeName(#"strncmp(name, "_swift_getTypeByMangledNameIn", 29)"#))
        #expect(!Self.spellsASwiftRuntimeName(#"if strcmp(name, "_objc_msgSend") == 0 {"#))
        #expect(!Self.spellsASwiftRuntimeName("/// `swift_retain` is the Swift layer's"))
    }

    private static let pointerFromAddress = try! NSRegularExpression(pattern: #"Unsafe(Mutable)?(Raw)?Pointer(<[^>]*>)?\(bitPattern:"#)

    static func turnsAnAddressIntoAPointer(_ code: String) -> Bool {
        pointerFromAddress.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) != nil
    }

    private static let swiftRuntimeLiteral = try! NSRegularExpression(pattern: #""[^"]*swift_[^"]*""#)

    static func spellsASwiftRuntimeName(_ line: String) -> Bool {
        let code = line.trimmingCharacters(in: .whitespaces)
        guard !code.hasPrefix("//") else { return false }
        return swiftRuntimeLiteral.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) != nil
    }

    private static func lines(of fileURL: URL) throws -> [(Int, String)] {
        try String(contentsOf: fileURL, encoding: .utf8).components(separatedBy: .newlines).enumerated().map { ($0.offset + 1, $0.element) }
    }

    /// Every Swift file of `Sources/ObjCCodeReferences`.
    private static func moduleSourceFiles() throws -> [URL] {
        let moduleDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ObjCCodeReferencesTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("Sources/ObjCCodeReferences")
        let enumerator = try #require(FileManager.default.enumerator(at: moduleDirectory, includingPropertiesForKeys: nil))
        var files: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            files.append(fileURL)
        }
        #expect(files.count >= 5, "found only \(files.count) sources under \(moduleDirectory.path)")
        return files
    }
}
