//
//  ObjCMethodListMask.swift
//  
//
//  Created by p-x9 on 2024/05/23
//  
//

import Foundation

enum ObjCMethodListMask {
    static let isUniqued: UInt32 = 0x1
    static let isSorted: UInt32 = 0x2

    static let usesSelectorOffsets: UInt32 = 0x40000000
    static let isRelative: UInt32 = 0x80000000

    static let sizeMask: UInt32 = 0x0000FFFC
    static var flagMask: UInt32 { ~sizeMask }
}
