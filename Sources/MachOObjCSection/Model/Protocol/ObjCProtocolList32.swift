//
//  ObjCProtocolList32.swift
//
//
//  Created by p-x9 on 2024/11/01
//
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCProtocolList32: ObjCProtocolListProtocol {
    public typealias Header = ObjCProtocolListHeader32
    public typealias ObjCProtocol = ObjCProtocol32

    public let offset: Int
    public let header: Header
    public let isListOfLists: Bool

    init(ptr: UnsafeRawPointer, offset: Int) {
        self.offset = offset
        self.header = ptr.assumingMemoryBound(to: Header.self).pointee
        self.isListOfLists = offset & 1 == 1
    }
}

extension ObjCProtocolList32 {
    public func protocols(
        in machO: MachOImage
    ) -> [ObjCProtocol]? {
        // TODO: Support listOfLists
        guard !isListOfLists else { return nil }

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

    public func protocols(
        in machO: MachOFile
    ) -> [ObjCProtocol]? {
        // TODO: Support listOfLists
        guard !isListOfLists else { return nil }

        let headerStartOffset = machO.headerStartOffset/* + machO.headerStartOffsetInCache*/
        let start = headerStartOffset + offset
        let data = machO.fileHandle.readData(
            offset: numericCast(start + MemoryLayout<Header>.size),
            size: MemoryLayout<UInt32>.size * numericCast(header.count)
        )
        let sequnece: DataSequence<UInt32> = .init(
            data: data,
            numberOfElements: numericCast(header.count)
        )

        return sequnece
            .map {
                let offset = $0
                return machO.fileHandle.read<ObjCProtocol32>(
                    offset: numericCast(headerStartOffset) + numericCast(offset),
                    swapHandler: { _ in }
                )
            }
    }
}
