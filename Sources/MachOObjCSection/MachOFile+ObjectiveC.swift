//
//  MachOFile+ObjectiveC.swift
//
//
//  Created by p-x9 on 2024/08/01
//  
//

import Foundation
@_spi(Support) import MachOKit

extension MachOFile {
    public struct ObjectiveC {
        private let machO: MachOFile

        init(machO: MachOFile) {
            self.machO = machO
        }
    }

    public var objc: ObjectiveC {
        .init(machO: self)
    }
}

extension MachOFile.ObjectiveC {
    /// `__DATA.__objc_imageinfo` or `__DATA_CONST.__objc_imageinfo`
    public var imageInfo: ObjCImageInfo? {
        let __objc_imageinfo: any SectionProtocol
        if machO.is64Bit,
           let section = machO.findObjCSection64(for: .__objc_imageinfo) {
            __objc_imageinfo = section
        } else if let section = machO.findObjCSection32(for: .__objc_imageinfo) {
            __objc_imageinfo = section
        } else {
            return nil
        }

        return machO.fileHandle.read(
            offset: numericCast(__objc_imageinfo.offset + machO.headerStartOffset)
        )
    }
}

extension MachOFile.ObjectiveC {
    /// `__TEXT.__objc_methlist`
    public var methods: MachOFile.ObjCMethodLists? {
        let loadCommands = machO.loadCommands

        let __objc_methlist: any SectionProtocol
        if let text = loadCommands.text64,
           let section = text.__objc_methlist(in: machO) {
            __objc_methlist = section
        } else if let text = loadCommands.text,
                  let section = text.__objc_methlist(in: machO) {
            __objc_methlist = section
        } else {
            return nil
        }

        return .init(
            data: machO.fileHandle.readData(
                offset: numericCast(__objc_methlist.offset + machO.headerStartOffset),
                size: __objc_methlist.size
            ),
            offset: numericCast(__objc_methlist.offset),
            align: numericCast(__objc_methlist.align),
            is64Bit: machO.is64Bit
        )
    }
}

extension MachOFile.ObjectiveC {
    /// `__DATA.__objc_protolist` or `__DATA_CONST.__objc_protolist`
    public var protocols64: [ObjCProtocol64]? {
        guard machO.is64Bit else { return nil }

        guard let __objc_protolist = machO.findObjCSection64(
            for: .__objc_protolist
        ) else { return nil }

        let data = machO.fileHandle.readData(
            offset: numericCast(__objc_protolist.offset + machO.headerStartOffset),
            size: __objc_protolist.size
        )

        let offsets: DataSequence<UInt64> = .init(
            data: data,
            numberOfElements: __objc_protolist.size / 8
        )

        return offsets
            .map { $0 & 0x7ffffffff }
            .compactMap {
                if let cache = machO.cache {
                    let resolved = cache.fileOffset(of: $0 + cache.mainCacheHeader.sharedRegionStart) ?? $0
                    return ($0, resolved)
                }
                return ($0, $0)
            }
            .map { (offset: UInt64, resolved: UInt64) in
                let layout: ObjCProtocol64.Layout = machO.fileHandle.read(offset: resolved + numericCast(machO.headerStartOffset))
                return .init(layout: layout, offset: numericCast(offset))
            }
    }

    /// `__DATA.__objc_protolist` or `__DATA_CONST.__objc_protolist`
    public var protocols32: [ObjCProtocol32]? {
        guard !machO.is64Bit else { return nil }

        guard let __objc_protolist = machO.findObjCSection32(
            for: .__objc_protolist
        ) else { return nil }

        let data = machO.fileHandle.readData(
            offset: numericCast(__objc_protolist.offset + machO.headerStartOffset),
            size: __objc_protolist.size
        )

        let offsets: DataSequence<UInt32> = .init(
            data: data,
            numberOfElements: __objc_protolist.size / 4
        )

        return offsets
            .compactMap {
                let offset: UInt64 = numericCast($0)
                if let cache = machO.cache {
                    let resolved = cache.fileOffset(of: offset + cache.mainCacheHeader.sharedRegionStart) ?? offset
                    return (offset, resolved)
                }
                return (offset, offset)
            }
            .map { (offset: UInt64, resolved: UInt64) in
                let layout: ObjCProtocol32.Layout = machO.fileHandle.read(offset: resolved + numericCast(machO.headerStartOffset))
                return .init(layout: layout, offset: numericCast(offset))
            }
    }
}

extension MachOFile.ObjectiveC {
    /// `__DATA.__objc_classlist` or `__DATA_CONST.__objc_classlist`
    public var classes64: [ObjCClass64]? {
        guard machO.is64Bit else { return nil }

        guard let __objc_classlist = machO.findObjCSection64(
            for: .__objc_classlist
        ) else { return nil }

        let data = machO.fileHandle.readData(
            offset: numericCast(__objc_classlist.offset + machO.headerStartOffset),
            size: __objc_classlist.size
        )

        let offsets: DataSequence<UInt64> = .init(
            data: data,
            numberOfElements: __objc_classlist.size / 8
        )

        return offsets
            .map { $0 & 0x7ffffffff }
            .compactMap {
                if let cache = machO.cache {
                    let resolved = cache.fileOffset(of: $0 + cache.mainCacheHeader.sharedRegionStart) ?? $0
                    return ($0, resolved)
                }
                return ($0, $0)
            }
            .map { (offset: UInt64, resolved: UInt64) in
                let layout: ObjCClass64.Layout = machO.fileHandle.read(
                    offset: resolved + numericCast(machO.headerStartOffset)
                )
                return .init(layout: layout, offset: numericCast(offset))
            }
    }

    /// `__DATA.__objc_classlist` or `__DATA_CONST.__objc_classlist`
    public var classes32: [ObjCClass32]? {
        guard !machO.is64Bit else { return nil }

        guard let __objc_classlist = machO.findObjCSection32(
            for: .__objc_classlist
        ) else { return nil }

        let data = machO.fileHandle.readData(
            offset: numericCast(__objc_classlist.offset + machO.headerStartOffset),
            size: __objc_classlist.size
        )

        let offsets: DataSequence<UInt32> = .init(
            data: data,
            numberOfElements: __objc_classlist.size / 4
        )

        return offsets
            .compactMap {
                let offset: UInt64 = numericCast($0)
                if let cache = machO.cache {
                    let resolved = cache.fileOffset(of: offset + cache.mainCacheHeader.sharedRegionStart) ?? offset
                    return (offset, resolved)
                }
                return (offset, offset)
            }
            .map { (offset: UInt64, resolved: UInt64) in
                let layout: ObjCClass32.Layout = machO.fileHandle.read(
                    offset: resolved + numericCast(machO.headerStartOffset)
                )
                return .init(layout: layout, offset: numericCast(offset))
            }
    }
}

extension MachOFile.ObjectiveC {
    /// `__DATA.__objc_catlist` or `__DATA_CONST.__objc_catlist`
    public var categories64: [ObjCCategory64]? {
        guard machO.is64Bit else { return nil }

        guard let __objc_catlist = machO.findObjCSection64(
            for: .__objc_catlist
        ) else { return nil }

        let data = machO.fileHandle.readData(
            offset: numericCast(__objc_catlist.offset + machO.headerStartOffset),
            size: __objc_catlist.size
        )

        let offsets: DataSequence<UInt64> = .init(
            data: data,
            numberOfElements: __objc_catlist.size / 8
        )

        return offsets
            .map { $0 & 0x7ffffffff }
            .compactMap {
                if let cache = machO.cache {
                    let resolved = cache.fileOffset(of: $0 + cache.mainCacheHeader.sharedRegionStart) ?? $0
                    return ($0, resolved)
                }
                return ($0, $0)
            }
            .map { (offset: UInt64, resolved: UInt64) in
                let layout: ObjCCategory64.Layout = machO.fileHandle.read(
                    offset: resolved + numericCast(machO.headerStartOffset)
                )
                return .init(
                    layout: layout,
                    offset: numericCast(offset),
                    isCatlist2: false
                )
            }
    }

    /// `__DATA.__objc_catlist` or `__DATA_CONST.__objc_catlist`
    public var categories32: [ObjCCategory32]? {
        guard !machO.is64Bit else { return nil }

        guard let __objc_catlist = machO.findObjCSection32(
            for: .__objc_catlist
        ) else { return nil }

        let data = machO.fileHandle.readData(
            offset: numericCast(__objc_catlist.offset + machO.headerStartOffset),
            size: __objc_catlist.size
        )

        let offsets: DataSequence<UInt32> = .init(
            data: data,
            numberOfElements: __objc_catlist.size / 4
        )

        return offsets
            .compactMap {
                let offset: UInt64 = numericCast($0)
                if let cache = machO.cache {
                    let resolved = cache.fileOffset(of: offset + cache.mainCacheHeader.sharedRegionStart) ?? offset
                    return (offset, resolved)
                }
                return (offset, offset)
            }
            .map { (offset: UInt64, resolved: UInt64) in
                let layout: ObjCCategory32.Layout = machO.fileHandle.read(
                    offset: resolved + numericCast(machO.headerStartOffset)
                )
                return .init(
                    layout: layout,
                    offset: numericCast(offset),
                    isCatlist2: false
                )
            }
    }
}

extension MachOFile.ObjectiveC {
    /// `__DATA.__objc_catlist2` or `__DATA_CONST.__objc_catlist2`
    public var categories2_64: [ObjCCategory64]? {
        guard machO.is64Bit else { return nil }

        guard let __objc_catlist = machO.findObjCSection64(
            for: .__objc_catlist2
        ) else { return nil }

        let data = machO.fileHandle.readData(
            offset: numericCast(__objc_catlist.offset + machO.headerStartOffset),
            size: __objc_catlist.size
        )

        let offsets: DataSequence<UInt64> = .init(
            data: data,
            numberOfElements: __objc_catlist.size / 8
        )

        return offsets
            .map { $0 & 0x7ffffffff }
            .compactMap {
                if let cache = machO.cache {
                    let resolved = cache.fileOffset(of: $0 + cache.mainCacheHeader.sharedRegionStart) ?? $0
                    return ($0, resolved)
                }
                return ($0, $0)
            }
            .map { (offset: UInt64, resolved: UInt64) in
                let layout: ObjCCategory64.Layout = machO.fileHandle.read(
                    offset: resolved + numericCast(machO.headerStartOffset)
                )
                return .init(
                    layout: layout,
                    offset: numericCast(offset),
                    isCatlist2: true
                )
            }
    }

    /// `__DATA.__objc_catlist2` or `__DATA_CONST.__objc_catlist2`
    public var categories2_32: [ObjCCategory32]? {
        guard !machO.is64Bit else { return nil }

        guard let __objc_catlist = machO.findObjCSection32(
            for: .__objc_catlist2
        ) else { return nil }

        let data = machO.fileHandle.readData(
            offset: numericCast(__objc_catlist.offset + machO.headerStartOffset),
            size: __objc_catlist.size
        )

        let offsets: DataSequence<UInt32> = .init(
            data: data,
            numberOfElements: __objc_catlist.size / 4
        )

        return offsets
            .compactMap {
                let offset: UInt64 = numericCast($0)
                if let cache = machO.cache {
                    let resolved = cache.fileOffset(of: offset + cache.mainCacheHeader.sharedRegionStart) ?? offset
                    return (offset, resolved)
                }
                return (offset, offset)
            }
            .map { (offset: UInt64, resolved: UInt64) in
                let layout: ObjCCategory32.Layout = machO.fileHandle.read(
                    offset: resolved + numericCast(machO.headerStartOffset)
                )
                return .init(
                    layout: layout,
                    offset: numericCast(offset),
                    isCatlist2: true
                )
            }
    }
}
