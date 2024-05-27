//
//  ObjCProtocolList.swift
//
//
//  Created by p-x9 on 2024/05/25
//  
//

import Foundation

public struct ObjCProtocolList64 {
    public typealias Header = ObjCProtocolListHeader64

    public let offset: Int
    public let header: Header

    init(ptr: UnsafeRawPointer, offset: Int) {
        self.offset = offset
        self.header = ptr.assumingMemoryBound(to: Header.self).pointee
    }
}

extension ObjCProtocolList64 {
    public func protocols(
        in machO: MachOImage
    ) -> [ObjCProtocol64]? {
        let ptr = machO.ptr.advanced(by: offset)
        let sequnece = MemorySequence(
            basePointer: ptr
                .advanced(by: MemoryLayout<Header>.size)
                .assumingMemoryBound(to: UInt64.self),
            numberOfElements: numericCast(header.count)
        )

        return sequnece
            .map {
                UnsafeRawPointer(bitPattern: UInt($0))!
                    .assumingMemoryBound(to: ObjCProtocol64.self)
                    .pointee
            }
    }
}

public struct ObjCProtocolList32 {
    public typealias Header = ObjCProtocolListHeader32

    public let offset: Int
    public let header: Header

    init(ptr: UnsafeRawPointer, offset: Int) {
        self.offset = offset
        self.header = ptr.assumingMemoryBound(to: Header.self).pointee
    }
}

extension ObjCProtocolList32 {
    public func protocols(
        in machO: MachOImage
    ) -> [ObjCProtocol32]? {
        let ptr = machO.ptr.advanced(by: offset)
        let sequnece = MemorySequence(
            basePointer: ptr
                .advanced(by: MemoryLayout<Header>.size)
                .assumingMemoryBound(to: UInt32.self),
            numberOfElements: numericCast(header.count)
        )

        return sequnece
            .map {
                UnsafeRawPointer(bitPattern: UInt($0))!
                    .assumingMemoryBound(to: ObjCProtocol32.self)
                    .pointee
            }
    }
}
