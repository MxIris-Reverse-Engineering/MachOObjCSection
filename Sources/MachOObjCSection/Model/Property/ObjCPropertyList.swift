//
//  ObjCPropertyList.swift
//
//
//  Created by p-x9 on 2024/05/25
//
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCPropertyList {
    public typealias Header = ObjCPropertyListHeader

    /// Offset from machO header start
    public let offset: Int
    public let header: Header
    public let is64Bit: Bool

    init(
        ptr: UnsafeRawPointer,
        offset: Int,
        is64Bit: Bool
    ) {
        self.offset = offset
        self.header = ptr.assumingMemoryBound(to: Header.self).pointee
        self.is64Bit = is64Bit
    }
}

extension ObjCPropertyList {
    public var isListOfLists: Bool {
        offset & 1 == 1
    }
}

extension ObjCPropertyList {
    public var entrySize: Int { numericCast(header.entsize) }

    public var count: Int {
        numericCast(header.count)
    }
}

extension ObjCPropertyList {
    func isValidEntrySize(is64Bit: Bool) -> Bool {
        if is64Bit {
            MemoryLayout<ObjCProperty.Property64>.size == entrySize
        } else {
            MemoryLayout<ObjCProperty.Property32>.size == entrySize
        }
    }
}

extension ObjCPropertyList {
    public func properties(
        in machO: MachOImage
    ) -> [ObjCProperty] {
        // TODO: Support listOfLists
        guard !isListOfLists else { return [] }

        let ptr = machO.ptr.advanced(by: offset)
        let start = ptr.advanced(by: MemoryLayout<Header>.size)
        let sequence = MemorySequence(
            basePointer: start.assumingMemoryBound(
                to: ObjCProperty.Property.self
            ),
            numberOfElements: count
        )
        return sequence
            .map { ObjCProperty($0) }
    }

    public func properties(
        in machO: MachOFile
    ) -> [ObjCProperty] {
        guard !isListOfLists else {
            assertionFailure()
            return []
        }

        let headerStartOffset = machO.headerStartOffset
        var offset: UInt64 = numericCast(headerStartOffset + offset)

        var fileHandle = machO.fileHandle
        if let (_cache, _offset) = machO.cacheAndFileOffset(
            fromStart: offset
        ) {
            offset = _offset
            fileHandle = _cache.fileHandle
        }


        if machO.is64Bit {
            let sequence: DataSequence<ObjCProperty.Property64> = fileHandle
                .readDataSequence(
                    offset: offset + numericCast(MemoryLayout<Header>.size),
                    numberOfElements: count
                )
            return sequence
                .compactMap {
                    var name = UInt64($0.name) & 0x7ffffffff
                    var attributes = UInt64($0.attributes) & 0x7ffffffff

                    var nameFileHandle = machO.fileHandle
                    var attributesFileHandle = machO.fileHandle

                    if let (_cache, _offset) = machO.cacheAndFileOffset(
                        fromStart: name
                    ) {
                        name = _offset
                        nameFileHandle = _cache.fileHandle
                    }

                    if let (_cache, _offset) = machO.cacheAndFileOffset(
                        fromStart: attributes
                    ) {
                        attributes = _offset
                        attributesFileHandle = _cache.fileHandle
                    }

                    return ObjCProperty(
                        name: nameFileHandle.readString(
                            offset: numericCast(machO.headerStartOffset) + name
                        ) ?? "",
                        attributes: attributesFileHandle.readString(
                            offset: numericCast(headerStartOffset) + attributes
                        ) ?? ""
                    )
                }
        } else {
            let sequence: DataSequence<ObjCProperty.Property32> = fileHandle
                .readDataSequence(
                    offset: offset + numericCast(MemoryLayout<Header>.size),
                    numberOfElements: count
                )
            return sequence
                .map {
                    var name = UInt64($0.name)
                    var attributes = UInt64($0.attributes)

                    var nameFileHandle = machO.fileHandle
                    var attributesFileHandle = machO.fileHandle


                    if let (_cache, _offset) = machO.cacheAndFileOffset(
                        fromStart: name
                    ) {
                        name = _offset
                        nameFileHandle = _cache.fileHandle
                    }

                    if let (_cache, _offset) = machO.cacheAndFileOffset(
                        fromStart: attributes
                    ) {
                        attributes = _offset
                        attributesFileHandle = _cache.fileHandle
                    }

                    return ObjCProperty(
                        name: nameFileHandle.readString(
                            offset: numericCast(headerStartOffset) + name
                        ) ?? "",
                        attributes: attributesFileHandle.readString(
                            offset: numericCast(headerStartOffset) + attributes
                        ) ?? ""
                    )
                }
        }
    }
}
