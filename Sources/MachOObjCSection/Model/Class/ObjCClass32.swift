//
//  ObjCClass32.swift
//
//
//  Created by p-x9 on 2024/08/19
//  
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCClass32: LayoutWrapper, ObjCClassProtocol {
    public typealias Pointer = UInt32
    public typealias ClassData = ObjCClassData32

    public struct Layout: _ObjCClassLayoutProtocol {
        public let isa: Pointer // UnsafeRawPointer?
        public let superclass: Pointer // UnsafeRawPointer?
        public let methodCacheBuckets: Pointer
        public let methodCacheProperties: Pointer // aka vtable
        public let dataVMAddrAndFastFlags: Pointer

        // This field is only present if this is a Swift object, ie, has the Swift
        // fast bits set
        public let swiftClassFlags: UInt32
    }

    public var layout: Layout
    public var offset: Int
}

extension ObjCClass32 {
    public func metaClass(in machO: MachOFile) -> Self? {
        _readClass(
            at: numericCast(layout.isa),
            keyPath: \.isa,
            in: machO
        )
    }

    public func superClass(in machO: MachOFile) -> Self? {
        _readClass(
            at: numericCast(layout.superclass),
            keyPath: \.superclass,
            in: machO
        )
    }

    private func _readClass(
        at offset: UInt64,
        keyPath: PartialKeyPath<Layout>,
        in machO: MachOFile
    ) -> Self? {
        guard offset > 0 else { return nil }
        var offset: UInt64 = numericCast(offset) + numericCast(machO.headerStartOffset)
        if let resolved = resolveRebase(keyPath, in: machO) {
            offset = resolved + numericCast(machO.headerStartOffset)
        }
        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.header.sharedRegionStart) else {
                return nil
            }
            offset = _offset
        }
        let layout: ObjCClass32.Layout = machO.fileHandle.read(offset: offset)
        return ObjCClass32(layout: layout, offset: Int(offset))
    }
}
