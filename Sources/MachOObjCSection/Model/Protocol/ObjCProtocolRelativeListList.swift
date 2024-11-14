//
//  ObjCProtocolRelativeListList.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/11/02
//  
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCProtocolRelativeListList64: RelativeListListProtocol {
    public typealias List = ObjCProtocolList64

    public let offset: Int
    public let header: Header

    init(
        ptr: UnsafeRawPointer,
        offset: Int
    ) {
        self.offset = offset
        self.header = ptr.assumingMemoryBound(to: Header.self).pointee
    }

    public func list(in machO: MachOImage, for entry: Entry) -> List? {
        let listOffset = entry.offset + entry.listOffset
        return .init(
            ptr: machO.ptr.advanced(by: listOffset),
            offset: listOffset
        )
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

public struct ObjCProtocolRelativeListList32: RelativeListListProtocol {
    public typealias List = ObjCProtocolList32

    public let offset: Int
    public let header: Header

    init(
        ptr: UnsafeRawPointer,
        offset: Int
    ) {
        self.offset = offset
        self.header = ptr.assumingMemoryBound(to: Header.self).pointee
    }

    public func list(in machO: MachOImage, for entry: Entry) -> List? {
        let listOffset = entry.offset + entry.listOffset
        return .init(
            ptr: machO.ptr.advanced(by: listOffset),
            offset: listOffset
        )
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
