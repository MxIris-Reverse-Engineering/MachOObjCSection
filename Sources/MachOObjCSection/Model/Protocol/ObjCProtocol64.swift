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
    public var offset: Int

    public func layoutOffset(of field: LayoutField) -> Int {
        let keyPath: PartialKeyPath<Layout>

        switch field {
        case .isa: keyPath = \.isa
        case .mangledName: keyPath = \.mangledName
        case .protocols: keyPath = \.protocols
        case .instanceMethods: keyPath = \.instanceMethods
        case .classMethods: keyPath = \.classMethods
        case .optionalInstanceMethods: keyPath = \.optionalInstanceMethods
        case .optionalClassMethods: keyPath = \.optionalClassMethods
        case .instanceProperties: keyPath = \.instanceProperties
        case .size: keyPath = \.size
        case .flags: keyPath = \.flags
        case ._extendedMethodTypes: keyPath = \._extendedMethodTypes
        case ._demangledName: keyPath = \._demangledName
        case ._classProperties: keyPath = \._classProperties
        }

        return layoutOffset(of: keyPath)
    }
}
