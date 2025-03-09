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

    @_spi(Core)
    public init(ptr: UnsafeRawPointer, offset: Int) {
        self.offset = offset
        self.header = ptr.assumingMemoryBound(to: Header.self).pointee
    }
}

extension ObjCProtocolList32 {
    public func protocols(
        in machO: MachOImage
    ) -> [ObjCProtocol]? {
        _readProtocols(in: machO, pointerType: UInt32.self)
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
                let offset = $0 + numericCast(headerStartOffset)
                var resolvedOffset = offset

                var fileHandle = machO.fileHandle

                if let (_cache, _offset) = machO.cacheAndFileOffset(
                    fromStart: offset
                ) {
                    resolvedOffset = _offset
                    fileHandle = _cache.fileHandle
                }

                let layout: ObjCProtocol32.Layout = fileHandle.read(
                    offset: numericCast(resolvedOffset),
                    swapHandler: { _ in }
                )
                return .init(
                    layout: layout,
                    offset: numericCast(offset) - machO.headerStartOffset
                )
            }
    }
}
