//
//  ObjCProtocolArray32.swift
//
//
//  Created by p-x9 on 2024/11/01
//  
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCProtocolArray32: ObjCProtocolArrayProtocol {
    public typealias ObjCProtocolList = ObjCProtocolList32

    public let offset: Int

    init(
        offset: Int
    ) {
        self.offset = offset
    }
}

extension ObjCProtocolArray32 {
    var kind: ListArrayKind? {
        .init(rawValue: numericCast(offset) & 3)
    }

    public func lists(in machO: MachOImage) -> [ObjCProtocolList] {
        let start = machO.ptr
            .advanced(by: offset & ~3)

        var lists: [ObjCProtocolList] = []
        switch kind {
        case .single:
            lists.append(
                ObjCProtocolList(
                    ptr: start,
                    offset: Int(bitPattern: start) - Int(bitPattern: machO.ptr)
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
                let list = ObjCProtocolList(
                    ptr: ptr,
                    offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr)
                )
                lists.append(list)
                currentOffset += MemoryLayout<UInt>.size
            }
        case .relative:
            // TODO: implement
            break
        case ._dummy, .none:
            break
        }

        return lists
    }
}
