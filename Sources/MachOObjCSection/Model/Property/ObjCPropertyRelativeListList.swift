//
//  ObjCPropertyRelativeListList.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/11/02
//
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCPropertyRelativeListList: RelativeListListProtocol {
    public typealias List = ObjCPropertyList

    public let offset: Int
    public let header: Header

    init(
        ptr: UnsafeRawPointer,
        offset: Int
    ) {
        self.offset = offset
        self.header = ptr.assumingMemoryBound(to: Header.self).pointee
    }

    public func list(in machO: MachOImage, for entry: Entry) -> (MachOImage, List)? {
        let offset = entry.offset + entry.listOffset
        let ptr = machO.ptr.advanced(by: offset)

#if canImport(MachO)
        let cache: DyldCacheLoaded = .current
        guard let machO = entry.machO(in: cache) else { return nil }

        let list = List(
            ptr: ptr,
            offset: .init(bitPattern: ptr) - .init(bitPattern: machO.ptr),
            is64Bit: machO.is64Bit
        )

        return (machO, list)
#else
        return nil
#endif
    }

    public func list(in machO: MachOFile, for entry: Entry) -> (MachOFile, List)? {
        let offset: UInt64 = numericCast(entry.offset + entry.listOffset)

        guard let (cache, resolvedOffset) = machO.cacheAndFileOffset(fromStart: offset) else {
            return nil
        }

        guard let machO = entry.machO(in: cache) else { return nil }

        let data = cache.fileHandle.readData(
            offset: resolvedOffset,
            size: MemoryLayout<List.Header>.size
        )
        let list: List? = data.withUnsafeBytes {
            guard let ptr = $0.baseAddress else {
                return nil
            }
            return .init(
                ptr: ptr,
                offset: numericCast(offset),
                is64Bit: machO.is64Bit
            )
        }

        guard let list else { return nil }

        return (machO, list)
    }
}
