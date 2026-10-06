import Testing
import Foundation
import MachOKit
import MachOKitExtensions
@testable import MachOObjCSection

/// Two images of the running system's dyld cache whose headers sit in two
/// different sub-cache files, neither of them the main file: reading the
/// second one's header through the first one has to cross into another
/// sub-cache. `nil` when the cache has no such pair, which gates the suite off.
private struct CrossSubCacheProbe: Sendable {
    let cacheURL: URL
    let imagePath: String
    let targetAddress: UInt64

    static let system: CrossSubCacheProbe? = try? make()

    private static func make() throws -> CrossSubCacheProbe? {
        guard let cacheURL = DyldCache.host?.url else { return nil }
        let fullCache = try FullDyldCache(url: cacheURL)
        guard let imageInfos = fullCache.imageInfos else { return nil }
        var firstImage: (path: String, fileURL: URL)?
        for imageInfo in imageInfos {
            guard let imagePath = imageInfo.path(in: fullCache),
                  let (cache, _) = fullCache.cacheAndFileOffset(for: imageInfo.address),
                  cache.url != fullCache.url else {
                continue
            }
            guard let firstImage else {
                firstImage = (imagePath, cache.url)
                continue
            }
            if cache.url != firstImage.fileURL {
                return CrossSubCacheProbe(cacheURL: cacheURL, imagePath: firstImage.path, targetAddress: imageInfo.address)
            }
        }
        return nil
    }
}

/// From a dyld cache opened from its main file alone, every read that crossed
/// into another sub-cache assembled that sub-cache again, and each assembled
/// cache got a mapping of its file of its own. Indexing one image read
/// hundreds of times across files: an evolution over the archived macOS caches
/// held 250 mappings of one sub-cache file, and their page tables pushed the
/// process past 5 GB.
@Suite(
    "Reads into another sub-cache reuse one mapping",
    .enabled(if: CrossSubCacheProbe.system != nil)
)
struct DyldCacheSubCacheReadTests {
    @Test("Two reads into another sub-cache share one mapping of its file")
    func readsIntoAnotherSubCacheShareOneMapping() throws {
        let probe = try #require(CrossSubCacheProbe.system)
        let image = try #require(try DyldCache(url: probe.cacheURL).machOFile(by: .path(probe.imagePath)))

        let firstRead = try #require(image.fileHandleAndOffset(forAddress: probe.targetAddress))
        let secondRead = try #require(image.fileHandleAndOffset(forAddress: probe.targetAddress))

        #expect(firstRead.0 === secondRead.0)
    }

    /// The holder kept each owner's file in a weak-to-strong `NSMapTable`,
    /// which holds on to the value of a key that went away until it next
    /// resizes: a cache's mapping outlived the cache.
    @Test("A file held for an owner goes away with the owner")
    func heldFileGoesAwayWithItsOwner() throws {
        let holder = FileHandleHolder<NSObject, DyldCache.File>()
        weak var heldFile: DyldCache.File?
        do {
            let owner = NSObject()
            heldFile = holder.fileHandle(for: owner) {
                try! .open(url: URL(fileURLWithPath: "/usr/lib/dyld"), isWritable: false)
            }
        }

        #expect(heldFile == nil)
    }
}
