//
//  _ObjCClassLayoutProtocol.swift
//
//
//  Created by p-x9 on 2024/08/06
//  
//

import Foundation

public protocol _ObjCClassLayoutProtocol {
    associatedtype Pointer: FixedWidthInteger

    var isa: Pointer { get }
    var superclass: Pointer { get }
    var methodCacheBuckets: Pointer { get }
    var methodCacheProperties: Pointer { get }
    var dataVMAddrAndFastFlags: Pointer { get }

    // This field is only present if this is a Swift object, ie, has the Swift
    // fast bits set
    var swiftClassFlags: UInt32 { get }
}
