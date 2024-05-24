//
//  ObjCMethodListHeader.swift
//
//
//  Created by p-x9 on 2024/05/23
//  
//

import Foundation

public struct ObjCMethodListHeader {
    public let entsizeAndFlags: UInt32
    public let count: UInt32
}

extension ObjCMethodListHeader {
    typealias Mask = ObjCMethodListMask

    public var entrySize: Int {
        numericCast(entsizeAndFlags & Mask.sizeMask)
    }

    public var flags: UInt32 {
        entsizeAndFlags & Mask.flagMask
    }

    public var listSize: Int {
        MemoryLayout<ObjCMethodListHeader>.size + entrySize * numericCast(count)
    }
}
