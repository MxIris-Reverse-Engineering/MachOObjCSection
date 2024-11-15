//
//  ObjCPropertyArray.swift
//  
//
//  Created by p-x9 on 2024/10/31
//  
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCPropertyArray {
    public let offset: Int
    public let is64Bit: Bool

    init(
        offset: Int,
        is64Bit: Bool
    ) {
        self.offset = offset
        self.is64Bit = is64Bit
    }
}

extension ObjCPropertyArray {
    var kind: ListArrayKind? {
        .init(rawValue: numericCast(offset) & 3)
    }

    func lists(in machO: MachOImage) -> [ObjCPropertyList] {
        let start = machO.ptr
            .advanced(by: offset & ~3)

        var lists: [ObjCPropertyList] = []
        switch kind {
        case .single:
            lists.append(
                ObjCPropertyList(
                    ptr: start,
                    offset: Int(bitPattern: start) - Int(bitPattern: machO.ptr),
                    is64Bit: machO.is64Bit
                )
            )
        case .array:
            var currentOffset: Int = 0
            let count = start
                .assumingMemoryBound(to: UInt32.self)
                .pointee
            for _ in 0 ..< Int(count) {
                let address = start
                    .advanced(
                        by: machO.is64Bit ? MemoryLayout<UInt64>.size : 0
                    ) // `count` + align
                    .advanced(by: currentOffset)
                    .assumingMemoryBound(to: UInt.self)
                    .pointee
                guard let ptr = UnsafeRawPointer(bitPattern: address) else {
                    currentOffset += MemoryLayout<UInt>.size
                    continue
                }
                let list = ObjCPropertyList(
                    ptr: ptr,
                    offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr),
                    is64Bit: machO.is64Bit
                )
                lists.append(list)
                currentOffset += MemoryLayout<UInt>.size
            }
        case .relative:
            let relativeListList = ObjCPropertyRelativeListList(
                ptr: start,
                offset: Int(bitPattern: start) - Int(bitPattern: machO.ptr)
            )
            lists = relativeListList.lists(in: machO)
                .map(\.1)
        case ._dummy, .none:
            break
        }

        return lists
    }
}
