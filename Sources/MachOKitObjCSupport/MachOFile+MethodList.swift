//
//  MachOFile+MethodList.swift
//
//
//  Created by p-x9 on 2024/05/23
//  
//

import Foundation
import MachOKit

extension MachOFile {
    public struct ObjcMethodLists: Sequence {
        public let data: Data
        public let offset: Int
        public let align: Int // 2^align

        public func makeIterator() -> Iterator {
            .init(
                data: data,
                offset: offset,
                align: align
            )
        }
    }
}

extension MachOFile.ObjcMethodLists {
    public struct Iterator: IteratorProtocol {
        public typealias Element = ObjCMethodList

        private let tableStartOffset: Int
        private let data: Data
        private let align: Int

        private var nextOffset: Int = 0

        init(data: Data, offset: Int, align: Int) {
            self.data = data
            self.tableStartOffset = offset
            self.align = align
        }

        public mutating func next() -> Element? {
            guard nextOffset < data.count else {
                return nil
            }
            let data = data.advanced(by: nextOffset)

            guard let header: Element.Header = data.withUnsafeBytes({
                guard let baseAddress = $0.baseAddress else {
                    return nil
                }
                return baseAddress
                    .assumingMemoryBound(to: Element.Header.self)
                    .pointee
            }) else { return nil }

            guard nextOffset + header.listSize <= data.count else {
                return nil
            }

            guard let list: Element = data.withUnsafeBytes({
                guard let ptr = $0.baseAddress else {
                    return nil
                }
                return Element(
                    ptr: ptr,
                    offset: tableStartOffset + nextOffset
                )
            }) else { return nil }

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
