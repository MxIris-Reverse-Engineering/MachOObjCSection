//
//  ObjCClassProtocol.swift
//
//
//  Created by p-x9 on 2024/08/06
//  
//

import Foundation

public protocol ObjCClassProtocol {
    associatedtype Layout: _ObjCClassLayoutProtocol
    associatedtype ClassData: ObjCClassDataProtocol where ClassData.Layout.Pointer == Layout.Pointer

    var layout: Layout { get }
}
