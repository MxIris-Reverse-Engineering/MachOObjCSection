//
//  DyldCacheLoaded.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/11/02
//  
//

import MachOKit

extension DyldCacheLoaded {
    static var current: DyldCacheLoaded {
        var size = 0
        guard let ptr = _dyld_get_shared_cache_range(&size),
              let cache = try? DyldCacheLoaded(ptr: ptr) else {
            fatalError()
        }
        return cache
    }
}

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

extension DyldCacheLoaded {
    func machO(at index: Int) -> MachOImage? {
        if let ro = headerOptimizationRO64,
           ro.contains(index: index) {
            guard let header = ro.headerInfos(in: self).first(
                where: {
                    $0.index == index
                }
            ) else {
                return nil
            }
            return header.machO(in: self)
        }
        if let ro = headerOptimizationRO32,
           ro.contains(index: index) {
            guard let header = ro.headerInfos(in: self).first(
                where: {
                    $0.index == index
                }
            ) else {
                return nil
            }
            return header.machO(in: self)
        }
        return nil
    }
}
