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
    var cache: DyldCache? {
        guard isLoadedFromDyldCache else { return nil }
        return try? DyldCache(url: url)
    }
}
