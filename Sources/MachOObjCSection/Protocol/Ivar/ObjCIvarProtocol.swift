//
//  ObjCIvarProtocol.swift
//
//
//  Created by p-x9 on 2024/08/22
//  
//

import Foundation
import MachOObjCSectionC
@_spi(Support) import MachOKit

public protocol ObjCIvarProtocol: _FixupResolvable where LayoutField == ObjCIvarLayoutField {
    associatedtype Layout: _ObjCIvarLayoutProtocol

    var layout: Layout { get }
    var offset: Int { get }

    @_spi(Core)
    init(layout: Layout, offset: Int)

    func offset(in machO: MachOFile) -> UInt32?
    func name(in machO: MachOFile) -> String?
    func type(in machO: MachOFile) -> String?

    func offset(in machO: MachOImage) -> UInt32?
    func name(in machO: MachOImage) -> String
    func type(in machO: MachOImage) -> String?
}

extension ObjCIvarProtocol {
    // https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L1312
    public var alignment: UInt32 {
        if layout.alignment == ~UInt32.zero {
            return 1 << WORD_SHIFT
        }
        return 1 << layout.alignment
    }
}

extension ObjCIvarProtocol {
    public func offset(in machO: MachOFile) -> UInt32? {
        let headerStartOffset = machO.headerStartOffset
        var offset: UInt64 = machO.fileOffset(
            of: numericCast(layout.offset)
        ) + numericCast(headerStartOffset)

        if let resolved = resolveRebase(.offset, in: machO) {
            offset = machO.fileOffset(of: resolved) + numericCast(headerStartOffset)
        }
//        if isBind(\.offset, in: machO) { return nil }

        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.mainCacheHeader.sharedRegionStart) else {
                return nil
            }
            offset = _offset
        }

        return try! machO.fileHandle.readData(
                offset: numericCast(offset),
                length: MemoryLayout<UInt32>.size
            ).withUnsafeBytes {
                $0.load(as: UInt32.self)
            }
    }

    public func name(in machO: MachOFile) -> String? {
        let headerStartOffset = machO.headerStartOffset
        var offset: UInt64 = machO.fileOffset(
            of: numericCast(layout.name)
        ) + numericCast(headerStartOffset)

        if let resolved = resolveRebase(.name, in: machO) {
            offset = machO.fileOffset(of: resolved) + numericCast(headerStartOffset)
        }
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
        var offset: UInt64 = machO.fileOffset(
            of: numericCast(layout.type)
        ) + numericCast(headerStartOffset)

        if let resolved = resolveRebase(.type, in: machO) {
            offset = machO.fileOffset(of: resolved) + numericCast(headerStartOffset)
        }
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

extension ObjCIvarProtocol {
    public func offset(in machO: MachOImage) -> UInt32? {
        guard layout.offset > 0 else { return nil }
        let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.offset)
        )
        return ptr!.assumingMemoryBound(to: UInt32.self).pointee
    }

    public func name(in machO: MachOImage) -> String {
        let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.name)
        )
        return .init(cString: ptr!.assumingMemoryBound(to: CChar.self))
    }

    public func type(in machO: MachOImage) -> String? {
        guard layout.type > 0 else { return nil }
        let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.type)
        )
        return .init(cString: ptr!.assumingMemoryBound(to: CChar.self))
    }
}
