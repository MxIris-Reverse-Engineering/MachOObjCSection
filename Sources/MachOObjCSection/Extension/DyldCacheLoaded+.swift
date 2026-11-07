//
//  DyldCacheLoaded.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/11/02
//
//

import Foundation
import MachOKit
internal import MachOKitExtensions

#if !canImport(Darwin)
extension DyldCacheLoaded {
    // FIXME: fallback for linux
    public static var current: DyldCacheLoaded? {
        return nil
    }
}
#endif


extension DyldCacheLoaded {
    var relativeMethodSelectorBaseAddress: UnsafeRawPointer? {
        if let objcOptimization = objcOptimization {
            return objcOptimization.relativeMethodSelectorBaseAddress(in: self)
        } else if let objcOptimization = oldObjcOptimization {
            return objcOptimization.relativeMethodSelectorBaseAddress(in: self)
        }
        return nil
    }
}

#if canImport(Darwin)
/// Cache for MachOImage lookups by index to avoid repeated memory accesses
/// Thread-safe with lock protection for atomic check-and-set operations
private final class MachOImageCache: @unchecked Sendable {
    static let shared = MachOImageCache()

    private let cache = NSCache<NSNumber, MachOImageWrapper>()
    /// An `NSLock` rather than an `os_unfair_lock` stored in the class: Swift
    /// does not promise a stored property the stable address an unfair lock
    /// needs, so passing `&property` to `os_unfair_lock_lock` was undefined
    /// behavior that merely happened to work.
    private let lock = NSLock()

    private init() {}

    /// Get cached MachOImage or compute and cache it atomically
    /// - Parameters:
    ///   - index: The image index
    ///   - compute: Closure to compute the MachOImage if not cached
    /// - Returns: The cached or newly computed MachOImage
    func machO(at index: Int, orCompute compute: () -> MachOImage?) -> MachOImage? {
        lock.lock()
        defer { lock.unlock() }

        let key = NSNumber(value: index)
        if let cached = cache.object(forKey: key) {
            return cached.image
        }
        guard let result = compute() else {
            return nil
        }
        cache.setObject(MachOImageWrapper(result), forKey: key)
        return result
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAllObjects()
    }
}

private final class MachOImageWrapper: NSObject {
    let image: MachOImage
    init(_ image: MachOImage) {
        self.image = image
    }
}
#endif


extension DyldCacheLoaded {
    var headerOptimizationRO64: ObjCHeaderOptimizationRO64? {
        guard cpu.is64Bit else {
            return nil
        }
        if let objcOptimization {
            return objcOptimization.headerOptimizationRO64(in: self)
        }
        if let oldObjcOptimization {
            return oldObjcOptimization.headerOptimizationRO64(in: self)
        }
        return nil
    }

    var headerOptimizationRO32: ObjCHeaderOptimizationRO32? {
        guard !cpu.is64Bit else {
            return nil
        }
        if let objcOptimization {
            return objcOptimization.headerOptimizationRO32(in: self)
        }
        if let oldObjcOptimization {
            return oldObjcOptimization.headerOptimizationRO32(in: self)
        }
        return nil
    }

    var headerOptimizationRW64: ObjCHeaderOptimizationRW64? {
        guard cpu.is64Bit else {
            return nil
        }
        if let objcOptimization {
            return objcOptimization.headerOptimizationRW64(in: self)
        }
        if let oldObjcOptimization {
            return oldObjcOptimization.headerOptimizationRW64(in: self)
        }
        return nil
    }

    var headerOptimizationRW32: ObjCHeaderOptimizationRW32? {
        guard !cpu.is64Bit else {
            return nil
        }
        if let objcOptimization {
            return objcOptimization.headerOptimizationRW32(in: self)
        }
        if let oldObjcOptimization {
            return oldObjcOptimization.headerOptimizationRW32(in: self)
        }
        return nil
    }
}

extension DyldCacheLoaded {
    func machO(at index: Int) -> MachOImage? {
        #if canImport(Darwin)
        return MachOImageCache.shared.machO(at: index) { [self] in
            computeMachO(at: index)
        }
        #else
        return computeMachO(at: index)
        #endif
    }

    private func computeMachO(at index: Int) -> MachOImage? {
        if let ro = headerOptimizationRO64,
           ro.contains(index: index) {
            guard let header = cached.headerInfo(at: index, in: ro) else {
                return nil
            }
            return header.machO(in: self)
        }
        if let ro = headerOptimizationRO32,
           ro.contains(index: index) {
            guard let header = cached.headerInfo(at: index, in: ro) else {
                return nil
            }
            return header.machO(in: self)
        }
        return nil
    }
}

extension DyldCacheLoaded {
    /// The first of `machOImages()` one of whose segments contains `ptr`,
    /// found in a table built once per loaded cache instead of walking the
    /// cache's thousands of images for every pointer.
    func machO(containing ptr: UnsafeRawPointer) -> MachOImage? {
        LoadedCacheImageAddressTables.shared.tables(for: self).slidAddresses.image(containing: UInt64(UInt(bitPattern: ptr)))
    }

    /// The first of `machOImages()` one of whose segments contains
    /// `unslidAddress`, found the same way.
    func machO(containing unslidAddress: UInt64) -> MachOImage? {
        LoadedCacheImageAddressTables.shared.tables(for: self).unslidAddresses.image(containing: unslidAddress)
    }
}

/// The images of each shared cache loaded into this process by address,
/// slid and unslid, built the first time the cache is asked. A loaded shared
/// cache is never unmapped, so the tables live as long as the process.
private final class LoadedCacheImageAddressTables: @unchecked Sendable {
    static let shared = LoadedCacheImageAddressTables()

    struct Tables {
        /// Addresses as the images' segments declare them.
        let unslidAddresses: CacheImageAddressTable<MachOImage>
        /// Addresses in this process: each segment moved by its image's slide,
        /// the way `MachOImage.contains(ptr:)` reads a pointer.
        let slidAddresses: CacheImageAddressTable<MachOImage>
    }

    private let lock = NSLock()
    private var tablesByCacheAddress: [UInt: Tables] = [:]

    private init() {}

    func tables(for cache: DyldCacheLoaded) -> Tables {
        let cacheAddress = UInt(bitPattern: cache.ptr)
        if let tables = lock.withLock({ tablesByCacheAddress[cacheAddress] }) {
            return tables
        }
        let images = Array(cache.machOImages())
        let builtTables = Tables(
            unslidAddresses: CacheImageAddressTable(images: images) { Self.segmentRanges(of: $0) },
            slidAddresses: CacheImageAddressTable(images: images) { image in
                let slide = Int64(image.vmaddrSlide ?? 0)
                return Self.segmentRanges(of: image).compactMap { range in
                    let slidLowerBound = UInt64(bitPattern: Int64(bitPattern: range.lowerBound) &+ slide)
                    let slidUpperBound = UInt64(bitPattern: Int64(bitPattern: range.upperBound) &+ slide)
                    guard slidLowerBound <= slidUpperBound else { return nil }
                    return slidLowerBound ..< slidUpperBound
                }
            }
        )
        return lock.withLock {
            if let tables = tablesByCacheAddress[cacheAddress] {
                return tables
            }
            tablesByCacheAddress[cacheAddress] = builtTables
            return builtTables
        }
    }

    private static func segmentRanges(of image: MachOImage) -> [Range<UInt64>] {
        image.is64Bit
            ? image.segments64.compactMap(\.virtualMemoryRange)
            : image.segments32.compactMap(\.virtualMemoryRange)
    }
}
