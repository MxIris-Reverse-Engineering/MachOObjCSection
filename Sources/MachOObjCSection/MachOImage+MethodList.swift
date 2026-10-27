//
//  MachOImage+MethodList.swift
//
//
//  Created by p-x9 on 2024/05/23
//  
//

import Foundation
import MachOKit

extension MachOImage {
    public struct ObjCMethodLists: Sequence {
        public let offset: Int
        public let basePointer: UnsafeRawPointer
        public let tableSize: Int
        public let align: Int // 2^align
        public let is64Bit: Bool

        public func makeIterator() -> Iterator {
            .init(
                offset: offset,
                basePointer: basePointer,
                tableSize: tableSize,
                align: align,
                is64Bit: is64Bit
            )
        }
    }
}

extension MachOImage.ObjCMethodLists {
    public struct Iterator: IteratorProtocol {
        public typealias Element = ObjCMethodList

        private let tableStartOffset: Int
        private let basePointer: UnsafeRawPointer
        private let tableSize: Int
        private let align: Int
        private let is64Bit: Bool

        private var nextOffset: Int = 0

        init(
            offset: Int,
            basePointer: UnsafeRawPointer,
            tableSize: Int,
            align: Int,
            is64Bit: Bool
        ) {
            self.tableStartOffset = offset
            self.basePointer = basePointer
            self.tableSize = tableSize
            self.align = align
            self.is64Bit = is64Bit
        }

        public mutating func next() -> Element? {
            guard nextOffset + MemoryLayout<Element.Header>.size <= tableSize else {
                return nil
            }
            let ptr = basePointer
                .advanced(by: nextOffset)

            let header = ptr.assumingMemoryBound(to: Element.Header.self).pointee
            let listSize = Element.size(for: header)

            guard nextOffset + listSize <= tableSize else {
                return nil
            }

            let list = ObjCMethodList(
                ptr: ptr,
                offset: tableStartOffset + nextOffset,
                is64Bit: is64Bit
            )
            guard list.isValidEntrySize(is64Bit: is64Bit) else {
                preconditionFailure()
            }

            defer {
                nextOffset = roundedUp(nextOffset + list.size, toAlignmentExponent: align)
            }

            return list
        }
    }
}

/// `offset` rounded up to a multiple of `2^alignmentExponent`, the alignment a
/// section's `align` field states as a power-of-two exponent. An exponent too
/// large to shift by — no section is aligned that far — leaves `offset` as is.
func roundedUp(_ offset: Int, toAlignmentExponent alignmentExponent: Int) -> Int {
    guard (0 ..< Int.bitWidth - 1).contains(alignmentExponent) else {
        return offset
    }
    let alignment = 1 << alignmentExponent
    return (offset + alignment - 1) & ~(alignment - 1)
}
