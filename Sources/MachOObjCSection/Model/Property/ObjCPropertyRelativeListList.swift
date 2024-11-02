//
//  ObjCPropertyRelativeListList.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/11/02
//  
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCPropertyRelativeListList: RelativeListListProtocol {
    public typealias List = ObjCPropertyList

    public let offset: Int
    public let header: Header

    init(
        ptr: UnsafeRawPointer,
        offset: Int
    ) {
        self.offset = offset
        self.header = ptr.assumingMemoryBound(to: Header.self).pointee
    }

    public func list(in machO: MachOImage, for entry: Entry) -> List? {
        let listOffset = entry.offset + entry.listOffset
        return .init(
            ptr: machO.ptr.advanced(by: listOffset),
            offset: listOffset,
            is64Bit: machO.is64Bit
        )
    }
}
