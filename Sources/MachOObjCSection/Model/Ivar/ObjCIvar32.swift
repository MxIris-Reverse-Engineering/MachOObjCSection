//
//  ObjCIvar32.swift
//
//
//  Created by p-x9 on 2024/08/22
//  
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCIvar32: LayoutWrapper, ObjCIvarProtocol {
    public struct Layout: _ObjCIvarLayoutProtocol {
        public typealias Pointer = UInt32

        public let offset: Pointer  // uint32_t*
        public let name: Pointer    // const char *
        public let type: Pointer    // const char *
        public let alignment: UInt32
        public let size: UInt32
    }

    public var layout: Layout
    public var offset: Int

    @_spi(Core)
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

extension ObjCIvar32 {
    public func offset(in machO: MachOFile) -> UInt32? {
        let headerStartOffset = machO.headerStartOffset
        var offset: UInt64 = numericCast(layout.offset) + numericCast(headerStartOffset)

//        if let resolved = resolveRebase(\.offset, in: machO) {
//            offset = resolved + numericCast(machO.headerStartOffset)
//        }
//        if isBind(\.offset, in: machO) { return nil }

        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.mainCacheHeader.sharedRegionStart) else {
                return nil
            }
            offset = _offset
        }

        return machO.fileHandle
            .readData(
                offset: offset,
                size: MemoryLayout<UInt32>.size
            ).withUnsafeBytes {
                $0.load(as: UInt32.self)
            }
    }

    public func name(in machO: MachOFile) -> String? {
        let headerStartOffset = machO.headerStartOffset
        var offset: UInt64 = numericCast(layout.name) + numericCast(headerStartOffset)

//        if let resolved = resolveRebase(\.name, in: machO) {
//            offset = resolved + numericCast(machO.headerStartOffset)
//        }
//        if isBind(\.name, in: machO) { return nil }

        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.mainCacheHeader.sharedRegionStart) else {
                return nil
            }
            offset = _offset
        }

        return machO.fileHandle.readString(
            offset: offset
        )
    }

    public func type(in machO: MachOFile) -> String? {
        let headerStartOffset = machO.headerStartOffset
        var offset: UInt64 = numericCast(layout.type) + numericCast(headerStartOffset)

//        if let resolved = resolveRebase(\.type, in: machO) {
//            offset = resolved + numericCast(machO.headerStartOffset)
//        }
//        if isBind(\.type, in: machO) { return nil }

        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.mainCacheHeader.sharedRegionStart) else {
                return nil
            }
            offset = _offset
        }

        return machO.fileHandle.readString(
            offset: offset
        )
    }
}
