//
//  ObjCClass.swift
//
//
//  Created by p-x9 on 2024/08/03
//  
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCClass64: LayoutWrapper, ObjCClassProtocol {
    public typealias Pointer = UInt64
    public typealias ClassData = ObjCClassData64

    public struct Layout: _ObjCClassLayoutProtocol {
        public let isa: Pointer // UnsafeRawPointer?
        public let superclass: Pointer // UnsafeRawPointer?
        public let methodCacheBuckets: Pointer
        public let methodCacheProperties: Pointer // aka vtable
        public let dataVMAddrAndFastFlags: Pointer

        // This field is only present if this is a Swift object, ie, has the Swift
        // fast bits set
        public let swiftClassFlags: UInt32
    }

    public var layout: Layout
}
