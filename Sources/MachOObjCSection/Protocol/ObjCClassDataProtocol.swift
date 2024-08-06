//
//  ObjCClassDataProtocol.swift
//
//
//  Created by p-x9 on 2024/08/06
//  
//

import Foundation
@_spi(Support) import MachOKit

public protocol ObjCClassDataProtocol {
    associatedtype Layout: _ObjCClassDataLayoutProtocol

    var layout: Layout { get }
}

private extension ObjCClassDataProtocol {
    
}
