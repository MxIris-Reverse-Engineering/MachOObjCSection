//
//  ObjCProtocolArrayProtocol.swift
//
//
//  Created by p-x9 on 2024/11/01
//  
//

import Foundation

public protocol ObjCProtocolArrayProtocol {
    associatedtype ObjCProtocolList: ObjCProtocolListProtocol

    func lists(in machO: MachOImage) -> [ObjCProtocolList]
}
