//
//  ObjCProtocolList.swift
//
//
//  Created by p-x9 on 2024/05/25
//
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCProtocolList64: ObjCProtocolListProtocol {
    public typealias Header = ObjCProtocolListHeader64
    public typealias ObjCProtocol = ObjCProtocol64

    public let offset: Int
    public let header: Header

    @_spi(Core)
    public init(ptr: UnsafeRawPointer, offset: Int) {
        self.offset = offset
        self.header = ptr.assumingMemoryBound(to: Header.self).pointee
    }
}

extension ObjCProtocolList64 {
    public func protocols(
        in machO: MachOImage
    ) -> [ObjCProtocol]? {
        _readProtocols(in: machO, pointerType: UInt64.self)
    }

    public func protocols(
        in machO: MachOFile
    ) -> [ObjCProtocol]? {
        guard !isListOfLists else {
            assertionFailure()
            return nil
        }

        let headerStartOffset = machO.headerStartOffset/* + machO.headerStartOffsetInCache*/
        let offset: UInt64 = numericCast(headerStartOffset + offset)

        var resolvedOffset = offset

        var fileHandle = machO.fileHandle

        if let (_cache, _offset) = machO.cacheAndFileOffset(
            fromStart: offset
        ) {
            resolvedOffset = _offset
            fileHandle = _cache.fileHandle
        }

        let sequnece: DataSequence<UInt64> = fileHandle
            .readDataSequence(
                offset: resolvedOffset + numericCast(MemoryLayout<Header>.size),
                numberOfElements: numericCast(header.count)
            )

        return sequnece
            .map {
                var offset = $0 & 0x7ffffffff

                var fileHandle = machO.fileHandle

                if let (_cache, _offset) = machO.cacheAndFileOffset(
                    fromStart: offset
                ) {
                    offset = _offset
                    fileHandle = _cache.fileHandle
                }

                return fileHandle.read<ObjCProtocol64>(
                    offset: numericCast(headerStartOffset) + numericCast(offset),
                    swapHandler: { _ in }
                )
            }
    }
}
