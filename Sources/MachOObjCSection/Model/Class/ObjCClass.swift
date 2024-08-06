//
//  ObjCClass.swift
//
//
//  Created by p-x9 on 2024/08/03
//  
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCClass64: LayoutWrapper {
    public typealias Pointer = UInt64
    public typealias ClassData = ObjCClassData64

    public struct Layout {
        public let isa: Pointer // UnsafeRawPointer?
        public let superclass: Pointer // UnsafeRawPointer?
        public let methodCacheBuckets: Pointer
        public let methodCacheProperties: Pointer // aka vtable
        public let dataVMAddrAndFastFlags: Pointer

        // This field is only present if this is a Swift object, ie, has the Swift
        // fast bits set
        public let swiftClassFlags: UInt32;
    }

    public var layout: Layout
}

extension ObjCClass64 {
    public func superClass(in machO: MachOFile) -> ObjCClass64? {
        guard layout.superclass > 0 else { return nil }
        var offset = layout.superclass & 0x7ffffffff + numericCast(machO.headerStartOffset)
        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.header.sharedRegionStart) else {
                return nil
            }
            offset = _offset
        }
        return machO.fileHandle.read(offset: offset)
    }

    public func classData(in machO: MachOFile) -> ClassData? {
        var offset = layout.dataVMAddrAndFastFlags & 0x00007ffffffffff8 + numericCast(machO.headerStartOffset)
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
