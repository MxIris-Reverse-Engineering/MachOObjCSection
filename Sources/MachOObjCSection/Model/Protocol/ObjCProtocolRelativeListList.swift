//
//  ObjCProtocolRelativeListList.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/11/02
//  
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCProtocolRelativeListList64: ObjCProtocolRelativeListListProtocol {
    public typealias List = ObjCProtocolList64

    public let offset: Int
    public let header: Header

    @_spi(Core)
    public init(
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
            offset: offset
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
            offset: numericCast(resolvedOffset),
            size: MemoryLayout<List.Header>.size
        )
        let list: List? = data.withUnsafeBytes {
            guard let ptr = $0.baseAddress else {
                return nil
            }
            return .init(
                ptr: ptr,
                offset: numericCast(offset)
            )
        }

        guard let list else { return nil }

        return (listMachO, list)
    }
}

public struct ObjCProtocolRelativeListList32: ObjCProtocolRelativeListListProtocol {
    public typealias List = ObjCProtocolList32

    public let offset: Int
    public let header: Header

    @_spi(Core)
    public init(
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
            offset: offset
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
                offset: numericCast(offset)
            )
        }

        guard let list else { return nil }

        return (listMachO, list)
    }
}
