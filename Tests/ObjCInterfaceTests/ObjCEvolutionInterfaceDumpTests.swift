import Foundation
import MachOKit
import ObjCDiffing
import ObjCIndexing
import ObjCInterface
import Testing

/// The merged header of AppKit's image group — AppKit, UIFoundation,
/// CollectionViewCore and CoreAutoLayout — across every archived macOS
/// cache, written to `~/Documents/SwiftInterfaceTests` for a maintainer to
/// read. Ported from MachOSwiftSection's
/// `ObjCEvolutionInterfaceTestSuite.AppKitImageGroupArchivedDyldCacheTests`:
/// the same axis, labels, images and availability macros.
///
/// The one thing it cannot do is supply the Swift classes an image keeps no
/// class object for (`ObjCSuppliedClass`): finding them takes Swift
/// metadata, which MachOSwiftSection reads. Its header therefore lacks the
/// generic Swift classes MachOSwiftSection's lists, and its file name ends
/// in `-MachOObjCSection` so it never overwrites that one.
///
/// Like the original it asserts nothing. Indexing about two hundred images
/// takes minutes, so it runs only with `MACHO_OBJC_SECTION_DUMP=1`.
@Suite(
    "Merged header of AppKit's image group over every archived macOS cache",
    .enabled(if: ProcessInfo.processInfo.environment["MACHO_OBJC_SECTION_DUMP"] == "1")
)
struct ObjCEvolutionInterfaceDumpTests {
    /// The cache directories under `/Volumes/DyldSharedCaches/macOS`, oldest
    /// first. A directory without a cache is skipped.
    private static let cacheVersions = [
        "11.0.1", "11.1", "11.2", "11.3", "11.4", "11.5", "11.6", "11.7",
        "12.0.1", "12.1", "12.2", "12.3", "12.4", "12.5", "12.6", "12.7",
        "13.0", "13.1", "13.2", "13.3", "13.4", "13.5", "13.6", "13.7",
        "14.0", "14.1", "14.2", "14.3", "14.4", "14.5", "14.6", "14.7", "14.8",
        "15.0", "15.1", "15.2", "15.3", "15.4", "15.5", "15.6", "15.7", "15.8",
        "26.0", "26.1", "26.2", "26.3", "26.4", "26.5", "26.6", "26.7",
        "27.0",
    ]

    /// There is no macOS 11.0 or 12.0 cache, only 11.0.1 and 12.0.1; the axis
    /// labels them with the versions an SDK's availability macros name.
    private static let versionLabelsByCacheVersion = ["11.0.1": "11.0", "12.0.1": "12.0"]

    /// The images of one version, the primary image first.
    private static let imageNames = ["AppKit", "UIFoundation", "CollectionViewCore", "CoreAutoLayout"]

    @Test("Write the merged header of AppKit's image group")
    func writeAppKitImageGroupHeader() async throws {
        var builder = ObjCEvolutionInterfaceBuilder()
        var newestGroup: [(imageName: String, machO: MachOFile)] = []
        for cacheVersion in Self.cacheVersions {
            let cachePath = "/Volumes/DyldSharedCaches/macOS/\(cacheVersion)/dyld_shared_cache_arm64e"
            guard FileManager.default.fileExists(atPath: cachePath) else { continue }
            let cache = try DyldCache(url: URL(fileURLWithPath: cachePath))
            // An image joins its version's group where the cache holds it
            // with Objective-C metadata; a version without the primary image
            // is off the axis.
            let group = Self.imageNames.compactMap { imageName -> (imageName: String, machO: MachOFile)? in
                guard let machO = cache.machOFile(by: .name(imageName)),
                      machO.sections.contains(where: { $0.sectionName.hasPrefix("__objc_") }) else {
                    return nil
                }
                return (imageName, machO)
            }
            guard group.first?.imageName == Self.imageNames.first else { continue }

            var images: [ObjCEvolutionInterfaceImage<MachOFile>] = []
            for image in group {
                let indexer = ObjCInterfaceIndexer(machO: image.machO, imagePath: image.machO.imagePath)
                try await indexer.prepare()
                images.append(ObjCEvolutionInterfaceImage(imageName: image.imageName, indexer: indexer, machO: image.machO))
            }
            let label = Self.versionLabelsByCacheVersion[cacheVersion] ?? cacheVersion
            builder.addVersion(images: images, version: ObjCAPIVersionDescriptor(label: label))
            newestGroup = group
        }

        let merged = try builder.build(availabilityPlatform: "macos")
        let header = merged.interface.string + "\n\n// API-breaking on this axis: \(merged.evolution.hasBreakingChange)"

        // Named as MachOSwiftSection names it — the primary image's platform
        // and SDK, then the group — with this package's suffix.
        let primaryImage = try #require(newestGroup.first)
        let buildVersion = try #require(primaryImage.machO.loadCommands.info(of: LoadCommand.buildVersion))
        let groupName = newestGroup.map(\.imageName).joined(separator: "+")
        let outputDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwiftInterfaceTests")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputFile = outputDirectory.appendingPathComponent("macOS-\(buildVersion.sdk)-\(groupName)-ObjCEvolutionInterface-MachOObjCSection.h")
        try header.write(to: outputFile, atomically: true, encoding: .utf8)
        print("Wrote \(outputFile.path)")
    }
}
