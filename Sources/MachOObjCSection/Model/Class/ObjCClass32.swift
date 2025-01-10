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
    public typealias LayoutField = ObjCClassLayoutField

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

    @_spi(Core)
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }

    public func layoutOffset(of field: LayoutField) -> Int {
        let keyPath: PartialKeyPath<Layout>

        switch field {
        case .isa: keyPath = \.isa
        case .superclass: keyPath = \.superclass
        case .methodCacheBuckets: keyPath = \.methodCacheBuckets
        case .methodCacheProperties: keyPath = \.methodCacheProperties
        case .dataVMAddrAndFastFlags: keyPath = \.dataVMAddrAndFastFlags
        case .swiftClassFlags: keyPath = \.swiftClassFlags
        }

        return layoutOffset(of: keyPath)
    }
}

extension ObjCClass32 {
    public func classROData(in machO: MachOFile) -> ClassROData? {
        _classROData(in: machO)
    }
}

extension ObjCClass32 {
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
        let offset: UInt64 = numericCast(layout.dataVMAddrAndFastFlags) & numericCast(FAST_DATA_MASK_32) + numericCast(machO.headerStartOffset)

        var resolved = offset
        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.mainCacheHeader.sharedRegionStart) else {
                return nil
            }
            resolved = _offset
        }

        let layout: ClassROData.Layout = machO.fileHandle.read(offset: resolved)
        let classData = ClassROData(layout: layout, offset: Int(offset))

        return classData
    }
}
