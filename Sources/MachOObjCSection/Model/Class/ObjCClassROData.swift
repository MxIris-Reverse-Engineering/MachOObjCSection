//
//  ObjCClassROData.swift
//
//
//  Created by p-x9 on 2024/08/05
//  
//

import Foundation
@_spi(Support) import MachOKit

// https://github.com/apple-oss-distributions/dyld/blob/25174f1accc4d352d9e7e6294835f9e6e9b3c7bf/common/ObjCVisitor.h#L480
// https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L1699
public struct ObjCClassROData64: LayoutWrapper, ObjCClassRODataProtocol {
    public typealias Pointer = UInt64
    public typealias ObjCProtocolList = ObjCProtocolList64
    public typealias ObjCIvarList = ObjCIvarList64

    public struct Layout: _ObjCClassRODataLayoutProtocol {
        public let flags: UInt32
        public let instanceStart: UInt32
        public let instanceSize: Pointer // union { uint32_t instanceSize; PtrTy pad; }
        public let ivarLayout: Pointer // union { const uint8_t * ivarLayout; Class nonMetaclass; };
        public let name: Pointer
        public let baseMethods: Pointer
        public let baseProtocols: Pointer
        public let ivars: Pointer
        public let weakIvarLayout: Pointer
        public let baseProperties: Pointer
    }

    public var layout: Layout
    public var offset: Int
}

public struct ObjCClassROData32: LayoutWrapper, ObjCClassRODataProtocol {
    public typealias Pointer = UInt32
    public typealias ObjCProtocolList = ObjCProtocolList32
    public typealias ObjCIvarList = ObjCIvarList32

    public struct Layout: _ObjCClassRODataLayoutProtocol {
        public let flags: UInt32
        public let instanceStart: UInt32
        public let instanceSize: Pointer // union { uint32_t instanceSize; PtrTy pad; }
        public let ivarLayout: Pointer // union { const uint8_t * ivarLayout; Class nonMetaclass; };
        public let name: Pointer
        public let baseMethods: Pointer
        public let baseProtocols: Pointer
        public let ivars: Pointer
        public let weakIvarLayout: Pointer
        public let baseProperties: Pointer
    }

    public var layout: Layout
    public var offset: Int
}

extension ObjCClassROData64 {
    public func methods(in machO: MachOFile) -> ObjCMethodList? {
        guard layout.baseMethods > 0 else { return nil }
        var offset: UInt64 = numericCast(layout.baseMethods) & 0x7ffffffff + numericCast(machO.headerStartOffset)

        if let resolved = resolveRebase(\.baseMethods, in: machO) {
            offset = resolved & 0x7ffffffff + numericCast(machO.headerStartOffset)
        }
        if isBind(\.baseMethods, in: machO) { return nil }
        offset &= 0x7ffffffff
        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.header.sharedRegionStart) else {
                return nil
            }
            offset = _offset
        }

        let data = machO.fileHandle.readData(
            offset: offset,
            size: MemoryLayout<ObjCMethodList.Header>.size
        )
        let list: ObjCMethodList? = data.withUnsafeBytes {
            guard let ptr = $0.baseAddress else { return nil }
            return .init(
                ptr: ptr,
                offset: numericCast(offset) - machO.headerStartOffset,
                is64Bit: machO.is64Bit
            )
        }
        if list?.isValidEntrySize(is64Bit: machO.is64Bit) == false {
            // FIXME: Check
            return nil
        }
        return list
    }
}

extension ObjCClassROData32 {
    public func methods(in machO: MachOFile) -> ObjCMethodList? {
        guard layout.baseMethods > 0 else { return nil }
        var offset: UInt64 = numericCast(layout.baseMethods) + numericCast(machO.headerStartOffset)

        if let resolved = resolveRebase(\.baseMethods, in: machO) {
            offset = resolved + numericCast(machO.headerStartOffset)
        }
        if isBind(\.baseMethods, in: machO) { return nil }
        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.header.sharedRegionStart) else {
                return nil
            }
            offset = _offset
        }

        let data = machO.fileHandle.readData(
            offset: offset,
            size: MemoryLayout<ObjCMethodList.Header>.size
        )
        let list: ObjCMethodList? = data.withUnsafeBytes {
            guard let ptr = $0.baseAddress else { return nil }
            return .init(
                ptr: ptr,
                offset: numericCast(offset) - machO.headerStartOffset,
                is64Bit: machO.is64Bit
            )
        }
        if list?.isValidEntrySize(is64Bit: machO.is64Bit) == false {
            // FIXME: Check
            return nil
        }
        return list
    }
}
