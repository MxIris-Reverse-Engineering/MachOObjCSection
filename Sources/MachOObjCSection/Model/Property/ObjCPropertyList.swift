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
    ) -> AnyRandomAccessCollection<ObjCProperty> {
        // TODO: Support listOfLists
        guard !isListOfLists else { return AnyRandomAccessCollection([]) }

        let ptr = machO.ptr.advanced(by: offset)
        let start = ptr.advanced(by: MemoryLayout<Header>.size)
        let sequence = MemorySequence(
            basePointer: start.assumingMemoryBound(
                to: ObjCProperty.Property.self
            ),
            numberOfElements: count
        )
        return AnyRandomAccessCollection(
            sequence
                .map { ObjCProperty($0) }
        )
    }

    public func properties(
        in machO: MachOFile
    ) -> AnyRandomAccessCollection<ObjCProperty> {
        // TODO: Support listOfLists
        guard !isListOfLists else { return AnyRandomAccessCollection([]) }

        let headerStartOffset = machO.headerStartOffset
        let start = headerStartOffset + offset
        let size = if machO.is64Bit {
            MemoryLayout<ObjCProperty.Property64>.size
        } else {
            MemoryLayout<ObjCProperty.Property32>.size
        }
        let data = machO.fileHandle.readData(
            offset: numericCast(start + MemoryLayout<Header>.size),
            size: size * count
        )

        if machO.is64Bit {
            let sequence: DataSequence<ObjCProperty.Property64> = .init(
                data: data,
                numberOfElements: count
            )
            return AnyRandomAccessCollection(
                sequence
                    .map {
                        ObjCProperty(
                            name: machO.fileHandle.readString(
                                offset: numericCast(headerStartOffset) + ($0.name & 0x7ffffffff)
                            ) ?? "",
                            attributes: machO.fileHandle.readString(
                                offset: numericCast(headerStartOffset) + ($0.attributes & 0x7ffffffff)
                            ) ?? ""
                        )
                    }
            )
        } else {
            let sequence: DataSequence<ObjCProperty.Property64> = .init(
                data: data,
                numberOfElements: count
            )
            return AnyRandomAccessCollection(
                sequence
                    .map {
                        ObjCProperty(
                            name: machO.fileHandle.readString(
                                offset: numericCast(headerStartOffset) + $0.name
                            ) ?? "",
                            attributes: machO.fileHandle.readString(
                                offset: numericCast(headerStartOffset) + $0.attributes
                            ) ?? ""
                        )
                    }
            )
        }
    }
}
