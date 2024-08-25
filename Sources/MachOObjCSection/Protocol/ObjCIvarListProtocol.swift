//
//  ObjCIvarListProtocol.swift
//
//
//  Created by p-x9 on 2024/08/25
//
//

import Foundation

public protocol ObjCIvarListProtocol {
    associatedtype ObjCIvar: ObjCIvarProtocol

    var offset: Int { get }
    var header: ObjCIvarListHeader { get }

    func ivars(in machO: MachOImage) -> [ObjCIvar]?
    func ivars(in machO: MachOFile) -> [ObjCIvar]?
}

extension ObjCIvarListProtocol {
    public var entrySize: Int { numericCast(header.entsize) }

    public var count: Int {
        numericCast(header.count)
    }
}
