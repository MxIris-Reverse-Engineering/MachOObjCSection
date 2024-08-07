//
//  ObjCClassProtocol.swift
//
//
//  Created by p-x9 on 2024/08/06
//  
//

import Foundation
@_spi(Support) import MachOKit

public protocol ObjCClassProtocol {
    associatedtype Layout: _ObjCClassLayoutProtocol
    associatedtype ClassData: LayoutWrapper, ObjCClassDataProtocol where ClassData.Layout.Pointer == Layout.Pointer

    var layout: Layout { get }
}

extension ObjCClassProtocol where Self: LayoutWrapper {
//    public func superClass(in machO: MachOFile) -> Self? {
//        guard layout.superclass > 0 else { return nil }
//        var offset: UInt64 = numericCast(layout.superclass) & 0x7ffffffff + numericCast(machO.headerStartOffset)
//        if let cache = machO.cache {
//            guard let _offset = cache.fileOffset(of: offset + cache.header.sharedRegionStart) else {
//                return nil
//            }
//            offset = _offset
//        }
//        return machO.fileHandle.read(offset: offset)
//    }

    public func classData(in machO: MachOFile) -> ClassData? {
        var offset: UInt64 = numericCast(layout.dataVMAddrAndFastFlags) & 0x00007ffffffffff8 + numericCast(machO.headerStartOffset)
        offset &= 0x7ffffffff
        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.header.sharedRegionStart) else {
                return nil
            }
            offset = _offset
        }
        return machO.fileHandle.read(offset: offset)
    }
}
