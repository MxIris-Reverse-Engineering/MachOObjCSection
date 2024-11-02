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
    public typealias ClassROData = ObjCClassROData32
    public typealias ClassRWData = ObjCClassRWData32

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

    public func classROData(in machO: MachOFile) -> ClassROData? {
        _classROData(in: machO)
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
        ), let data = cls.classROData(in: machO) {
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
              let data = superCls.classROData(in: machO) else {
            return nil
        }
        return data.name(in: machO)
    }

    // https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L2534
    public func hasRWPointer(in machO: MachOImage) -> Bool {
        if FAST_IS_RW_POINTER_32 != 0 {
            return numericCast(layout.dataVMAddrAndFastFlags) & FAST_IS_RW_POINTER_32 != 0
        } else {
            guard let data = _classROData(in: machO) else {
                return false
            }
            return data.isRealized
        }
    }

    public func classROData(in machO: MachOImage) -> ClassROData? {
        if hasRWPointer(in: machO) { return nil }
        return _classROData(in: machO)
    }

    public func classRWData(in machO: MachOImage) -> ClassRWData? {
        if !hasRWPointer(in: machO) { return nil }

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
            .assumingMemoryBound(to: ClassRWData.Layout.self)
            .pointee
        let classData = ClassRWData(
            layout: layout,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr)
        )

        return classData
    }
}

extension ObjCClass32 {
    /// https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.mm#L6746
    public func version(in machO: MachOFile) -> Int32 {
        guard let _data = _classROData(in: machO) else {
            return 0
        }
        return _data.isMetaClass ? 7 : 0
    }

    public func version(in machO: MachOImage) -> Int32 {
        if let rw = classRWData(in: machO),
           let ext = rw.ext(in: machO) {
            return numericCast(ext.version)
        }
        guard let _data = _classROData(in: machO) else {
            return 0
        }
        return _data.isMetaClass ? 7 : 0
    }
}

extension ObjCClass32 {
    private func _classROData(in machO: MachOImage) -> ClassROData? {
        let address: UInt = numericCast(layout.dataVMAddrAndFastFlags) & numericCast(FAST_DATA_MASK_32)
        guard let ptr = UnsafeRawPointer(bitPattern: address) else {
            return nil
        }
        let layout = ptr
            .assumingMemoryBound(to: ClassROData.Layout.self)
            .pointee
        let classData = ClassROData(
            layout: layout,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr)
        )

        return classData
    }

    private func _classROData(in machO: MachOFile) -> ClassROData? {
        var offset: UInt64 = numericCast(layout.dataVMAddrAndFastFlags) & numericCast(FAST_DATA_MASK_32) + numericCast(machO.headerStartOffset)

        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.header.sharedRegionStart) else {
                return nil
            }
            offset = _offset
        }

        let layout: ClassROData.Layout = machO.fileHandle.read(offset: offset)
        let classData = ClassROData(layout: layout, offset: Int(offset))

        return classData
    }
}
