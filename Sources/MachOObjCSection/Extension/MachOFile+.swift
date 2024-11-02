//
//  MachOFile+.swift
//
//
//  Created by p-x9 on 2024/07/19
//  
//

import Foundation
import MachOKit

extension MachOFile {
    var fileHandle: FileHandle {
        try! .init(forReadingFrom: url)
    }
}

extension MachOFile {
    var cache: DyldCache? {
        guard isLoadedFromDyldCache else { return nil }
        return try? DyldCache(url: url)
    }

    func cache(for address: UInt64) -> DyldCache? {
        guard let cache else { return nil }
        if cache.fileOffset(of: address) != nil {
            return cache
        }
        guard let subCaches = cache.mainCache?.subCaches else {
            return nil
        }
        for subCache in subCaches {
            guard let cache = try? subCache.subcache(for: cache) else {
                continue
            }
            if cache.fileOffset(of: address) != nil {
                return cache
            }
        }
        return nil
    }

    func cacheAndFileOffset(for address: UInt64) -> (DyldCache, UInt64)? {
        guard let cache else { return nil }
        if let offset = cache.fileOffset(of: address) {
            return (cache, offset)
        }
        guard let subCaches = cache.mainCache?.subCaches else {
            return nil
        }
        for subCache in subCaches {
            guard let cache = try? subCache.subcache(for: cache) else {
                continue
            }
            if let offset = cache.fileOffset(of: address) {
                return (cache, offset)
            }
        }
        return nil
    }
}

extension MachOFile {
    func isBind(
        _ offset: Int
    ) -> Bool {
        resolveBind(at: numericCast(offset)) != nil
    }
}
