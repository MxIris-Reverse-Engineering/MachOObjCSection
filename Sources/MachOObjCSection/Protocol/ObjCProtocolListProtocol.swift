//
//  ObjCProtocolListProtocol.swift
//
//
//  Created by p-x9 on 2024/07/19
//  
//

import Foundation

public protocol ObjCProtocolListHeaderProtocol {
    var count: Int { get }
}

public protocol ObjCProtocolListProtocol {
    associatedtype Header: ObjCProtocolListHeaderProtocol
    associatedtype ObjCProtocol: ObjcProtocolProtocol

    var offset: Int { get }
    var header: Header { get }

    func protocols(in machO: MachOImage) -> [ObjCProtocol]?
    func protocols(in machO: MachOFile) -> [ObjCProtocol]?
}
