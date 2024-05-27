//
//  ObjCPropertyList.swift
//
//
//  Created by p-x9 on 2024/05/25
//  
//

import Foundation

public struct ObjCPropertyList {
    public typealias Header = ObjCPropertyListHeader

    /// Offset from machO header start
    public let offset: Int
    public let header: Header
    public let isListOfLists: Bool

    init(
        ptr: UnsafeRawPointer,
        offset: Int,
        is64Bit: Bool
    ) {
        self.offset = offset
        self.header = ptr.assumingMemoryBound(to: Header.self).pointee
        if is64Bit {
            self.isListOfLists = (ptr.assumingMemoryBound(to: UInt64.self).pointee & 1) != 0
        } else {
            self.isListOfLists = (ptr.assumingMemoryBound(to: UInt32.self).pointee & 1) != 0
        }
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
}
