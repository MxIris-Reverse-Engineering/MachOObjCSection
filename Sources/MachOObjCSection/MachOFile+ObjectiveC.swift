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
    public struct ObjectiveC: ObjCSectionRepresentable {
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
    public var protocols64: [ObjCProtocol64]? {
        guard machO.is64Bit else { return nil }

        guard let __objc_protolist = machO.findObjCSection64(
            for: .__objc_protolist
        ) else { return nil }

        guard let protocols: [ObjCProtocol64] = _readProtocols(
            from: __objc_protolist,
            in: machO
        ) else { return nil }

        return protocols
    }

    public var protocols32: [ObjCProtocol32]? {
        guard !machO.is64Bit else { return nil }

        guard let __objc_protolist = machO.findObjCSection32(
            for: .__objc_protolist
        ) else { return nil }

        guard let protocols: [ObjCProtocol32] = _readProtocols(
            from: __objc_protolist,
            in: machO
        ) else { return nil }

        return protocols
    }
}

extension MachOFile.ObjectiveC {
    public var classes64: [ObjCClass64]? {
        guard machO.is64Bit else { return nil }

        guard let __objc_classlist = machO.findObjCSection64(
            for: .__objc_classlist
        ) else { return nil }

        guard let classes: [ObjCClass64] = _readClasses(
            from: __objc_classlist,
            in: machO
        ) else { return nil }

        return classes
    }

    public var classes32: [ObjCClass32]? {
        guard !machO.is64Bit else { return nil }

        guard let __objc_classlist = machO.findObjCSection32(
            for: .__objc_classlist
        ) else { return nil }

        guard let classes: [ObjCClass32] = _readClasses(
            from: __objc_classlist,
            in: machO
        ) else { return nil }

        return classes
    }

    public var nonLazyClasses64: [ObjCClass64]? {
        guard machO.is64Bit else { return nil }

        guard let __objc_nlclslist = machO.findObjCSection64(
            for: .__objc_nlclslist
        ) else { return nil }

        guard let classes: [ObjCClass64] = _readClasses(
            from: __objc_nlclslist,
            in: machO
        ) else { return nil }

        return classes
    }

    public var nonLazyClasses32: [ObjCClass32]? {
        guard !machO.is64Bit else { return nil }

        guard let __objc_nlclslist = machO.findObjCSection32(
            for: .__objc_nlclslist
        ) else { return nil }

        guard let classes: [ObjCClass32] = _readClasses(
            from: __objc_nlclslist,
            in: machO
        ) else { return nil }

        return classes
    }
}

extension MachOFile.ObjectiveC {
    public var categories64: [ObjCCategory64]? {
        guard machO.is64Bit else { return nil }

        guard let __objc_catlist = machO.findObjCSection64(
            for: .__objc_catlist
        ) else { return nil }

        guard let categories: [ObjCCategory64] = _readCategories(
            from: __objc_catlist,
            in: machO
        ) else { return nil }

        return categories
    }

    public var categories32: [ObjCCategory32]? {
        guard !machO.is64Bit else { return nil }

        guard let __objc_catlist = machO.findObjCSection32(
            for: .__objc_catlist
        ) else { return nil }

        guard let categories: [ObjCCategory32] = _readCategories(
            from: __objc_catlist,
            in: machO
        ) else { return nil }

        return categories
    }

    public var nonLazyCategories64: [ObjCCategory64]? {
        guard machO.is64Bit else { return nil }

        guard let __objc_nlcatlist = machO.findObjCSection64(
            for: .__objc_nlcatlist
        ) else { return nil }

        guard let categories: [ObjCCategory64] = _readCategories(
            from: __objc_nlcatlist,
            in: machO
        ) else { return nil }

        return categories
    }

    public var nonLazyCategories32: [ObjCCategory32]? {
        guard !machO.is64Bit else { return nil }

        guard let __objc_nlcatlist = machO.findObjCSection32(
            for: .__objc_nlcatlist
        ) else { return nil }

        guard let categories: [ObjCCategory32] = _readCategories(
            from: __objc_nlcatlist,
            in: machO
        ) else { return nil }

        return categories
    }
}

extension MachOFile.ObjectiveC {
    public var categories2_64: [ObjCCategory64]? {
        guard machO.is64Bit else { return nil }

        guard let __objc_catlist = machO.findObjCSection64(
            for: .__objc_catlist2
        ) else { return nil }

        guard let categories: [ObjCCategory64] = _readCategories(
            from: __objc_catlist,
            in: machO,
            isCatlist2: true
        ) else { return nil }

        return categories
    }

    public var categories2_32: [ObjCCategory32]? {
        guard !machO.is64Bit else { return nil }

        guard let __objc_catlist = machO.findObjCSection32(
            for: .__objc_catlist2
        ) else { return nil }

        guard let categories: [ObjCCategory32] = _readCategories(
            from: __objc_catlist,
            in: machO,
            isCatlist2: true
        ) else { return nil }

        return categories
    }
}

extension MachOFile.ObjectiveC {
    func _readCategories<
        Categgory: ObjCCategoryProtocol
    >(
        from section: any SectionProtocol,
        in machO: MachOFile,
        isCatlist2: Bool = false
    ) -> [Categgory]? {
        let data = machO.fileHandle.readData(
            offset: numericCast(section.offset + machO.headerStartOffset),
            size: section.size
        )

        typealias Pointer = Categgory.Layout.Pointer
        let pointerSize: Int = MemoryLayout<Pointer>.size
        let offsets: DataSequence<Pointer> = .init(
            data: data,
            numberOfElements: section.size / pointerSize
        )

        return offsets
            .map { UInt64($0) & 0x7ffffffff }
            .compactMap {
                if let cache = machO.cache {
                    let resolved = cache.fileOffset(of: $0 + cache.mainCacheHeader.sharedRegionStart) ?? $0
                    return ($0, resolved)
                }
                return ($0, $0)
            }
            .map { (offset: UInt64, resolved: UInt64) in
                let layout: Categgory.Layout = machO.fileHandle.read(
                    offset: resolved + numericCast(machO.headerStartOffset)
                )
                return .init(
                    layout: layout,
                    offset: numericCast(offset),
                    isCatlist2: isCatlist2
                )
            }
    }

    func _readClasses<
        Class: ObjCClassProtocol
    >(
        from section: any SectionProtocol,
        in machO: MachOFile
    ) -> [Class]? {
        let data = machO.fileHandle.readData(
            offset: numericCast(section.offset + machO.headerStartOffset),
            size: section.size
        )

        typealias Pointer = Class.Layout.Pointer
        let pointerSize: Int = MemoryLayout<Pointer>.size
        let offsets: DataSequence<Pointer> = .init(
            data: data,
            numberOfElements: section.size / pointerSize
        )

        return offsets
            .map { UInt64($0) & 0x7ffffffff }
            .compactMap {
                if let cache = machO.cache {
                    let resolved = cache.fileOffset(of: $0 + cache.mainCacheHeader.sharedRegionStart) ?? $0
                    return ($0, resolved)
                }
                return ($0, $0)
            }
            .map { (offset: UInt64, resolved: UInt64) in
                let layout: Class.Layout = machO.fileHandle.read(
                    offset: resolved + numericCast(machO.headerStartOffset)
                )
                return .init(layout: layout, offset: numericCast(offset))
            }
    }

    func _readProtocols<
        Protocol: ObjCProtocolProtocol
    >(
        from section: any SectionProtocol,
        in machO: MachOFile
    ) -> [Protocol]? {
        let data = machO.fileHandle.readData(
            offset: numericCast(section.offset + machO.headerStartOffset),
            size: section.size
        )

        typealias Pointer = Protocol.Layout.Pointer
        let pointerSize: Int = MemoryLayout<Pointer>.size
        let offsets: DataSequence<Pointer> = .init(
            data: data,
            numberOfElements: section.size / pointerSize
        )

        return offsets
            .map { UInt64($0) & 0x7ffffffff }
            .compactMap {
                if let cache = machO.cache {
                    let resolved = cache.fileOffset(of: $0 + cache.mainCacheHeader.sharedRegionStart) ?? $0
                    return ($0, resolved)
                }
                return ($0, $0)
            }
            .map { (offset: UInt64, resolved: UInt64) in
                let layout: Protocol.Layout = machO.fileHandle.read(offset: resolved + numericCast(machO.headerStartOffset))
                return .init(layout: layout, offset: numericCast(offset))
            }
    }
}
