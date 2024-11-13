//
//  ObjCProtocol32.swift
//
//
//  Created by p-x9 on 2024/11/01
//
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCProtocol32: LayoutWrapper, ObjCProtocolProtocol {
    public typealias Pointer = UInt32
    public typealias ObjCProtocolList = ObjCProtocolList32

    public struct Layout: _ObjCProtocolLayoutProtocol {
        public let isa: Pointer // UnsafeRawPointer?
        public let mangledName: Pointer // UnsafePointer<CChar>
        public let protocols: Pointer // UnsafeRawPointer?
        public let instanceMethods: Pointer // UnsafeRawPointer?
        public let classMethods: Pointer // UnsafeRawPointer?
        public let optionalInstanceMethods: Pointer // UnsafeRawPointer?
        public let optionalClassMethods: Pointer // UnsafeRawPointer?
        public let instanceProperties: Pointer // UnsafeRawPointer?
        public let size: UInt32   // sizeof(protocol_t)
        public let flags: UInt32
        // Fields below this point are not always present on disk.
        public let _extendedMethodTypes: Pointer // UnsafePointer<UnsafePointer<CChar>>?
        public let _demangledName: Pointer // UnsafePointer<CChar>?
        public let _classProperties: Pointer // UnsafeRawPointer?
    }

    public var layout: Layout
}

extension ObjCProtocol32 {
    public func protocols(in machO: MachOImage) -> ObjCProtocolList? {
        guard !machO.is64Bit,
              let ptr = UnsafeRawPointer(
                bitPattern: UInt(layout.protocols)
              ) else {
            return nil
        }
        return .init(
            ptr: ptr,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr)
        )
    }

    public func protocols(in machO: MachOFile) -> ObjCProtocolList? {
        guard !machO.is64Bit else { return nil }
        guard layout.protocols > 0 else { return nil }

        let headerStartOffset = machO.headerStartOffset/* + machO.headerStartOffsetInCache*/

        let offset: UInt64 = numericCast(layout.protocols) + numericCast(headerStartOffset)
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
            size: MemoryLayout<ObjCProtocolList32.Header>.size
        )
        return data.withUnsafeBytes {
            guard let baseAddress = $0.baseAddress else { return nil }
            return .init(
                ptr: baseAddress,
                offset: numericCast(offset) - machO.headerStartOffset
            )
        }
    }
}
