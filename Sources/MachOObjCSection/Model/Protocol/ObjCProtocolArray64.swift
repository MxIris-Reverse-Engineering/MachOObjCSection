//
//  ObjCProtocolArray.swift
//
//
//  Created by p-x9 on 2024/11/01
//  
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCProtocolArray64: ObjCProtocolArrayProtocol {
    public typealias ObjCProtocolList = ObjCProtocolList64

    public let offset: Int

    init(
        offset: Int
    ) {
        self.offset = offset
    }
}

extension ObjCProtocolArray64 {
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
            let count = start
                .assumingMemoryBound(to: UInt32.self)
                .pointee
            let sequnece = MemorySequence(
                basePointer: start
                    .advanced(
                        by: machO.is64Bit ? MemoryLayout<UInt64>.size : MemoryLayout<UInt32>.size
                    ) // `count` + align
                    .assumingMemoryBound(to: UInt64.self),
                numberOfElements: numericCast(count)
            )

            lists = sequnece
                .map {
                    let ptr = UnsafeRawPointer(bitPattern: UInt($0))!
                    return ObjCProtocolList(
                        ptr: ptr,
                        offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr)
                    )
                }
        case .relative:
            let relativeListList = ObjCProtocolRelativeListList64(
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
