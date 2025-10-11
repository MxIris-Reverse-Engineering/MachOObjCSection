//
//  MachOFile+.swift
//
//
//  Created by p-x9 on 2024/07/19
//
//

import Foundation
import MachOKit
#if compiler(>=6.0) || (compiler(>=5.10) && hasFeature(AccessLevelOnImport))
internal import FileIO
#else
@_implementationOnly import FileIO
#endif

extension MachOFile {
    internal typealias File = MemoryMappedFile

    var fileHandle: File {
        try! .open(url: url, isWritable: false)
    }
}

extension MachOFile {
    var fullCache: FullDyldCache? {
        guard isLoadedFromDyldCache else { return nil }
        return try? FullDyldCache(
            url: url
                .deletingPathExtension()
                .deletingPathExtension()
        )
    }

    var cache: DyldCache? {
        guard isLoadedFromDyldCache else { return nil }
        guard let cache = try? DyldCache(url: url) else {
            return nil
        }
        if let mainCache = cache.mainCache {
            return try? .init(
                subcacheUrl: cache.url,
                mainCacheHeader: mainCache.header
            )
        }
        return cache
    }

    func cache(for address: UInt64) -> DyldCache? {
        cacheAndFileOffset(for: address)?.0
    }

    /// Convert an address that is not slided into the actual cache it contains and the file offset in it.
    /// - Parameter address: address (unslid)
    /// - Returns: cache and file offset
    func cacheAndFileOffset(for address: UInt64) -> (DyldCache, UInt64)? {
        guard let cache else { return nil }
        if let offset = cache.fileOffset(of: address) {
            return (cache, offset)
        }
        guard let mainCache = cache.mainCache else {
            return nil
        }

        if let offset = mainCache.fileOffset(of: address) {
            return (mainCache, offset)
        }

        guard let subCaches = mainCache.subCaches else {
            return nil
        }
        for subCache in subCaches {
            guard let cache = try? subCache.subcache(for: mainCache) else {
                continue
            }
            if let offset = cache.fileOffset(of: address) {
                return (cache, offset)
            }
        }
        return nil
    }

    /// Converts the offset from the start of the main cache to the actual cache
    /// it contains and the file offset within that cache.
    /// - Parameter offset: Offset from the start of the main cache.
    /// - Returns: cache and file offset
    func cacheAndFileOffset(fromStart offset: UInt64) -> (DyldCache, UInt64)? {
        guard let cache else { return nil }
        return cacheAndFileOffset(
            for: cache.mainCacheHeader.sharedRegionStart + offset
        )
    }
}

extension MachOFile {
    func isBind(
        _ offset: Int
    ) -> Bool {
        resolveBind(at: numericCast(offset)) != nil
    }
}

extension MachOFile {
    var relativeMethodSelectorBaseAddressOffset: UInt64? {
        if let cache,
           let offset = cache.relativeMethodSelectorBaseAddressOffset {
            return offset
        }

        if let fullCache,
           let offset = fullCache.relativeMethodSelectorBaseAddressOffset {
            return offset
        }

        return nil
    }

    func findObjCSection64(for section: ObjCMachOSection) -> Section64? {
        findObjCSection64(for: section.rawValue)
    }

    func findObjCSection32(for section: ObjCMachOSection) -> Section? {
        findObjCSection32(for: section.rawValue)
    }

    // [dyld implementation](https://github.com/apple-oss-distributions/dyld/blob/66c652a1f1f6b7b5266b8bbfd51cb0965d67cc44/common/MachOFile.cpp#L3880)
    func findObjCSection64(for name: String) -> Section64? {
        let segmentNames = [
            "__DATA", "__DATA_CONST", "__DATA_DIRTY"
        ]
        let segments = segments64
        for segment in segments {
            guard segmentNames.contains(segment.segmentName) else {
                continue
            }
            if let section = segment._section(for: name, in: self) {
                return section
            }
        }
        return nil
    }

    func findObjCSection32(for name: String) -> Section? {
        let segmentNames = [
            "__DATA", "__DATA_CONST", "__DATA_DIRTY"
        ]
        let segments = segments32
        for segment in segments {
            guard segmentNames.contains(segment.segmentName) else {
                continue
            }
            if let section = segment._section(for: name, in: self) {
                return section
            }
        }
        return nil
    }
}
