//
//  DyldCacheImageLookup.swift
//  MachOObjCSection
//

import Foundation
@_spi(Support) import MachOKit

/// What one opening of a dyld cache file answers about its images, each
/// answer worked out once: the image an address lies in, and the image an
/// Objective-C header index names.
///
/// It hangs off the opening's file handle identity, which every `DyldCache`
/// MachOKit assembles for the file shares, and goes away with it.
final class DyldCacheImageLookup: @unchecked Sendable {
    private static let lookups = OwnerAttachedValues<any FileHandleIdentity & AnyObject, DyldCacheImageLookup>()

    private let lock = NSLock()
    private var addressTable: CacheImageAddressTable<MachOFile>?
    private var locatedImagesByHeaderIndex: [Int: DyldCache.LocatedValue<MachOFile>?] = [:]

    private init() {}

    static func lookup(for cache: DyldCache) -> DyldCacheImageLookup {
        lookups.value(for: cache.fileHandleIdentity) { DyldCacheImageLookup() }
    }

    /// The first of `cache.machOFiles()` one of whose segments contains
    /// `unslidAddress`.
    func machO(containing unslidAddress: UInt64, in cache: DyldCache) -> MachOFile? {
        addressTable(of: cache).image(containing: unslidAddress)
    }

    /// The image the Objective-C header at `index` names, as `locate` finds
    /// it the first time it is asked for. Built outside the lock — locating
    /// opens sub-cache files — and the first finished answer is kept.
    func locatedImage(
        atHeaderIndex index: Int,
        locating locate: () -> DyldCache.LocatedValue<MachOFile>?
    ) -> DyldCache.LocatedValue<MachOFile>? {
        if case let .some(locatedImage) = lock.withLock({ locatedImagesByHeaderIndex[index] }) {
            return locatedImage
        }
        let locatedImage = locate()
        return lock.withLock {
            if case let .some(winner) = locatedImagesByHeaderIndex[index] {
                return winner
            }
            locatedImagesByHeaderIndex[index] = .some(locatedImage)
            return locatedImage
        }
    }

    private func addressTable(of cache: DyldCache) -> CacheImageAddressTable<MachOFile> {
        if let addressTable = lock.withLock({ addressTable }) {
            return addressTable
        }
        let builtTable = CacheImageAddressTable(images: cache.machOFiles()) { machO in
            machO.is64Bit
                ? machO.segments64.compactMap(\.virtualMemoryRange)
                : machO.segments32.compactMap(\.virtualMemoryRange)
        }
        return lock.withLock {
            if let addressTable {
                return addressTable
            }
            addressTable = builtTable
            return builtTable
        }
    }
}
