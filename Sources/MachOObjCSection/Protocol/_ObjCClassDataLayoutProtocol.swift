//
//  _ObjCClassDataLayoutProtocol.swift.swift
//
//
//  Created by p-x9 on 2024/08/06
//  
//

import Foundation

public protocol _ObjCClassDataLayoutProtocol {
    associatedtype Pointer: FixedWidthInteger

    var flags: UInt32 { get }
    var instanceStart: UInt32 { get }
    var instanceSize: Pointer { get } // union { uint32_t instanceSize; PtrTy pad; }
    var ivarLayout: Pointer { get } // union { const uint8_t * ivarLayout; Class nonMetaclass; };
    var name: Pointer { get }
    var baseMethods: Pointer { get }
    var baseProtocols: Pointer { get }
    var ivars: Pointer { get }
    var weakIvarLayout: Pointer { get }
    var baseProperties: Pointer { get }
}
