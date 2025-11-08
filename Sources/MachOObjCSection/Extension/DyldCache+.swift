//
//  DyldCache+.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/11/02
//
//

import Foundation
import MachOKit
#if compiler(>=6.0) || (compiler(>=5.10) && hasFeature(AccessLevelOnImport))
internal import FileIO
#else
@_implementationOnly import FileIO
#endif

extension DyldCache {
    internal typealias File = MemoryMappedFile

    var fileHandle: File {
        try! .open(url: url, isWritable: false)
    }

    var fileStartOffset: UInt64 {
        numericCast(
            header.sharedRegionStart - mainCacheHeader.sharedRegionStart
        )
    }
}

// MARK: - locate value
extension DyldCache {
    typealias LocateValue<V> = (cache: DyldCache, value: V)

    func locateValue<V>(
        _ keyPath: KeyPath<DyldCache, V?>
    ) -> LocateValue<V>? {
        locateValue({ $0[keyPath: keyPath] })
    }

    func locateValue<V>(
        _ resolver: (DyldCache) -> V?
    ) -> LocateValue<V>? {
        if let value = resolver(self) { return (self, value) }

        guard let mainCache else { return nil }
        if let value = resolver(mainCache) { return (mainCache, value) }

        guard let subCaches = mainCache.subCaches else {
            return nil
        }
        for subCache in subCaches {
            guard let cache = try? subCache.subcache(for: mainCache) else {
                continue
            }
            if let value = resolver(cache) {
                return (cache, value)
            }
        }
        return nil
    }
}

extension DyldCache {
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
        guard cpu.is64Bit else {
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
        guard cpu.is64Bit else {
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

extension DyldCache {
    func machO(at index: Int) -> MachOFile? {
        guard let mainCache else { return nil }
        if let ro = mainCache.headerOptimizationRO64,
           ro.contains(index: index) {
            guard let header = ro.headerInfos(in: mainCache)?.first(
                where: {
                    $0.index == index
                }
            ) else {
                return nil
            }
            return header._machO(mainCache: mainCache)
        }
        if let ro = mainCache.headerOptimizationRO32,
           ro.contains(index: index) {
            guard let header = ro.headerInfos(in: mainCache)?.first(
                where: {
                    $0.index == index
                }
            ) else {
                return nil
            }
            return header._machO(mainCache: mainCache)
        }
        return nil
    }
}

extension DyldCache {
    func machO(containing unslidAddress: UInt64) -> MachOFile? {
        for machO in self.machOFiles() {
            if machO.contains(unslidAddress: unslidAddress) {
                return machO
            }
        }
        return nil
    }
}
