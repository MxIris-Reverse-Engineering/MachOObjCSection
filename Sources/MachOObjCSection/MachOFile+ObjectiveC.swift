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

    public var objc: ObjectiveC  {
        .init(machO: self)
    }
}

extension MachOFile.ObjectiveC {
    /// __DATA.__objc_imageinfo or __DATA_CONST.__objc_imageinfo
    public var imageInfo: ObjCImageInfo? {
        let loadCommands = machO.loadCommands

        let __objc_imageinfo: any SectionProtocol
        if let data = loadCommands.data64,
           let section = data.sections(in: machO).first(
            where: {
                $0.sectionName == "__objc_imageinfo"
            }
           ) {
            __objc_imageinfo = section
        } else if let dataConst = loadCommands.dataConst64,
                  let section = dataConst.sections(in: machO).first(
                    where: {
                        $0.sectionName == "__objc_imageinfo"
                    }
                  ) {
            __objc_imageinfo = section
        } else if let data = loadCommands.data,
                  let section = data.sections(in: machO).first(
                    where: {
                        $0.sectionName == "__objc_imageinfo"
                    }
                  ) {
            __objc_imageinfo = section
        } else if let dataConst = loadCommands.dataConst,
                  let section = dataConst.sections(in: machO).first(
                    where: {
                        $0.sectionName == "__objc_imageinfo"
                    }
                  ) {
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
    /// __TEXT.__objc_methlist
    public var methods: MachOFile.ObjCMethodLists? {
        let loadCommands = machO.loadCommands

        let __objc_methlist: any SectionProtocol
        if let text = loadCommands.text64,
           let section = text.sections(in: machO).first(
            where: {
                $0.sectionName == "__objc_methlist"
            }
           ) {
            __objc_methlist = section
        } else if let text = loadCommands.text,
                  let section = text.sections(in: machO).first(
                    where: {
                        $0.sectionName == "__objc_methlist"
                    }
                  ) {
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
    /// __DATA.__objc_protolist or __DATA_CONST.__objc_protolist
    public var protocols64: [ObjCProtocol64]? {
        guard machO.is64Bit else { return nil }
        let loadCommands = machO.loadCommands

        let __objc_protolist: any SectionProtocol

        if let data = loadCommands.data64,
           let section = data.sections(in: machO).first(
            where: {
                $0.sectionName == "__objc_protolist"
            }
           ) {
            __objc_protolist = section
        } else if let dataConst = loadCommands.dataConst64,
                  let section = dataConst.sections(in: machO).first(
                    where: {
                        $0.sectionName == "__objc_protolist"
                    }
                  ) {
            __objc_protolist = section
        } else {
            return nil
        }

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
                    return cache.fileOffset(of: $0 + cache.mainCacheHeader.sharedRegionStart)
                }
                return $0
            }
            .map {
                let proto: ObjCProtocol64 = machO.fileHandle.read(offset: $0 + numericCast(machO.headerStartOffset))
                return proto
            }
    }

    public var protocols32: [ObjCProtocol32]? {
        guard !machO.is64Bit else { return nil }
        let loadCommands = machO.loadCommands

        let __objc_protolist: any SectionProtocol

        if let data = loadCommands.data,
           let section = data.sections(in: machO).first(
            where: {
                $0.sectionName == "__objc_protolist"
            }
           ) {
            __objc_protolist = section
        } else if let dataConst = loadCommands.dataConst,
                  let section = dataConst.sections(in: machO).first(
                    where: {
                        $0.sectionName == "__objc_protolist"
                    }
                  ) {
            __objc_protolist = section
        } else {
            return nil
        }

        let data = machO.fileHandle.readData(
            offset: numericCast(__objc_protolist.offset + machO.headerStartOffset),
            size: __objc_protolist.size
        )

        let offsets: DataSequence<UInt32> = .init(
            data: data,
            numberOfElements: __objc_protolist.size / 4
        )

        return offsets
            .map {
                let proto: ObjCProtocol32 = machO.fileHandle.read(
                    offset: numericCast($0) + numericCast(machO.headerStartOffset)
                )
                return proto
            }
    }
}

extension MachOFile.ObjectiveC {
    /// __DATA.__objc_classlist or __DATA_CONST.__objc_classlist
    public var classes64: [ObjCClass64]? {
        guard machO.is64Bit else { return nil }
        let loadCommands = machO.loadCommands

        let __objc_classlist: any SectionProtocol

        if let data = loadCommands.data64,
           let section = data.sections(in: machO).first(
            where: {
                $0.sectionName == "__objc_classlist"
            }
           ) {
            __objc_classlist = section
        } else if let dataConst = loadCommands.dataConst64,
                  let section = dataConst.sections(in: machO).first(
                    where: {
                        $0.sectionName == "__objc_classlist"
                    }
                  ) {
            __objc_classlist = section
        } else {
            return nil
        }

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
                    return cache.fileOffset(of: $0 + cache.mainCacheHeader.sharedRegionStart)
                }
                return $0
            }
            .map {
                let layout: ObjCClass64.Layout = machO.fileHandle.read(
                    offset: $0 + numericCast(machO.headerStartOffset)
                )
                return .init(layout: layout, offset: numericCast($0))
            }
    }

    /// __DATA.__objc_classlist or __DATA_CONST.__objc_classlist
    public var classes32: [ObjCClass32]? {
        guard !machO.is64Bit else { return nil }
        let loadCommands = machO.loadCommands

        let __objc_classlist: any SectionProtocol

        if let data = loadCommands.data,
           let section = data.sections(in: machO).first(
            where: {
                $0.sectionName == "__objc_classlist"
            }
           ) {
            __objc_classlist = section
        } else if let dataConst = loadCommands.dataConst,
                  let section = dataConst.sections(in: machO).first(
                    where: {
                        $0.sectionName == "__objc_classlist"
                    }
                  ) {
            __objc_classlist = section
        } else {
            return nil
        }

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
                if let cache = machO.cache {
                    return cache.fileOffset(of: numericCast($0) + cache.mainCacheHeader.sharedRegionStart)
                }
                return numericCast($0)
            }
            .map {
                let layout: ObjCClass32.Layout = machO.fileHandle.read(
                    offset: $0 + numericCast(machO.headerStartOffset)
                )
                return .init(layout: layout, offset: numericCast($0))
            }
    }
}
