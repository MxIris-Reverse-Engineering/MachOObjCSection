//
//  ObjCClassROData32.swift
//
//
//  Created by p-x9 on 2024/11/01
//
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCClassROData32: LayoutWrapper, ObjCClassRODataProtocol {
    public typealias Pointer = UInt32
    public typealias ObjCProtocolList = ObjCProtocolList32
    public typealias ObjCIvarList = ObjCIvarList32
    public typealias ObjCProtocolRelativeListList = ObjCProtocolRelativeListList32

    public struct Layout: _ObjCClassRODataLayoutProtocol {
        public let flags: UInt32
        public let instanceStart: UInt32
        public let instanceSize: UInt32
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

extension ObjCClassROData32 {
    public func methods(in machO: MachOFile) -> ObjCMethodList? {
        guard layout.baseMethods > 0 else { return nil }
        guard layout.baseMethods & 1 == 0 else { return nil }

        let offset: UInt64 = numericCast(layout.baseMethods) + numericCast(machO.headerStartOffset)

//        if let resolved = resolveRebase(\.baseMethods, in: machO) {
//            offset = resolved + numericCast(machO.headerStartOffset)
//        }
//        if isBind(\.baseMethods, in: machO) { return nil }

        var resolvedOffset = offset
        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.mainCacheHeader.sharedRegionStart) else {
                return nil
            }
            resolvedOffset = _offset
        }

        let data = machO.fileHandle.readData(
            offset: resolvedOffset,
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

    public func properties(in machO: MachOFile) -> ObjCPropertyList? {
        guard layout.baseProperties > 0 else { return nil }
        guard layout.baseProperties & 1 == 0 else { return nil }

        let offset: UInt64 = numericCast(layout.baseProperties) + numericCast(machO.headerStartOffset)

//        if let resolved = resolveRebase(\.baseProperties, in: machO) {
//            offset = resolved + numericCast(machO.headerStartOffset)
//        }
//        if isBind(\.baseProperties, in: machO) { return nil }

        var resolvedOffset = offset
        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.mainCacheHeader.sharedRegionStart) else {
                return nil
            }
            resolvedOffset = _offset
        }

        let data = machO.fileHandle.readData(
            offset: resolvedOffset,
            size: MemoryLayout<ObjCPropertyList.Header>.size
        )
        let list: ObjCPropertyList? = data.withUnsafeBytes {
            guard let ptr = $0.baseAddress else {
                return nil
            }
            return .init(
                ptr: ptr,
                offset: numericCast(offset) - machO.headerStartOffset,
                is64Bit: machO.is64Bit
            )
        }
        return list
    }

    public func ivars(in machO: MachOFile) -> ObjCIvarList? {
        guard layout.ivars > 0 else { return nil }

        let offset: UInt64 = numericCast(layout.ivars) + numericCast(machO.headerStartOffset)
        var resolvedOffset = offset

        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.mainCacheHeader.sharedRegionStart) else {
                return nil
            }
            resolvedOffset = _offset
        }
        let data = machO.fileHandle.readData(
            offset: resolvedOffset,
            size: MemoryLayout<ObjCIvarList32.Header>.size
        )
        let list: ObjCIvarList32? = data.withUnsafeBytes {
            guard let ptr = $0.baseAddress else {
                return nil
            }
            return .init(
                header: ptr.assumingMemoryBound(to: ObjCIvarListHeader.self).pointee,
                offset: numericCast(offset) - machO.headerStartOffset
            )
        }
        return list
    }

    public func protocols(in machO: MachOFile) -> ObjCProtocolList? {
        guard layout.baseProtocols > 0 else { return nil }
        guard layout.baseProtocols & 1 == 0 else { return nil }

        let offset: UInt64 = numericCast(layout.baseProtocols) + numericCast(machO.headerStartOffset)
        var resolvedOffset = offset

        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.mainCacheHeader.sharedRegionStart) else {
                return nil
            }
            resolvedOffset = _offset
        }
        let data = machO.fileHandle.readData(
            offset: resolvedOffset,
            size: MemoryLayout<ObjCProtocolList32.Header>.size
        )
        let list: ObjCProtocolList32? = data.withUnsafeBytes {
            guard let ptr = $0.baseAddress else {
                return nil
            }
            return .init(
                ptr: ptr,
                offset: numericCast(offset) - machO.headerStartOffset
            )
        }
        return list
    }
}

extension ObjCClassROData32 {
    public func ivars(in machO: MachOImage) -> ObjCIvarList? {
        guard layout.ivars > 0 else { return nil }
        guard let ptr = UnsafeRawPointer(bitPattern: UInt(layout.ivars)) else {
            return nil
        }
        let list = ObjCIvarList(
            header: ptr
                .assumingMemoryBound(to: ObjCIvarList.Header.self)
                .pointee,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr)
        )
        if list.isValidEntrySize(is64Bit: machO.is64Bit) == false {
            // FIXME: Check
            return nil
        }

        return list
    }

    public func protocols(in machO: MachOImage) -> ObjCProtocolList? {
        guard layout.baseProtocols > 0 else { return nil }
        guard layout.baseProtocols & 1 == 0 else { return nil }

        guard let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.baseProtocols)
        ) else {
            return nil
        }
        let list = ObjCProtocolList(
            ptr: ptr,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr)
        )

        return list
    }
}

extension ObjCClassROData32 {
    public func methodRelativeListList(in machO: MachOFile) -> ObjCMethodRelativeListList? {
        guard layout.baseMethods > 0 else { return nil }
        guard layout.baseMethods & 1 == 1 else { return nil }

        var offset: UInt64 = numericCast(layout.baseMethods) + numericCast(machO.headerStartOffset)
        offset &= ~1

//        if let resolved = resolveRebase(\.baseMethods, in: machO) {
//            offset = resolved + numericCast(machO.headerStartOffset)
//        }
//        if isBind(\.baseMethods, in: machO) { return nil }
//        offset &= ~1

        var resolvedOffset = offset

        var fileHandle = machO.fileHandle

        if let (_cache, _offset) = machO.cacheAndFileOffset(
            fromStart: offset
        ) {
            resolvedOffset = _offset
            fileHandle = _cache.fileHandle
        }

        let data = fileHandle.readData(
            offset: resolvedOffset,
            size: MemoryLayout<ObjCMethodRelativeListList.Header>.size
        )

        let lists: ObjCMethodRelativeListList? = data.withUnsafeBytes {
            guard let ptr = $0.baseAddress else {
                return nil
            }
            return .init(
                ptr: ptr,
                offset: numericCast(offset) - machO.headerStartOffset
            )
        }
        return lists
    }

    public func propertyRelativeListList(in machO: MachOFile) -> ObjCPropertyRelativeListList? {
        guard layout.baseProperties > 0 else { return nil }
        guard layout.baseProperties & 1 == 1 else { return nil }

        var offset: UInt64 = numericCast(layout.baseProperties) + numericCast(machO.headerStartOffset)
        offset &= ~1

//        if let resolved = resolveRebase(\.baseProperties, in: machO) {
//            offset = resolved + numericCast(machO.headerStartOffset)
//        }
//        if isBind(\.baseProperties, in: machO) { return nil }
//        offset &= ~1

        var resolvedOffset = offset

        var fileHandle = machO.fileHandle

        if let (_cache, _offset) = machO.cacheAndFileOffset(
            fromStart: offset
        ) {
            resolvedOffset = _offset
            fileHandle = _cache.fileHandle
        }

        let data = fileHandle.readData(
            offset: resolvedOffset,
            size: MemoryLayout<ObjCPropertyRelativeListList.Header>.size
        )

        let lists: ObjCPropertyRelativeListList? = data.withUnsafeBytes {
            guard let ptr = $0.baseAddress else {
                return nil
            }
            return .init(
                ptr: ptr,
                offset: numericCast(offset) - machO.headerStartOffset
            )
        }
        return lists
    }

    public func protocolRelativeListList(in machO: MachOFile) -> ObjCProtocolRelativeListList32? {
        guard layout.baseProtocols > 0 else { return nil }
        guard layout.baseProtocols & 1 == 1 else { return nil }

        var offset: UInt64 = numericCast(layout.baseProtocols) + numericCast(machO.headerStartOffset)
        offset &= ~1

//        if let resolved = resolveRebase(\.baseProtocols, in: machO) {
//            offset = resolved + numericCast(machO.headerStartOffset)
//        }
//        if isBind(\.baseProtocols, in: machO) { return nil }
//        offset &= 0x7ffffffff
//        offset &= ~1

        var resolvedOffset = offset

        var fileHandle = machO.fileHandle

        if let (_cache, _offset) = machO.cacheAndFileOffset(
            fromStart: offset
        ) {
            resolvedOffset = _offset
            fileHandle = _cache.fileHandle
        }

        let data = fileHandle.readData(
            offset: resolvedOffset,
            size: MemoryLayout<ObjCProtocolRelativeListList32.Header>.size
        )

        let lists: ObjCProtocolRelativeListList32? = data.withUnsafeBytes {
            guard let ptr = $0.baseAddress else {
                return nil
            }
            return .init(
                ptr: ptr,
                offset: numericCast(offset) - machO.headerStartOffset
            )
        }
        return lists
    }
}

extension ObjCClassROData32 {
    public func protocolRelativeListList(
        in machO: MachOImage
    ) -> ObjCProtocolRelativeListList32? {
        guard layout.baseProtocols > 0 else { return nil }
        guard layout.baseProtocols & 1 == 1 else { return nil }

        guard let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.baseProtocols & ~1)
        ) else {
            return nil
        }

        return .init(
            ptr: ptr,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr)
        )
    }
}
