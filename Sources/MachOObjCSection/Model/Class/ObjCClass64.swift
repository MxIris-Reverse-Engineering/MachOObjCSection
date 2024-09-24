//
//  ObjCClass.swift
//
//
//  Created by p-x9 on 2024/08/03
//  
//

import Foundation
@_spi(Support) import MachOKit
import MachOObjCSectionC

public struct ObjCClass64: LayoutWrapper, ObjCClassProtocol {
    public typealias Pointer = UInt64
    public typealias ClassData = ObjCClassData64

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

extension ObjCClass64 {
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

    public func classData(in machO: MachOFile) -> ClassData? {
        let FAST_DATA_MASK: UInt64
        if machO.isPhysicalIPhone && !machO.isSimulatorIPhone {
            FAST_DATA_MASK = numericCast(FAST_DATA_MASK_64_IPHONE)
        } else {
            FAST_DATA_MASK = numericCast(FAST_DATA_MASK_64)
        }

        var offset: UInt64 = numericCast(layout.dataVMAddrAndFastFlags) & FAST_DATA_MASK + numericCast(machO.headerStartOffset)
        offset &= 0x7ffffffff

        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.header.sharedRegionStart) else {
                return nil
            }
            offset = _offset
        }
        let layout: ClassData.Layout = machO.fileHandle.read(offset: offset)
        let classData = ClassData(layout: layout, offset: Int(offset))

        // TODO: Support `class_rw_t`
        if classData.hasRWPointer { return nil }

        return classData
    }


    private func _readClass(
        at offset: UInt64,
        keyPath: PartialKeyPath<Layout>,
        in machO: MachOFile
    ) -> Self? {
        guard offset > 0 else { return nil }
        var offset: UInt64 = numericCast(offset) & 0x7ffffffff + numericCast(machO.headerStartOffset)

        if let resolved = resolveRebase(keyPath, in: machO) {
            offset = resolved & 0x7ffffffff + numericCast(machO.headerStartOffset)
        }
        if isBind(keyPath, in: machO) { return nil }
        offset &= 0x7ffffffff

        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.header.sharedRegionStart) else {
                return nil
            }
            offset = _offset
        }
        let layout: ObjCClass64.Layout = machO.fileHandle.read(offset: offset)
        return ObjCClass64(layout: layout, offset: Int(offset))
    }
}

extension ObjCClass64 {
    public func metaClass(in machO: MachOImage) -> Self? {
        guard layout.isa > 0 else { return nil }
        guard let ptr = UnsafeRawPointer(bitPattern: UInt(layout.isa)) else {
            return nil
        }
        let layout = ptr.assumingMemoryBound(to: Layout.self).pointee
        let offset: Int = numericCast(layout.isa) - Int(bitPattern: machO.ptr)
        return .init(layout: layout, offset: offset)
    }

    public func superClass(in machO: MachOImage) -> Self? {
        guard layout.superclass > 0 else { return nil }
        guard let ptr = UnsafeRawPointer(bitPattern: UInt(layout.superclass)) else {
            return nil
        }
        let layout = ptr.assumingMemoryBound(to: Layout.self).pointee
        let offset: Int = numericCast(layout.superclass) - Int(bitPattern: machO.ptr)
        return .init(layout: layout, offset: offset)
    }

    public func classData(in machO: MachOImage) -> ClassData? {
        let FAST_DATA_MASK: UInt
        if machO.isPhysicalIPhone && !machO.isSimulatorIPhone {
            FAST_DATA_MASK = numericCast(FAST_DATA_MASK_64_IPHONE)
        } else {
            FAST_DATA_MASK = numericCast(FAST_DATA_MASK_64)
        }

        let address: UInt = numericCast(layout.dataVMAddrAndFastFlags) & FAST_DATA_MASK

        guard let ptr = UnsafeRawPointer(bitPattern: address) else {
            return nil
        }

        let layout = ptr
            .assumingMemoryBound(to: ClassData.Layout.self)
            .pointee
        let classData = ClassData(
            layout: layout,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr)
        )

        // TODO: Support `class_rw_t`
        // https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L2534
        if classData.hasRWPointer { return nil }

        return classData
    }
}
