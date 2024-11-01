//
//  ObjCProtocol.swift
//
//
//  Created by p-x9 on 2024/05/27
//  
//

import Foundation
@_spi(Support) import MachOKit

// ref: https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L1619

public struct ObjCProtocol64: LayoutWrapper, ObjCProtocolProtocol {
    public typealias Pointer = UInt64
    public typealias ObjCProtocolList = ObjCProtocolList64

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

extension ObjCProtocol64 {
    public func protocols(in machO: MachOImage) -> ObjCProtocolList? {
        guard machO.is64Bit,
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
        guard machO.is64Bit else { return nil }
        guard layout.protocols > 0 else { return nil }
        let headerStartOffset = machO.headerStartOffset/* + machO.headerStartOffsetInCache*/
        var protocols = layout.protocols & 0x7ffffffff
        if let cache = machO.cache {
            protocols = numericCast(cache.fileOffset(of: numericCast(protocols) + cache.header.sharedRegionStart) ?? 0)
        }
        let data = machO.fileHandle.readData(
            offset: numericCast(headerStartOffset) + numericCast(protocols),
            size: MemoryLayout<ObjCProtocolList64.Header>.size
        )
        return data.withUnsafeBytes {
            guard let baseAddress = $0.baseAddress else { return nil }
            return .init(
                ptr: baseAddress,
                offset: numericCast(protocols)
            )
        }
    }
}
