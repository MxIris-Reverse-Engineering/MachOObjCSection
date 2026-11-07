import Testing
import Foundation
@testable import MachOKit
@testable import MachOObjCSection

/// The image a dyld cache address lies in, looked up in a table built once
/// per cache instead of walking the cache's images for every pointer —
/// about four thousand images on macOS 27, walked once for every protocol,
/// class and category pointer read out of the cache.
///
/// Every answer must be the walk's: the first image, in the walk's order, one
/// of whose segments contains the address, including where segments of
/// several images overlap.
@Suite("Images of a dyld cache by address")
struct CacheImageAddressTableTests {
    /// Overlapping, nested, identical and adjacent ranges, against the walk
    /// at every boundary, next to it and at seeded random addresses.
    @Test func answersLikeTheWalkWhereRangesOverlap() {
        let rangesByImage: [[Range<UInt64>]] = [
            [100 ..< 200, 1000 ..< 2000],
            [150 ..< 250],
            [1000 ..< 2000],
            [200 ..< 300, 300 ..< 400],
            [50 ..< 60, 60 ..< 70],
            [],
            [1500 ..< 1600, 5000 ..< 5000],
            [0 ..< 10],
        ]
        let table = CacheImageAddressTable(images: Array(rangesByImage.indices)) { rangesByImage[$0] }

        var addresses: Set<UInt64> = []
        for ranges in rangesByImage {
            for range in ranges {
                for boundary in [range.lowerBound, range.upperBound] {
                    addresses.insert(boundary)
                    addresses.insert(boundary &+ 1)
                    if boundary > 0 { addresses.insert(boundary - 1) }
                }
            }
        }
        var generator = SeededGenerator(seed: 0x5EED)
        for _ in 0 ..< 2000 {
            addresses.insert(UInt64.random(in: 0 ..< 6000, using: &generator))
        }

        for address in addresses.sorted() {
            let walked = rangesByImage.indices.first { rangesByImage[$0].contains { $0.contains(address) } }
            #expect(table.image(containing: address) == walked, "address \(address)")
        }
    }

    @Test func answersNothingForAnEmptyCache() {
        let table = CacheImageAddressTable(images: [Int]()) { _ in [] }
        #expect(table.image(containing: 0) == nil)
        #expect(table.image(containing: .max) == nil)
    }

    /// The system's cache read from disk, asked through the cache an image
    /// reads through — the file holding Foundation's header, as the
    /// Objective-C readers ask it: for segment boundaries of a sample of the
    /// file's images, the lookup names the image the walk over
    /// `machOFiles()` — the images whose headers that file holds — names.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: Self.systemCachePath)))
    func fileLookupAnswersLikeTheWalk() throws {
        let fullCache = try FullDyldCache(url: URL(fileURLWithPath: Self.systemCachePath))
        let foundation = try #require(fullCache.machOFile(by: .name("Foundation")))
        let cache = try #require(foundation.cache)
        let images = Array(cache.machOFiles())
        try #require(images.count > 10)
        let rangesByImage = images.map { image in
            image.is64Bit ? image.segments64.compactMap(\.virtualMemoryRange) : image.segments32.compactMap(\.virtualMemoryRange)
        }

        for address in Self.sampleAddresses(rangesByImage: rangesByImage) {
            let walkedIndex = rangesByImage.indices.first { rangesByImage[$0].contains { $0.contains(address) } }
            let answer = cache.machO(containing: address)
            #expect(answer.map { Self.identity(of: $0) } == walkedIndex.map { Self.identity(of: images[$0]) }, "address \(String(address, radix: 16))")
        }
    }

    /// The shared cache loaded into this process, unslid addresses and
    /// pointers alike.
    @Test func loadedLookupAnswersLikeTheWalk() throws {
        let cache = try #require(DyldCacheLoaded.current)
        let images = Array(cache.machOImages())
        try #require(images.count > 100)
        let rangesByImage = images.map { image in
            image.is64Bit ? image.segments64.compactMap(\.virtualMemoryRange) : image.segments32.compactMap(\.virtualMemoryRange)
        }

        for address in Self.sampleAddresses(rangesByImage: rangesByImage) {
            let walkedImage = images.first { $0.contains(unslidAddress: address) }
            #expect(cache.machO(containing: address)?.ptr == walkedImage?.ptr, "unslid address \(String(address, radix: 16))")

            let slide = images.first?.vmaddrSlide ?? 0
            guard let pointer = UnsafeRawPointer(bitPattern: UInt(address) &+ UInt(bitPattern: slide)) else { continue }
            let walkedPointerImage = images.first { $0.contains(ptr: pointer) }
            #expect(cache.machO(containing: pointer)?.ptr == walkedPointerImage?.ptr, "pointer \(pointer)")
        }
    }

    private static let systemCachePath = "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e"

    /// An image of a cache by where its header is.
    private static func identity(of image: MachOFile) -> String {
        "\(image.url.path):\(image.headerStartOffsetInCache)"
    }

    /// Boundaries of the segments of about 12 images spread over the cache,
    /// the middle of each segment and the addresses just inside and just past
    /// its ends — the shared `__LINKEDIT` among them.
    private static func sampleAddresses(rangesByImage: [[Range<UInt64>]]) -> [UInt64] {
        var addresses: Set<UInt64> = []
        for imageIndex in stride(from: 0, to: rangesByImage.count, by: max(rangesByImage.count / 12, 1)) {
            for range in rangesByImage[imageIndex] {
                addresses.insert(range.lowerBound)
                addresses.insert(range.lowerBound &+ (range.upperBound - range.lowerBound) / 2)
                addresses.insert(range.upperBound - 1)
                addresses.insert(range.upperBound)
                if range.lowerBound > 0 { addresses.insert(range.lowerBound - 1) }
            }
        }
        return addresses.sorted()
    }
}

/// A deterministic generator, so a failing address can be reproduced.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
