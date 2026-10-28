import Foundation
import MachOKit
import ObjCDiffing
import ObjCIndexing
import Testing
@testable import ObjCInterface

/// AppKit merged across three archived macOS caches, one per relative method
/// list layout (`DyldCacheRelativeMethodNameTests` explains the three). The
/// caches are several gigabytes each and live on an archive volume, so the
/// suite skips where one is absent.
@Suite(
    "Evolution interface over archived macOS caches",
    .enabled(if: ArchivedMacOSCache.areAllPresent)
)
struct ObjCEvolutionInterfaceArchivedCacheTests {
    /// Indexing AppKit three times takes a while, so the suite builds the
    /// merged header once, one version at a time, the way a host does.
    actor Fixture {
        static let shared = Fixture()

        private var merged: ObjCEvolutionInterface?

        func load() async throws -> ObjCEvolutionInterface {
            if let merged { return merged }
            var builder = ObjCEvolutionInterfaceBuilder()
            for version in ArchivedMacOSCache.versions {
                let image = try ArchivedMacOSCache.image(named: "AppKit", version: version)
                let indexer = ObjCInterfaceIndexer(machO: image, imagePath: image.imagePath)
                try await indexer.prepare()
                builder.addVersion(indexer: indexer, machO: image, version: ObjCAPIVersionDescriptor(label: version))
            }
            let merged = try builder.build(availabilityPlatform: "macos")
            self.merged = merged
            return merged
        }
    }

    private static func lines() async throws -> [String] {
        try await Fixture.shared.load().interface.string.components(separatedBy: "\n")
    }

    /// Every presence bitmap three versions can have, as an annotation opens.
    private static let annotationOpenings: [String] = ["●", "○"].flatMap { first in
        ["●", "○"].flatMap { second in
            ["●", "○"].map { third in "// [\(first)\(second)\(third)]" }
        }
    }

    @Test("A class the SDK introduces in macOS 13 reads as added in 13.0, with the SDK's own macro")
    func classIntroducedInMacOS13() async throws {
        let lines = try await Self.lines()
        // AppKit's NSComboButton.h: `API_AVAILABLE(macos(13.0)) @interface NSComboButton : NSControl`.
        let firstLineIndex = try #require(lines.firstIndex { $0.hasPrefix("@interface NSComboButton : NSControl") })
        #expect(lines[firstLineIndex].hasSuffix("// [○○●] added in 13.0"))
        #expect(lines[firstLineIndex - 1] == "API_AVAILABLE(macos(13.0))")
    }

    @Test("Every lineage that changed has exactly one annotation")
    func everyChangedLineageHasOneAnnotation() async throws {
        let merged = try await Fixture.shared.load()
        let changedLineageCount = merged.evolution.allContainerLineages.reduce(0) { count, containerLineage in
            count + (containerLineage.events.isEmpty ? 0 : 1) + containerLineage.memberLineages.count
        }
        try #require(changedLineageCount > 0)

        let annotationCount = try await Self.lines().filter { line in
            Self.annotationOpenings.contains { line.contains($0) }
        }.count
        #expect(annotationCount == changedLineageCount)
    }

    @Test("A removed declaration keeps its line, and only a whole lifecycle gets a macro")
    func removedDeclarationsStay() async throws {
        let lines = try await Self.lines()
        let removedLines = lines.filter { $0.hasSuffix("// [●●○] removed in 13.0") }
        #expect(!removedLines.isEmpty)
        // Present from the start of the axis, so the introduction is unknown
        // and no macro can be written.
        #expect(removedLines.allSatisfy { !$0.contains("API_OBSOLETED") && !$0.contains("API_AVAILABLE") })

        // Added in 12.0.1 and gone in 13.0: one lifecycle API_OBSOLETED states,
        // before a member's semicolon or on the line above a container's.
        let obsoletedMacro = "API_OBSOLETED(\"Removed\", macos(12.0.1, 13.0, 13.0))"
        for (lineIndex, line) in lines.enumerated() where line.hasSuffix("// [○●○] added in 12.0.1 · removed in 13.0") {
            if line.hasPrefix("@interface ") || line.hasPrefix("@protocol ") {
                #expect(lines[lineIndex - 1] == obsoletedMacro)
            } else if line.hasPrefix("- (") || line.hasPrefix("+ (") || line.hasPrefix("@property ") {
                #expect(line.contains(obsoletedMacro + ";"))
            }
        }
    }
}

/// The archive `ArchivedMacOSCache` in `ObjCMetadataSourceTests` reads,
/// which this target cannot see, narrowed to the versions this suite merges.
private enum ArchivedMacOSCache {
    static let versions = ["11.0.1", "12.0.1", "13.0"]

    static var areAllPresent: Bool {
        versions.allSatisfy { FileManager.default.fileExists(atPath: path(version: $0)) }
    }

    static func path(version: String) -> String {
        "/Volumes/DyldSharedCaches/macOS/\(version)/dyld_shared_cache_arm64e"
    }

    static func image(named imageName: String, version: String) throws -> MachOFile {
        let cache = try DyldCache(url: URL(fileURLWithPath: path(version: version)))
        return try #require(cache.machOFile(by: .name(imageName)), "no \(imageName) image in the macOS \(version) cache")
    }
}
