//
//  DyldCache+.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/11/02
//
//

import Foundation
import MachOKit

extension DyldCache {
    var fileHandle: FileHandle {
        try! .init(forReadingFrom: url)
    }

    var fileStartOffset: UInt64 {
        numericCast(
            header.sharedRegionStart - mainCacheHeader.sharedRegionStart
        )
    }
}

extension DyldCache {
    var mainCache: DyldCache? {
        if url.lastPathComponent.contains(".") {
            var url = url
            url.deletePathExtension()
            return try? .init(url: url)
        } else {
            return self
        }
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
