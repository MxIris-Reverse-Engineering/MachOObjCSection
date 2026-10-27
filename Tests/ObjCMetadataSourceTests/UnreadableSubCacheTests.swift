import Testing
import Foundation
@_spi(Support) import MachOKit
import MachOKitExtensions
@testable import MachOObjCSection

/// An image of the running system's dyld cache whose header lies in a
/// sub-cache file, and a different sub-cache file that looking the image up
/// passes on its way there. `nil` when the cache has no such pair, which gates
/// the suite off.
private struct IncompleteCacheProbe: Sendable {
    /// The main file of the cache.
    let cacheURL: URL
    /// The sub-cache file the test leaves out: neither the image's nor the
    /// one holding the Objective-C header optimization, but listed before the
    /// image's.
    let omittedFileName: String
    /// The image's Objective-C image index.
    let objcImageIndex: Int
    /// The image's path, read with every file of the cache present.
    let imagePath: String

    static let system: IncompleteCacheProbe? = try? make()

    private static func make() throws -> IncompleteCacheProbe? {
        guard let cacheURL = DyldCache.host?.url else { return nil }
        let cache = try DyldCache(url: cacheURL)
        guard let headerOptimization = cache._headerOptimizationRO64,
              let headerInfos = headerOptimization.value.headerInfos(in: headerOptimization.cache),
              let subCacheEntries = cache.subCaches else {
            return nil
        }
        let subCacheFileNames = subCacheEntries.map { cacheURL.lastPathComponent + $0.fileSuffix }

        // The later the image's file, the more files the lookup passes on its
        // way there, any of which it could fail to open.
        for headerInfo in Array(headerInfos).reversed().prefix(32) {
            guard let located = cache._machO(at: headerInfo.index),
                  let imageFileIndex = subCacheFileNames.firstIndex(of: located.cache.url.lastPathComponent) else {
                continue
            }
            let neededFileNames: Set<String> = [
                located.cache.url.lastPathComponent,
                headerOptimization.cache.url.lastPathComponent,
            ]
            guard let omittedFileName = subCacheFileNames[..<imageFileIndex].first(where: { !neededFileNames.contains($0) }) else {
                continue
            }
            return IncompleteCacheProbe(
                cacheURL: cacheURL,
                omittedFileName: omittedFileName,
                objcImageIndex: headerInfo.index,
                imagePath: located.value.imagePath
            )
        }
        return nil
    }
}

/// A cache copied without one of its files — or one whose file cannot be read
/// — still holds every image the other files do. MachOKit's `locateValue`
/// gives up on the whole lookup at the first sub-cache file it cannot open.
@Suite(
    "Lookups past a sub-cache file that cannot be opened",
    .enabled(if: IncompleteCacheProbe.system != nil)
)
struct UnreadableSubCacheTests {
    /// A fresh directory of symbolic links to every file of the cache but
    /// `omittedFileName`.
    private static func linkCacheFiles(of cacheURL: URL, omitting omittedFileName: String) throws -> URL {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("IncompleteDyldCache-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let cacheDirectory = cacheURL.deletingLastPathComponent()
        let cacheFileName = cacheURL.lastPathComponent
        for fileName in try fileManager.contentsOfDirectory(atPath: cacheDirectory.path)
        where fileName.hasPrefix(cacheFileName) && fileName != omittedFileName {
            try fileManager.createSymbolicLink(
                at: directory.appendingPathComponent(fileName),
                withDestinationURL: cacheDirectory.appendingPathComponent(fileName)
            )
        }
        return directory
    }

    @Test("An image is found past a sub-cache file that cannot be opened")
    func findsImagePastUnreadableSubCache() throws {
        let probe = try #require(IncompleteCacheProbe.system)
        let directory = try Self.linkCacheFiles(of: probe.cacheURL, omitting: probe.omittedFileName)
        defer { try? FileManager.default.removeItem(at: directory) }

        let incompleteCache = try DyldCache(url: directory.appendingPathComponent(probe.cacheURL.lastPathComponent))

        #expect(incompleteCache._machO(at: probe.objcImageIndex)?.value.imagePath == probe.imagePath)
    }
}
