//
//  ObjCClassDataProtocol.swift
//
//
//  Created by p-x9 on 2024/08/06
//  
//

import Foundation
@_spi(Support) import MachOKit

public protocol ObjCClassDataProtocol {
    associatedtype Layout: _ObjCClassDataLayoutProtocol
    associatedtype ObjCProtocolList: ObjCProtocolListProtocol

    var layout: Layout { get }
}

extension ObjCClassDataProtocol {
    public func ivarLayout(in machO: MachOFile) -> [UInt8]? {
        _ivarLayout(in: machO, at: numericCast(layout.ivarLayout))
    }

    public func weakIvarLayout(in machO: MachOFile) -> [UInt8]? {
        _ivarLayout(in: machO, at: numericCast(layout.weakIvarLayout))
    }

    public func name(in machO: MachOFile) -> String? {
        var offset: UInt64 = numericCast(layout.name) & 0x7ffffffff + numericCast(machO.headerStartOffset)
        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.header.sharedRegionStart) else {
                return nil
            }
            offset = _offset
        }
        return machO.fileHandle.readString(offset: numericCast(offset))
    }

    public func methods(in machO: MachOFile) -> ObjCMethodList? {
        guard layout.baseMethods > 0 else { return nil }
        var offset: UInt64 = numericCast(layout.baseMethods) & 0x7ffffffff + numericCast(machO.headerStartOffset)
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

    public func properties(in machO: MachOFile) -> ObjCPropertyList? {
        guard layout.baseProperties > 0 else { return nil }
        var offset: UInt64 = numericCast(layout.baseProperties) & 0x7ffffffff + numericCast(machO.headerStartOffset)
        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.header.sharedRegionStart) else {
                return nil
            }
            offset = _offset
        }
        let data = machO.fileHandle.readData(
            offset: offset,
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
}

extension ObjCClassDataProtocol where ObjCProtocolList == ObjCProtocolList64 {
    public func protocols(in machO: MachOFile) -> ObjCProtocolList? {
        guard layout.baseProtocols > 0 else { return nil }
        var offset: UInt64 = numericCast(layout.baseProtocols) & 0x7ffffffff + numericCast(machO.headerStartOffset)
        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.header.sharedRegionStart) else {
                return nil
            }
            offset = _offset
        }
        let data = machO.fileHandle.readData(
            offset: offset,
            size: MemoryLayout<ObjCProtocolList64.Header>.size
        )
        let list: ObjCProtocolList64? = data.withUnsafeBytes {
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

extension ObjCClassDataProtocol where ObjCProtocolList == ObjCProtocolList32 {
    public func protocols(in machO: MachOFile) -> ObjCProtocolList? {
        guard layout.baseProtocols > 0 else { return nil }
        var offset: UInt64 = numericCast(layout.baseProtocols) + numericCast(machO.headerStartOffset)
        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.header.sharedRegionStart) else {
                return nil
            }
            offset = _offset
        }
        let data = machO.fileHandle.readData(
            offset: offset,
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

extension ObjCClassDataProtocol {
    private func _ivarLayout(
        in machO: MachOFile,
        at offset: Int
    ) -> [UInt8]? {
        var offset: UInt64 = numericCast(offset) & 0x7ffffffff + numericCast(machO.headerStartOffset)
        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.header.sharedRegionStart) else {
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
}
