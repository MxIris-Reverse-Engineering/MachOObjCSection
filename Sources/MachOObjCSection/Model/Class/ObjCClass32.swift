//
//  ObjCClass32.swift
//
//
//  Created by p-x9 on 2024/08/19
//  
//

import Foundation
@_spi(Support) import MachOKit
import MachOObjCSectionC

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

    public func superClassName(in machO: MachOFile) -> String? {
        _readClassName(
            at: numericCast(layout.superclass),
            keyPath: \.superclass,
            in: machO
        )
    }

    public func classData(in machO: MachOFile) -> ClassData? {
        var offset: UInt64 = numericCast(layout.dataVMAddrAndFastFlags) & numericCast(FAST_DATA_MASK_32) + numericCast(machO.headerStartOffset)

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
        var offset: UInt64 = numericCast(offset) + numericCast(machO.headerStartOffset)
        if let resolved = resolveRebase(keyPath, in: machO) {
            offset = resolved + numericCast(machO.headerStartOffset)
        }
        if isBind(keyPath, in: machO) { return nil }
        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.header.sharedRegionStart) else {
                return nil
            }
            offset = _offset
        }
        let layout: ObjCClass32.Layout = machO.fileHandle.read(offset: offset)
        return ObjCClass32(layout: layout, offset: Int(offset))
    }

    private func _readClassName(
        at offset: UInt64,
        keyPath: PartialKeyPath<Layout>,
        in machO: MachOFile
    ) -> String? {
        guard offset > 0 else { return nil }

        if let cls = _readClass(
            at: offset,
            keyPath: keyPath,
            in: machO
        ), let data = cls.classData(in: machO) {
            return data.name(in: machO)
        }

        if let bindSymbolName = resolveBind(keyPath, in: machO) {
            return bindSymbolName
                .replacingOccurrences(of: "_OBJC_CLASS_$_", with: "")
        }

        return nil
    }
}

extension ObjCClass32 {
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
        let offset: Int = numericCast(layout.isa) - Int(bitPattern: machO.ptr)
        return .init(layout: layout, offset: offset)
    }

    public func superClassName(in machO: MachOImage) -> String? {
        guard let superCls = superClass(in: machO),
              let data = superCls.classData(in: machO) else {
            return nil
        }
        return data.name(in: machO)
    }

    public func classData(in machO: MachOImage) -> ClassData? {
        let address: UInt = numericCast(layout.dataVMAddrAndFastFlags) & numericCast(FAST_DATA_MASK_32)
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
        if classData.hasRWPointer { return nil }

        return classData
    }
}
