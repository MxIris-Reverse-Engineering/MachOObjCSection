//
//  ObjCHeaderOptimizationRO+.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/11/03
//  
//

import MachOKit

extension ObjCHeaderOptimizationROProtocol {
    func contains(index: Int) -> Bool {
        (0 ..< count).contains(index)
    }
}

extension ObjCHeaderInfoROProtocol {
    func _machO(mainCache: DyldCache) -> MachOFile? {
        if let machO = machO(in: mainCache) {
            return machO
        }
        guard let subCaches = mainCache.subCaches else {
            return nil
        }
        for subCache in subCaches {
            guard let cache = try? subCache.subcache(for: mainCache) else {
                continue
            }
            if let machO = machO(in: cache) {
                return machO
            }
        }
        return nil
    }
}
