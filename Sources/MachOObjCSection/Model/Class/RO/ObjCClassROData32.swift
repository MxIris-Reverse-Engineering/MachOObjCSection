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
