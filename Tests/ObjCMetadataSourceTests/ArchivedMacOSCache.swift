import Testing
import Foundation
import MachOKit

/// An archived macOS arm64e dyld shared cache, addressed by OS version.
///
/// The archive volume holds one directory per release. The caches are several
/// gigabytes each, far too large to vendor, so every test reading one skips
/// when its cache is absent.
enum ArchivedMacOSCache {
    static func path(version: String) -> String {
        "/Volumes/DyldSharedCaches/macOS/\(version)/dyld_shared_cache_arm64e"
    }

    static func isPresent(version: String) -> Bool {
        FileManager.default.fileExists(atPath: path(version: version))
    }

    /// The image the way the command line tools open it: the cache file, then
    /// the image looked up by name.
    static func image(named imageName: String, version: String) throws -> MachOFile {
        let cache = try DyldCache(url: URL(fileURLWithPath: path(version: version)))
        return try #require(
            cache.machOFile(by: .name(imageName)),
            "no \(imageName) image in the macOS \(version) cache"
        )
    }
}

/// One image of one archived cache.
struct ArchivedCacheImage: Sendable, CustomTestStringConvertible {
    let version: String
    let imageName: String

    var testDescription: String { "\(imageName) in macOS \(version)" }
}
