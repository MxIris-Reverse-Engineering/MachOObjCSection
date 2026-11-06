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

    /// The cache's Objective-C header infos by index, read once: the header
    /// optimization lives in one of the cache's files, and finding it walks
    /// them all.
    struct ObjCHeaderInfos {
        let headerOptimizationRO64: DyldCache.LocatedValue<ObjCHeaderOptimizationRO64>?
        let headerInfos64ByIndex: [Int: ObjCHeaderInfoRO64]
        let headerOptimizationRO32: DyldCache.LocatedValue<ObjCHeaderOptimizationRO32>?
        let headerInfos32ByIndex: [Int: ObjCHeaderInfoRO32]
    }

    private let lock = NSLock()
    private var addressTable: CacheImageAddressTable<MachOFile>?
    private var objcHeaderInfos: ObjCHeaderInfos?
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

    /// The cache's Objective-C header infos, read the first time they are
    /// asked for. The first header listed under an index answers for it, as
    /// the search over the list did.
    func objcHeaderInfos(of cache: DyldCache) -> ObjCHeaderInfos {
        if let objcHeaderInfos = lock.withLock({ objcHeaderInfos }) {
            return objcHeaderInfos
        }
        let headerOptimizationRO64 = cache._headerOptimizationRO64
        let headerOptimizationRO32 = cache._headerOptimizationRO32
        let builtHeaderInfos = ObjCHeaderInfos(
            headerOptimizationRO64: headerOptimizationRO64,
            headerInfos64ByIndex: Self.headerInfosByIndex(headerOptimizationRO64.flatMap { $0.value.headerInfos(in: $0.cache) }),
            headerOptimizationRO32: headerOptimizationRO32,
            headerInfos32ByIndex: Self.headerInfosByIndex(headerOptimizationRO32.flatMap { $0.value.headerInfos(in: $0.cache) })
        )
        return lock.withLock {
            if let objcHeaderInfos {
                return objcHeaderInfos
            }
            objcHeaderInfos = builtHeaderInfos
            return builtHeaderInfos
        }
    }

    private static func headerInfosByIndex<HeaderInfo: ObjCHeaderInfoROProtocol>(
        _ headerInfos: AnyRandomAccessCollection<HeaderInfo>?
    ) -> [Int: HeaderInfo] {
        guard let headerInfos else { return [:] }
        var headerInfosByIndex: [Int: HeaderInfo] = [:]
        for headerInfo in headerInfos where headerInfosByIndex[headerInfo.index] == nil {
            headerInfosByIndex[headerInfo.index] = headerInfo
        }
        return headerInfosByIndex
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
