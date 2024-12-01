//
//  ObjCIvarListProtocol.swift
//
//
//  Created by p-x9 on 2024/08/25
//
//

import Foundation
@_spi(Support) import MachOKit

public protocol ObjCIvarListProtocol {
    typealias Header = ObjCIvarListHeader
    associatedtype ObjCIvar: ObjCIvarProtocol

    var offset: Int { get }
    var header: Header { get }

    @_spi(Core)
    init(header: Header, offset: Int)

    func ivars(in machO: MachOImage) -> [ObjCIvar]?
    func ivars(in machO: MachOFile) -> [ObjCIvar]?
}

extension ObjCIvarListProtocol {
    public var entrySize: Int { numericCast(header.entsize) }

    public var count: Int {
        numericCast(header.count)
    }
}

extension ObjCIvarListProtocol {
    func isValidEntrySize(is64Bit: Bool) -> Bool {
        MemoryLayout<ObjCIvar.Layout>.size == entrySize
    }
}

extension ObjCIvarListProtocol where ObjCIvar: LayoutWrapper {
    public func ivars(in machO: MachOImage) -> [ObjCIvar]? {
        let offset = offset + MemoryLayout<Header>.size
        let ptr = machO.ptr.advanced(by: offset)
        let sequnece = MemorySequence(
            basePointer: ptr
                .assumingMemoryBound(to: ObjCIvar.Layout.self),
            numberOfElements: numericCast(header.count)
        )
        return sequnece.enumerated().map {
            ObjCIvar(
                layout: $1,
                offset: offset + ObjCIvar.layoutSize * $0
            )
        }
    }
}
