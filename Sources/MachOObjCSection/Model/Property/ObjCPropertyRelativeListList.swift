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
        let list = List(
            ptr: machO.ptr.advanced(by: offset),
            offset: offset,
            is64Bit: machO.is64Bit
        )

        let cache: DyldCacheLoaded = .current
        guard let objcOptimization = cache.objcOptimization,
              let ro = objcOptimization.headerOptimizationRO64(in: cache) else {
            return nil
        }

        guard let header = ro.headerInfos(in: cache).first(
            where: { $0.index == entry.imageIndex }
        ),
              let machO = header.machO(in: cache) else {
            return nil
        }

        return (machO, list)
    }

    public func list(in machO: MachOFile, for entry: Entry) -> (MachOFile, List)? {
        let offset: UInt64 = numericCast(entry.offset + entry.listOffset)

        guard let (cache, resolvedOffset) = machO.cacheAndFileOffset(fromStart: offset) else {
            return nil
        }

        guard let listMachO = cache.machO(at: entry.imageIndex) else {
            return nil
        }

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

        return (listMachO, list)
    }
}
