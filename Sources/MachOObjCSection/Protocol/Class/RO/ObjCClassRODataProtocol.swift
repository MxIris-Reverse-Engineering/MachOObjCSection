//
//  ObjCClassDataProtocol.swift
//
//
//  Created by p-x9 on 2024/08/06
//
//

import Foundation
@_spi(Support) import MachOKit

public protocol ObjCClassRODataProtocol: _FixupResolvable where LayoutField == ObjCClassRODataLayoutField {
    associatedtype Layout: _ObjCClassRODataLayoutProtocol
    associatedtype ObjCProtocolList: ObjCProtocolListProtocol
    associatedtype ObjCIvarList: ObjCIvarListProtocol
    associatedtype ObjCProtocolRelativeListList: ObjCProtocolRelativeListListProtocol where ObjCProtocolRelativeListList.List == ObjCProtocolList

    var layout: Layout { get }
    var offset: Int { get }

    var isRootClass: Bool { get }

    @_spi(Core)
    init(layout: Layout, offset: Int)

    func ivarLayout(in machO: MachOFile) -> [UInt8]?
    func weakIvarLayout(in machO: MachOFile) -> [UInt8]?
    func name(in machO: MachOFile) -> String?
    func methods(in machO: MachOFile) -> ObjCMethodList?
    func properties(in machO: MachOFile) -> ObjCPropertyList?
    func protocols(in machO: MachOFile) -> ObjCProtocolList?
    func ivars(in machO: MachOFile) -> ObjCIvarList?

    func ivarLayout(in machO: MachOImage) -> [UInt8]?
    func weakIvarLayout(in machO: MachOImage) -> [UInt8]?
    func name(in machO: MachOImage) -> String?
    func methods(in machO: MachOImage) -> ObjCMethodList?
    func properties(in machO: MachOImage) -> ObjCPropertyList?
    func protocols(in machO: MachOImage) -> ObjCProtocolList?
    func ivars(in machO: MachOImage) -> ObjCIvarList?

    func methodRelativeListList(in machO: MachOFile) -> ObjCMethodRelativeListList?
    func propertyRelativeListList(in machO: MachOFile) -> ObjCPropertyRelativeListList?
    func protocolRelativeListList(in machO: MachOFile) -> ObjCProtocolRelativeListList?

    func methodRelativeListList(in machO: MachOImage) -> ObjCMethodRelativeListList?
    func propertyRelativeListList(in machO: MachOImage) -> ObjCPropertyRelativeListList?
    func protocolRelativeListList(in machO: MachOImage) -> ObjCProtocolRelativeListList?
}

extension ObjCClassRODataProtocol {
    public var flags: ObjCClassRODataFlags {
        .init(rawValue: layout.flags)
    }
}

extension ObjCClassRODataProtocol {
    // https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L36

    public var isMetaClass: Bool {
        flags.contains(.meta)
    }

    public var isRootClass: Bool {
        flags.contains(.root)
    }

    // Values for class_rw_t->flags
    // These are not emitted by the compiler and are never used in class_ro_t.
    // Their presence should be considered in future ABI versions.
    // class_t->data is class_rw_t, not class_ro_t
    public var isRealized: Bool {
        flags.contains(.realized)
    }
}

extension ObjCClassRODataProtocol {
    public func ivarLayout(in machO: MachOFile) -> [UInt8]? {
        if flags.contains(.meta) { return nil }
        return _ivarLayout(in: machO, at: numericCast(layout.ivarLayout))
    }

    public func weakIvarLayout(in machO: MachOFile) -> [UInt8]? {
        _ivarLayout(in: machO, at: numericCast(layout.weakIvarLayout))
    }

    public func name(in machO: MachOFile) -> String? {
        var offset: UInt64 = numericCast(layout.name) & 0x7ffffffff + numericCast(machO.headerStartOffset)
        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.mainCacheHeader.sharedRegionStart) else {
                return nil
            }
            offset = _offset
        }
        return machO.fileHandle.readString(offset: numericCast(offset))
    }

    public func methods(in machO: MachOFile) -> ObjCMethodList? {
        guard layout.baseMethods > 0 else { return nil }
        guard layout.baseMethods & 1 == 0 else { return nil }

        var offset: UInt64 = numericCast(layout.baseMethods) & 0x7ffffffff + numericCast(machO.headerStartOffset)

        if let resolved = resolveRebase(.baseMethods, in: machO),
            resolved != offset {
            offset = resolved & 0x7ffffffff + numericCast(machO.headerStartOffset)
        }
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

        var offset: UInt64 = numericCast(layout.baseProperties) & 0x7ffffffff + numericCast(machO.headerStartOffset)

        if let resolved = resolveRebase(.baseProperties, in: machO),
           resolved != offset {
            offset = resolved & 0x7ffffffff + numericCast(machO.headerStartOffset)
        }
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
        if list?.isValidEntrySize(is64Bit: machO.is64Bit) == false {
            // FIXME: Check
            return nil
        }
        return list
    }

    public func ivars(in machO: MachOFile) -> ObjCIvarList? {
        guard layout.ivars > 0 else { return nil }

        var offset: UInt64 = numericCast(layout.ivars) & 0x7ffffffff + numericCast(machO.headerStartOffset)

        if let resolved = resolveRebase(.ivars, in: machO),
           resolved != offset {
            offset = resolved & 0x7ffffffff + numericCast(machO.headerStartOffset)
        }
//        if isBind(\.ivars, in: machO) { return nil }

        var resolvedOffset = offset

        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.mainCacheHeader.sharedRegionStart) else {
                return nil
            }
            resolvedOffset = _offset
        }

        let data = machO.fileHandle.readData(
            offset: resolvedOffset,
            size: MemoryLayout<ObjCIvarList.Header>.size
        )
        let list: ObjCIvarList? = data.withUnsafeBytes {
            guard let ptr = $0.baseAddress else {
                return nil
            }
            return .init(
                header: ptr
                    .assumingMemoryBound(to: ObjCIvarListHeader.self)
                    .pointee,
                offset: numericCast(offset) - machO.headerStartOffset
            )
        }
        if list?.isValidEntrySize(is64Bit: machO.is64Bit) == false {
            // FIXME: Check
            return nil
        }
        return list
    }

    public func protocols(in machO: MachOFile) -> ObjCProtocolList? {
        guard layout.baseProtocols > 0 else { return nil }
        guard layout.baseProtocols & 1 == 0 else { return nil }

        var offset: UInt64 = numericCast(layout.baseProtocols) & 0x7ffffffff + numericCast(machO.headerStartOffset)

        if let resolved = resolveRebase(.baseProtocols, in: machO),
           resolved != offset {
            offset = resolved & 0x7ffffffff + numericCast(machO.headerStartOffset)
        }
//        if isBind(\.baseProtocols, in: machO) { return nil }

        var resolvedOffset = offset

        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.mainCacheHeader.sharedRegionStart) else {
                return nil
            }
            resolvedOffset = _offset
        }

        let data = machO.fileHandle.readData(
            offset: resolvedOffset,
            size: MemoryLayout<ObjCProtocolList.Header>.size
        )

        let list: ObjCProtocolList? = data.withUnsafeBytes {
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

extension ObjCClassRODataProtocol {
    public func ivarLayout(in machO: MachOImage) -> [UInt8]? {
        if flags.contains(.meta) { return nil }
        return _ivarLayout(in: machO, at: numericCast(layout.ivarLayout))
    }

    public func weakIvarLayout(in machO: MachOImage) -> [UInt8]? {
        _ivarLayout(in: machO, at: numericCast(layout.weakIvarLayout))
    }

    public func name(in machO: MachOImage) -> String? {
        guard layout.name > 0 else { return nil }
        guard let ptr = UnsafeRawPointer(bitPattern: UInt(layout.name)) else {
            return nil
        }
        return .init(
            cString: ptr.assumingMemoryBound(to: CChar.self),
            encoding: .utf8
        )
    }

    public func methods(in machO: MachOImage) -> ObjCMethodList? {
        guard layout.baseMethods > 0 else { return nil }
        guard layout.baseMethods & 1 == 0 else { return nil }

        guard let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.baseMethods)
        ) else {
            return nil
        }

        let list = ObjCMethodList(
            ptr: ptr,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr),
            is64Bit: machO.is64Bit
        )

        if list.isValidEntrySize(is64Bit: machO.is64Bit) == false {
            // FIXME: Check
            return nil
        }

        return list
    }

    public func properties(in machO: MachOImage) -> ObjCPropertyList? {
        guard layout.baseProperties > 0 else { return nil }
        guard layout.baseProperties & 1 == 0 else { return nil }

        guard let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.baseProperties)
        ) else {
            return nil
        }
        let list = ObjCPropertyList(
            ptr: ptr,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr),
            is64Bit: machO.is64Bit
        )

        if list.isValidEntrySize(is64Bit: machO.is64Bit) == false {
            // FIXME: Check
            return nil
        }

        return list
    }

    public func ivars(in machO: MachOImage) -> ObjCIvarList? {
        guard layout.ivars > 0 else { return nil }
        guard let ptr = UnsafeRawPointer(bitPattern: UInt(layout.ivars)) else {
            return nil
        }
        let list = ObjCIvarList(
            header: ptr
                .assumingMemoryBound(to: ObjCIvarListHeader.self)
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

extension ObjCClassRODataProtocol {
    public func methodRelativeListList(in machO: MachOFile) -> ObjCMethodRelativeListList? {
        guard layout.baseMethods > 0 else { return nil }
        guard layout.baseMethods & 1 == 1 else { return nil }

        var offset: UInt64 = numericCast(layout.baseMethods) & 0x7ffffffff + numericCast(machO.headerStartOffset)
        offset &= ~1

        if let resolved = resolveRebase(.baseMethods, in: machO) {
            offset = resolved & 0x7ffffffff + numericCast(machO.headerStartOffset)
            offset &= ~1
        }
//        if isBind(\.baseMethods, in: machO) { return nil }

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

        var offset: UInt64 = numericCast(layout.baseProperties) & 0x7ffffffff + numericCast(machO.headerStartOffset)
        offset &= ~1

        if let resolved = resolveRebase(.baseProperties, in: machO) {
            offset = resolved & 0x7ffffffff + numericCast(machO.headerStartOffset)
            offset &= ~1
        }
//        if isBind(\.baseProperties, in: machO) { return nil }

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

    public func protocolRelativeListList(in machO: MachOFile) -> ObjCProtocolRelativeListList? {
        guard layout.baseProtocols > 0 else { return nil }
        guard layout.baseProtocols & 1 == 1 else { return nil }

        var offset: UInt64 = numericCast(layout.baseProtocols) & 0x7ffffffff + numericCast(machO.headerStartOffset)
        offset &= ~1

        if let resolved = resolveRebase(.baseProtocols, in: machO) {
            offset = resolved & 0x7ffffffff + numericCast(machO.headerStartOffset)
            offset &= ~1
        }
//        if isBind(\.baseProtocols, in: machO) { return nil }

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
            size: MemoryLayout<ObjCProtocolRelativeListList.Header>.size
        )

        let lists: ObjCProtocolRelativeListList? = data.withUnsafeBytes {
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

extension ObjCClassRODataProtocol {
    public func methodRelativeListList(
        in machO: MachOImage
    ) -> ObjCMethodRelativeListList? {
        guard layout.baseMethods > 0 else { return nil }
        guard layout.baseMethods & 1 == 1 else { return nil }

        guard let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.baseMethods & ~1)
        ) else {
            return nil
        }

        return .init(
            ptr: ptr,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr)
        )
    }

    public func propertyRelativeListList(
        in machO: MachOImage
    ) -> ObjCPropertyRelativeListList? {
        guard layout.baseProperties > 0 else { return nil }
        guard layout.baseProperties & 1 == 1 else { return nil }

        guard let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.baseProperties & ~1)
        ) else {
            return nil
        }

        return .init(
            ptr: ptr,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr)
        )
    }

    public func protocolRelativeListList(
        in machO: MachOImage
    ) -> ObjCProtocolRelativeListList? {
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

extension ObjCClassRODataProtocol {
    private func _ivarLayout(
        in machO: MachOFile,
        at offset: Int
    ) -> [UInt8]? {
        var offset: UInt64 = numericCast(offset) & 0x7ffffffff + numericCast(machO.headerStartOffset)
        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.mainCacheHeader.sharedRegionStart) else {
                return nil
            }
            offset = _offset
        }
        guard let string = machO.fileHandle.readString(offset: offset),
              let data = string.data(using: .utf8) else {
            return nil
        }
        return Array(data)
    }

    private func _ivarLayout(
        in machO: MachOImage,
        at offset: Int
    ) -> [UInt8]? {
        guard let ptr = UnsafeRawPointer(bitPattern: UInt(offset)) else {
            return nil
        }
        guard let string = String(cString: ptr.assumingMemoryBound(to: CChar.self), encoding: .utf8),
              let data = string.data(using: .utf8) else {
            return nil
        }
        return Array(data)
    }
}
