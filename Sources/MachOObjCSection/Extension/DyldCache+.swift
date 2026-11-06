//
//  DyldCache+.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/11/02
//
//

import Foundation
@_spi(Support) import MachOKit
#if compiler(>=6.0) || (compiler(>=5.10) && hasFeature(AccessLevelOnImport))
internal import FileIO
#else
@_implementationOnly import FileIO
#endif

extension FileHandleHolder<any FileHandleIdentity & AnyObject, DyldCache.File> {
    static let shared: FileHandleHolder<Owner, File> = .init()
}

extension DyldCache {
    internal typealias File = MemoryMappedFile

    var fileHandle: File {
        FileHandleHolder.shared.fileHandle(
            for: fileHandleIdentity,
            initialize: {
                try! .open(url: url, isWritable: false)
            }
        )
    }
}

extension DyldCache {
    var fileStartOffset: UInt64 {
        numericCast(
            header.sharedRegionStart - mainCacheHeader.sharedRegionStart
        )
    }
}

// MARK: - locate value
extension DyldCache {
    /// MachOKit's `locateValue(_:)`, except that a sub-cache file that cannot
    /// be opened is passed over rather than ending the lookup.
    ///
    /// MachOKit's version throws at the first sub-cache file it fails to open,
    /// and every lookup here wants only the value or `nil`: through `try?`, one
    /// missing or unreadable file — a cache copied in part, say — made values
    /// that sit in the files that are there come back as not found.
    func locateValueSkippingUnreadableSubCaches<Value>(
        _ resolver: (DyldCache) -> Value?
    ) -> LocatedValue<Value>? {
        do {
            return try locateValue(resolver)
        } catch {
            // MachOKit has looked in this cache and the main one by the time it
            // throws, which it does only while opening a sub-cache file.
            guard let mainCache, let subCaches = mainCache.subCaches else {
                return nil
            }
            for subCacheEntry in subCaches {
                guard let subCache = try? subCacheEntry.subcache(for: mainCache),
                      let value = resolver(subCache) else {
                    continue
                }
                return LocatedValue(cache: subCache, value: value)
            }
            return nil
        }
    }

    func locateValueSkippingUnreadableSubCaches<Value>(
        _ keyPath: KeyPath<DyldCache, Value?>
    ) -> LocatedValue<Value>? {
        locateValueSkippingUnreadableSubCaches { $0[keyPath: keyPath] }
    }
}

// MARK: - Objective-C
extension DyldCache {
    var _objcOptimization: LocatedValue<ObjCOptimization>? {
        locateValueSkippingUnreadableSubCaches(\.objcOptimization)
    }

    var _oldObjcOptimization: LocatedValue<OldObjCOptimization>? {
        locateValueSkippingUnreadableSubCaches(\.oldObjcOptimization)
    }
}

extension DyldCache {
    var headerOptimizationRO64: ObjCHeaderOptimizationRO64? {
        guard cpu.is64Bit else { return nil }
        if let _objcOptimization {
            return _objcOptimization.value.headerOptimizationRO64(in: self)
        }
        if let _oldObjcOptimization {
            return _oldObjcOptimization.value.headerOptimizationRO64(in: self)
        }
        return nil
    }

    var headerOptimizationRO32: ObjCHeaderOptimizationRO32? {
        guard !cpu.is64Bit else { return nil }
        if let _objcOptimization {
            return _objcOptimization.value.headerOptimizationRO32(in: self)
        }
        if let _oldObjcOptimization {
            return _oldObjcOptimization.value.headerOptimizationRO32(in: self)
        }
        return nil
    }
}

extension DyldCache {
    var _headerOptimizationRO64: LocatedValue<ObjCHeaderOptimizationRO64>? {
        locateValueSkippingUnreadableSubCaches(\.headerOptimizationRO64)
    }

    var _headerOptimizationRO32: LocatedValue<ObjCHeaderOptimizationRO32>? {
        locateValueSkippingUnreadableSubCaches(\.headerOptimizationRO32)
    }
}

extension DyldCache {
    /// The image the Objective-C header at `index` names, worked out once
    /// per cache file: every relative method, property and protocol list
    /// entry names its image by this index, and working it out rebuilds the
    /// whole header info list, searches it and opens sub-cache files.
    func _machO(at index: Int) -> LocatedValue<MachOFile>? {
        DyldCacheImageLookup.lookup(for: self).locatedImage(atHeaderIndex: index) {
            locateMachO(at: index)
        }
    }

    private func locateMachO(at index: Int) -> LocatedValue<MachOFile>? {
        if let located = _headerOptimizationRO64,
           located.value.contains(index: index) {
            let headers = located.value.headerInfos(in: located.cache)
            guard let header = headers?.first(
                where: {
                    $0.index == index
                }
            ) else {
                return nil
            }
            return locateValueSkippingUnreadableSubCaches { header.machO(in: $0) }
        }
        if let located = _headerOptimizationRO32,
           located.value.contains(index: index) {
            let headers = located.value.headerInfos(in: located.cache)
            guard let header = headers?.first(
                where: {
                    $0.index == index
                }
            ) else {
                return nil
            }
            return locateValueSkippingUnreadableSubCaches { header.machO(in: $0) }
        }
        return nil
    }
}

// MARK: - mach-o
extension DyldCache {
    /// The first of `machOFiles()` one of whose segments contains
    /// `unslidAddress`, found in a table built once per cache file
    /// (`CacheImageAddressTable`) instead of walking the cache's thousands of
    /// images for every protocol, class and category pointer.
    func machO(containing unslidAddress: UInt64) -> MachOFile? {
        DyldCacheImageLookup.lookup(for: self).machO(containing: unslidAddress, in: self)
    }
}
