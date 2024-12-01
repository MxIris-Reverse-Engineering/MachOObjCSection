//
//  ObjCProtocolListProtocol.swift
//
//
//  Created by p-x9 on 2024/07/19
//  
//

import Foundation
@_spi(Support) import MachOKit

public protocol ObjCProtocolListHeaderProtocol {
    var count: Int { get }
}

public protocol ObjCProtocolListProtocol {
    associatedtype Header: ObjCProtocolListHeaderProtocol
    associatedtype ObjCProtocol: ObjCProtocolProtocol

    var offset: Int { get }
    var header: Header { get }

    @_spi(Core)
    init(ptr: UnsafeRawPointer, offset: Int)

    func protocols(in machO: MachOImage) -> [ObjCProtocol]?
    func protocols(in machO: MachOFile) -> [ObjCProtocol]?
}

extension ObjCProtocolListProtocol {
    public var isListOfLists: Bool {
        offset & 1 == 1
    }
}

extension ObjCProtocolListProtocol {
    func _readProtocols<Pointer: FixedWidthInteger>(
        in machO: MachOImage,
        pointerType: Pointer.Type
    ) -> [ObjCProtocol]? {
        // TODO: Support listOfLists
        guard !isListOfLists else { return nil }

        let ptr = machO.ptr.advanced(by: offset)
        let sequnece = MemorySequence(
            basePointer: ptr
                .advanced(by: MemoryLayout<Header>.size)
                .assumingMemoryBound(to: Pointer.self),
            numberOfElements: numericCast(header.count)
        )

        return sequnece
            .map {
                UnsafeRawPointer(bitPattern: UInt($0))!
                    .assumingMemoryBound(to: ObjCProtocol.self)
                    .pointee
            }
    }
}
