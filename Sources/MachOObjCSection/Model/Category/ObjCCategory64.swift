//
//  ObjCCategory64.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/12/06
//  
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCCategory64: LayoutWrapper, ObjCCategoryProtocol {
    public typealias Pointer = UInt64
    public typealias ObjCClass = ObjCClass64

    public struct Layout: _ObjCCategoryLayoutProtocol {
        public let name: Pointer // UnsafePointer<CChar>
        public let cls: Pointer
        public let instanceMethods: Pointer // UnsafeRawPointer?
        public let classMethods: Pointer // UnsafeRawPointer?
        public let protocols: Pointer // UnsafeRawPointer?
        public let instanceProperties: Pointer // UnsafeRawPointer?
        // Fields below this point are not always present on disk.
        public let _classProperties: Pointer // UnsafeRawPointer?
    }

    public var layout: Layout
    public var offset: Int

    // Does this category come from the __objc_catlist2 section, not __objc_catlist
    public var isCatlist2: Bool

    @_spi(Core)
    public init(
        layout: Layout,
        offset: Int,
        isCatlist2: Bool
    ) {
        self.layout = layout
        self.offset = offset
        self.isCatlist2 = isCatlist2
    }

    public func layoutOffset(of field: LayoutField) -> Int {
        let keyPath: PartialKeyPath<Layout>

        switch field {
        case .name: keyPath = \.name
        case .cls: keyPath = \.cls
        case .instanceMethods: keyPath = \.instanceMethods
        case .classMethods: keyPath = \.classMethods
        case .protocols: keyPath = \.protocols
        case .instanceProperties: keyPath = \.instanceProperties
        case ._classProperties: keyPath = \._classProperties
        }

        return layoutOffset(of: keyPath)
    }
}
