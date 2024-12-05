//
//  ObjCIvar32.swift
//
//
//  Created by p-x9 on 2024/08/22
//  
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCIvar32: LayoutWrapper, ObjCIvarProtocol {
    public struct Layout: _ObjCIvarLayoutProtocol {
        public typealias Pointer = UInt32

        public let offset: Pointer  // uint32_t*
        public let name: Pointer    // const char *
        public let type: Pointer    // const char *
        public let alignment: UInt32
        public let size: UInt32
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
        case .offset: keyPath = \.offset
        case .name: keyPath = \.name
        case .type: keyPath = \.type
        case .alignment: keyPath = \.alignment
        case .size: keyPath = \.size
        }

        return layoutOffset(of: keyPath)
    }
}
