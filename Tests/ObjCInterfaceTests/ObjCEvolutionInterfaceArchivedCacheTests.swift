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

    /// The property lines of the class whose `@interface` line starts with
    /// `interfacePrefix` that declare one of `propertyNames`, in order.
    private static func propertyLines(
        ofInterfaceStartingWith interfacePrefix: String,
        named propertyNames: [String],
        in lines: [String]
    ) throws -> [String] {
        let interfaceLineIndex = try #require(lines.firstIndex { $0.hasPrefix(interfacePrefix) })
        let endLineIndex = try #require(lines[interfaceLineIndex...].firstIndex(of: "@end"))
        return lines[interfaceLineIndex ..< endLineIndex].filter { line in
            line.hasPrefix("@property ") && propertyNames.contains { line.contains(" \($0);") || line.contains("*\($0);") }
        }
    }

    /// AppKit's NSView.h declares `@property NSRect frame;` and `bounds` alike.
    /// From macOS 13 a category the linker merges into NSView adopts
    /// `NSLayoutItem`, whose read-only `frame` and `bounds` it puts ahead of
    /// the class's own; neither declaration of NSView changed.
    @Test("A property a protocol copies ahead of the class's own declaration reads as the class declares it, unchanged")
    func ownDeclarationOutranksProtocolCopy() async throws {
        let lines = try await Self.lines()
        let geometryLines = try Self.propertyLines(ofInterfaceStartingWith: "@interface NSView : NSResponder", named: ["frame", "bounds"], in: lines)
        #expect(geometryLines == ["@property struct CGRect frame;", "@property struct CGRect bounds;"])
    }

    /// AppKit's NSLayoutConstraint.h declares NSView's anchors in a category,
    /// `@property (readonly, strong) NSLayoutXAxisAnchor *leadingAnchor
    /// API_AVAILABLE(macos(10.11))`, which leaves no property record; the
    /// getter `- leadingAnchor` is there on the whole axis. From macOS 13 the
    /// read-only copy `NSAKLayoutItem` brings is NSView's only record of it.
    @Test("A property only an adopted protocol brings names the protocol and gets no availability macro")
    func protocolBroughtPropertyNamesTheProtocol() async throws {
        let lines = try await Self.lines()
        let interfaceLineIndex = try #require(lines.firstIndex { $0.hasPrefix("@interface NSView : NSResponder") })
        let endLineIndex = try #require(lines[interfaceLineIndex...].firstIndex(of: "@end"))
        let propertyLineIndex = try #require(lines[interfaceLineIndex ..< endLineIndex].firstIndex { line in
            line.hasPrefix("@property (readonly) NSLayoutXAxisAnchor *leadingAnchor")
        })
        let propertyLine = lines[propertyLineIndex]
        #expect(!propertyLine.contains("API_AVAILABLE"))
        // An annotation past the column cap moves to the next line.
        let annotationLine = propertyLine.contains("// [") ? propertyLine : lines[propertyLineIndex + 1]
        #expect(annotationLine.hasSuffix("// [○○●] added in 13.0 via <NSAKLayoutItem>"))
    }

    /// AppKit's NSMenuItem.h declares `@property (nullable) SEL action;` and
    /// `@property NSInteger tag;`, NSWindow.h `@property (nullable, strong)
    /// __kindof NSView *contentView;`. Categories the linker merges into each
    /// class adopt protocols declaring the same properties read-only, and on
    /// every version of the axis those copies come first.
    @Test("A protocol's copy ahead of the class's own declaration on the whole axis does not replace it")
    func ownDeclarationOutranksProtocolCopyAlongTheAxis() async throws {
        let lines = try await Self.lines()
        let menuItemLines = try Self.propertyLines(ofInterfaceStartingWith: "@interface NSMenuItem : NSObject", named: ["action", "tag"], in: lines)
        #expect(menuItemLines == ["@property SEL action;", "@property long long tag;"])
        let windowLines = try Self.propertyLines(ofInterfaceStartingWith: "@interface NSWindow : NSResponder", named: ["contentView"], in: lines)
        #expect(windowLines == ["@property (strong) NSView *contentView;"])
    }
}

/// AppKit's image group across macOS 12.0.1 and 13.0, the release that moved
/// the collection view layout classes out of UIFoundation: most into AppKit,
/// the public layout building blocks into CollectionViewCore, which first
/// appears in 13.0. Alone, UIFoundation reports every one of them removed.
@Suite(
    "Evolution of AppKit's image group over archived macOS caches",
    .enabled(if: ArchivedMacOSCache.areAllPresent)
)
struct ObjCImageGroupArchivedCacheTests {
    private static let versions = ["12.0.1", "13.0"]
    private static let imageNames = ["AppKit", "UIFoundation", "CollectionViewCore"]

    /// The merged header of the group, and UIFoundation's evolution alone for
    /// comparison, built once.
    actor Fixture {
        static let shared = Fixture()

        private var loaded: (merged: ObjCEvolutionInterface, uiFoundationAlone: ObjCAPIEvolution)?

        func load() async throws -> (merged: ObjCEvolutionInterface, uiFoundationAlone: ObjCAPIEvolution) {
            if let loaded { return loaded }
            var builder = ObjCEvolutionInterfaceBuilder()
            var uiFoundationSnapshots: [ObjCAPISnapshot] = []
            for version in ObjCImageGroupArchivedCacheTests.versions {
                var images: [ObjCEvolutionInterfaceImage<MachOFile>] = []
                for imageName in ObjCImageGroupArchivedCacheTests.imageNames {
                    guard let image = try ArchivedMacOSCache.imageIfPresent(named: imageName, version: version) else { continue }
                    let indexer = ObjCInterfaceIndexer(machO: image, imagePath: image.imagePath)
                    try await indexer.prepare()
                    images.append(ObjCEvolutionInterfaceImage(imageName: imageName, indexer: indexer, machO: image))
                    if imageName == "UIFoundation" {
                        uiFoundationSnapshots.append(ObjCAPISnapshotBuilder(indexer: indexer).snapshot())
                    }
                }
                builder.addVersion(images: images, version: ObjCAPIVersionDescriptor(label: version))
            }
            let loaded = try (
                merged: builder.build(),
                uiFoundationAlone: ObjCAPIEvolutionBuilder().evolution(
                    of: uiFoundationSnapshots,
                    versions: ObjCImageGroupArchivedCacheTests.versions.map { ObjCAPIVersionDescriptor(label: $0) }
                )
            )
            self.loaded = loaded
            return loaded
        }
    }

    @Test("Each class UIFoundation loses in 13.0 to another image of the group is a move there, not a removal")
    func classesLeavingUIFoundationAreMoves() async throws {
        let (merged, uiFoundationAlone) = try await Fixture.shared.load()
        let removedFromUIFoundation = Set(uiFoundationAlone.classes.filter { lineage in
            lineage.events.contains { $0.status == .removed && $0.versionIndex == 1 }
        }.map(\.name))
        // Present on both sides, so the group has no removal for them.
        let classesStillInTheGroup = merged.evolution.classes.filter { lineage in
            removedFromUIFoundation.contains(lineage.name) && lineage.presence == [true, true]
        }
        try #require(!classesStillInTheGroup.isEmpty)
        for lineage in classesStillInTheGroup {
            #expect(lineage.imageMoves?.map(\.oldImageNames) == [["UIFoundation"]], "\(lineage.name)")
        }
    }

    @Test("NSCollectionLayoutSection moved to CollectionViewCore, NSCollectionViewFlowLayout to AppKit")
    func knownMoves() async throws {
        let classes = try await Fixture.shared.load().merged.evolution.classes
        #expect(classes.first { $0.name == "NSCollectionLayoutSection" }?.imageMoves == [
            ObjCImageMove(versionIndex: 1, oldImageNames: ["UIFoundation"], newImageNames: ["CollectionViewCore"]),
        ])
        #expect(classes.first { $0.name == "NSCollectionViewFlowLayout" }?.imageMoves == [
            ObjCImageMove(versionIndex: 1, oldImageNames: ["UIFoundation"], newImageNames: ["AppKit"]),
        ])
    }

    @Test("The merged header lists the image group and carries a move on the class that moved")
    func mergedHeaderShowsTheMove() async throws {
        let lines = try await Fixture.shared.load().merged.interface.string.components(separatedBy: "\n")
        #expect(Array(lines[2 ... 5]) == ["// Image group:", "//   [●●] AppKit", "//   [●●] UIFoundation", "//   [○●] CollectionViewCore"])
        let annotation = "// [●●] moved in 13.0: UIFoundation → CollectionViewCore"
        let firstLineIndex = try #require(lines.firstIndex { $0.hasPrefix("@interface NSCollectionLayoutSection ") })
        // An annotation past the column cap moves to the next line.
        #expect(lines[firstLineIndex].hasSuffix(annotation) || lines[firstLineIndex + 1].hasSuffix(annotation))
    }
}

/// The archive `ArchivedMacOSCache` in `ObjCMetadataSourceTests` reads,
/// which this target cannot see, narrowed to the versions these suites merge.
private enum ArchivedMacOSCache {
    static let versions = ["11.0.1", "12.0.1", "13.0"]

    static var areAllPresent: Bool {
        versions.allSatisfy { FileManager.default.fileExists(atPath: path(version: $0)) }
    }

    static func path(version: String) -> String {
        "/Volumes/DyldSharedCaches/macOS/\(version)/dyld_shared_cache_arm64e"
    }

    static func image(named imageName: String, version: String) throws -> MachOFile {
        let image = try imageIfPresent(named: imageName, version: version)
        return try #require(image, "no \(imageName) image in the macOS \(version) cache")
    }

    /// The image, or `nil` where the version's cache has none.
    static func imageIfPresent(named imageName: String, version: String) throws -> MachOFile? {
        let cache = try DyldCache(url: URL(fileURLWithPath: path(version: version)))
        return cache.machOFile(by: .name(imageName))
    }
}
