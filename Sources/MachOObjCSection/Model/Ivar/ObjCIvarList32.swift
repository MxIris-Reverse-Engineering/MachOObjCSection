//
//  ObjCIvarList32.swift
//
//
//  Created by p-x9 on 2024/08/25
//  
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCIvarList32: ObjCIvarListProtocol {
    public typealias ObjCIvar = ObjCIvar32

    /// Offset from machO header start
    public let offset: Int
    public let header: Header

    @_spi(Core)
    public init(
        header: ObjCIvarListHeader,
        offset: Int
    ) {
        self.header = header
        self.offset = offset
    }
}

extension ObjCIvarList32 {
    public func ivars(in machO: MachOFile) -> [ObjCIvar]? {
        let headerStartOffset = machO.headerStartOffset

        var fileHandle = machO.fileHandle

        let offset: UInt64 = numericCast(
            headerStartOffset + offset + MemoryLayout<Header>.size
        )
        var resolvedOffset = offset
        if let (_cache, _offset) = machO.cacheAndFileOffset(
            fromStart: offset
        ) {
            resolvedOffset = _offset
            fileHandle = _cache.fileHandle
        }

        let size = MemoryLayout<ObjCIvar.Layout>.size
        let sequence: DataSequence<ObjCIvar.Layout> = fileHandle
            .readDataSequence(
                offset: resolvedOffset,
                numberOfElements: count
            )
        return sequence
            .enumerated()
            .map {
                .init(
                    layout: $1,
                    offset: numericCast(offset) - headerStartOffset + size * $0
                )
            }
    }
}

