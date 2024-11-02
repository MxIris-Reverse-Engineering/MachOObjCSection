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
