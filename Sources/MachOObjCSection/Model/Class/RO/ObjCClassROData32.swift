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
    public typealias LayoutField = ObjCClassRODataLayoutField

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

    @_spi(Core)
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }

    public func layoutOffset(of field: LayoutField) -> Int {
        let keyPath: PartialKeyPath<Layout>

        switch field {
        case .flags: keyPath = \.flags
        case .instanceStart: keyPath = \.instanceStart
        case .instanceSize: keyPath = \.instanceSize
        case .ivarLayout: keyPath = \.ivarLayout
        case .name: keyPath = \.name
        case .baseMethods: keyPath = \.baseMethods
        case .baseProtocols: keyPath = \.baseProtocols
        case .ivars: keyPath = \.ivars
        case .weakIvarLayout: keyPath = \.weakIvarLayout
        case .baseProperties: keyPath = \.baseProperties
        }

        return layoutOffset(of: keyPath)
    }
}
