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
    public struct ObjcMethodLists: Sequence {
        public let offset: Int
        public let basePointer: UnsafeRawPointer
        public let tableSize: Int
        public let align: Int // 2^align

        public func makeIterator() -> Iterator {
            .init(
                offset: offset,
                basePointer: basePointer,
                tableSize: tableSize,
                align: align
            )
        }
    }
}

extension MachOImage.ObjcMethodLists {
    public struct Iterator: IteratorProtocol {
        public typealias Element = ObjCMethodList

        private let tableStartOffset: Int
        private let basePointer: UnsafeRawPointer
        private let tableSize: Int
        private let align: Int

        private var nextOffset: Int = 0

        init(
            offset: Int,
            basePointer: UnsafeRawPointer,
            tableSize: Int,
            align: Int
        ) {
            self.tableStartOffset = offset
            self.basePointer = basePointer
            self.tableSize = tableSize
            self.align = align
        }

        public mutating func next() -> Element? {
            guard nextOffset < tableSize else {
                return nil
            }
            let ptr = basePointer
                .advanced(by: nextOffset)

            let header = ptr.assumingMemoryBound(to: Element.Header.self).pointee

            guard nextOffset + header.listSize <= tableSize else {
                return nil
            }

            let list = ObjCMethodList(
                ptr: ptr,
                offset: tableStartOffset + nextOffset
            )
            guard list.isValidEntrySize else {
                preconditionFailure()
            }

            defer {
                nextOffset += list.size
                nextOffset += nextOffset % numericCast(power(2, align))
            }

            return list
        }
    }
}

func power(_ x: Int, _ n: Int ) -> Int {
    (1..<n).reduce(into: x, { result, _ in result *= 2 })
}
