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
    public typealias LayoutField = ObjCProtocolLayoutField

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

    @_spi(Core)
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }

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
