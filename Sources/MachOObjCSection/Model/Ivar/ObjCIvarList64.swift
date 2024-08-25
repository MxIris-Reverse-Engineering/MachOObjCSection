//
//  ObjCIvarList64.swift
//
//
//  Created by p-x9 on 2024/08/21
//
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCIvarList64: ObjCIvarListProtocol {
    public typealias Header = ObjCIvarListHeader
    public typealias ObjCIvar = ObjCIvar64

    /// Offset from machO header start
    public let offset: Int
    public let header: Header

    init(
        header: ObjCIvarListHeader,
        offset: Int
    ) {
        self.header = header
        self.offset = offset
    }
}

extension ObjCIvarList64 {
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

    public func ivars(in machO: MachOFile) -> [ObjCIvar]? {
        let headerStartOffset = machO.headerStartOffset
        let offset = headerStartOffset + offset + MemoryLayout<Header>.size
        let size = MemoryLayout<ObjCIvar.Layout>.size
        let data = machO.fileHandle.readData(
            offset: numericCast(offset),
            size: size * count
        )
        let sequence: DataSequence<ObjCIvar.Layout> = .init(
            data: data,
            numberOfElements: count
        )
        return sequence
            .enumerated()
            .map {
                .init(
                    layout: $1,
                    offset: offset + ObjCIvar.layoutSize * $0
                )
            }
    }
}
