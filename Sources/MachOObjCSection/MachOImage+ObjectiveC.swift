//
//  MachOImage+ObjectiveC.swift
//
//
//  Created by p-x9 on 2024/08/03
//  
//

import Foundation
@_spi(Support) import MachOKit

extension MachOImage {
    public struct ObjectiveC {
        private let machO: MachOImage

        init(machO: MachOImage) {
            self.machO = machO
        }
    }

    public var objc: ObjectiveC  {
        .init(machO: self)
    }
}

extension MachOImage.ObjectiveC {
    /// __DATA.__objc_imageinfo or __DATA_CONST.__objc_imageinfo
    public var imageInfo: ObjCImageInfo? {
        let loadCommands = machO.loadCommands

        guard let vmaddrSlide = machO.vmaddrSlide else { return nil }

        let segment: any SegmentCommandProtocol
        let __objc_imageinfo: any SectionProtocol

        if let data = loadCommands.data64,
           let section = data.sections(cmdsStart: machO.cmdsStartPtr).first(
            where: {
                $0.sectionName == "__objc_imageinfo"
            }
           ) {
            segment = data
            __objc_imageinfo = section
        } else if let dataConst = loadCommands.dataConst64,
                  let section = dataConst.sections(cmdsStart: machO.cmdsStartPtr).first(
                    where: {
                        $0.sectionName == "__objc_imageinfo"
                    }
                  ) {
            segment = dataConst
            __objc_imageinfo = section
        } else if let data = loadCommands.data,
                  let section = data.sections(cmdsStart: machO.cmdsStartPtr).first(
                    where: {
                        $0.sectionName == "__objc_imageinfo"
                    }
                  ) {
            segment = data
            __objc_imageinfo = section
        } else if let dataConst = loadCommands.dataConst,
                  let section = dataConst.sections(cmdsStart: machO.cmdsStartPtr).first(
                    where: {
                        $0.sectionName == "__objc_imageinfo"
                    }
                  ) {
            segment = dataConst
            __objc_imageinfo = section
        } else {
            return nil
        }

        guard let start = __objc_imageinfo.startPtr(
            in: segment,
            vmaddrSlide: vmaddrSlide
        ) else { return nil }

        return start
            .assumingMemoryBound(to: ObjCImageInfo.self)
            .pointee
    }
}

extension MachOImage.ObjectiveC {
    /// __TEXT.__objc_methlist
    public var methods: MachOImage.ObjCMethodLists? {
        let loadCommands = machO.loadCommands

        guard let vmaddrSlide = machO.vmaddrSlide else { return nil }

        let text: any SegmentCommandProtocol
        let __objc_methlist: any SectionProtocol
        if let _text = loadCommands.text64,
           let section = _text.sections(cmdsStart: machO.cmdsStartPtr).first(
            where: {
                $0.sectionName == "__objc_methlist"
            }
           ) {
            text = _text
            __objc_methlist = section
        } else if let _text = loadCommands.text,
                  let section = _text.sections(cmdsStart: machO.cmdsStartPtr).first(
                    where: {
                        $0.sectionName == "__objc_methlist"
                    }
                  ) {
            text = _text
            __objc_methlist = section
        } else {
            return nil
        }

        guard let start = __objc_methlist.startPtr(
            in: text,
            vmaddrSlide: vmaddrSlide
        ) else { return nil }

        return .init(
            offset: Int(bitPattern: start) - Int(bitPattern: machO.ptr),
            basePointer: start,
            tableSize: __objc_methlist.size,
            align: __objc_methlist.align,
            is64Bit: machO.is64Bit
        )
    }
}

extension MachOImage.ObjectiveC {
    /// __DATA.__objc_protolist or __DATA_CONST.__objc_protolist
    public var protocols64: [ObjCProtocol64]? {
        guard machO.is64Bit else { return nil }
        guard let vmaddrSlide = machO.vmaddrSlide else { return nil }
        let loadCommands = machO.loadCommands

        let segment: any SegmentCommandProtocol
        let __objc_protolist: any SectionProtocol

        if let data = loadCommands.data64,
           let section = data.sections(cmdsStart: machO.cmdsStartPtr).first(
            where: {
                $0.sectionName == "__objc_protolist"
            }
           ) {
            segment = data
            __objc_protolist = section
        } else if let dataConst = loadCommands.dataConst64,
                  let section = dataConst.sections(cmdsStart: machO.cmdsStartPtr).first(
                    where: {
                        $0.sectionName == "__objc_protolist"
                    }
                  ) {
            segment = dataConst
            __objc_protolist = section
        } else {
            return nil
        }

        guard let start = __objc_protolist.startPtr(
            in: segment,
            vmaddrSlide: vmaddrSlide
        ) else { return nil }

        let offsets: MemorySequence<UInt64> = .init(
            basePointer: start.assumingMemoryBound(to: UInt64.self),
            numberOfElements: __objc_protolist.size / 8
        )

        return offsets
            .compactMap { UnsafeRawPointer(bitPattern: UInt($0)) }
            .map {
                $0.assumingMemoryBound(to: ObjCProtocol64.self).pointee
            }
    }

    public var protocols32: [ObjCProtocol32]? {
        guard !machO.is64Bit else { return nil }
        guard let vmaddrSlide = machO.vmaddrSlide else { return nil }
        let loadCommands = machO.loadCommands

        let segment: any SegmentCommandProtocol
        let __objc_protolist: any SectionProtocol

        if let data = loadCommands.data,
           let section = data.sections(cmdsStart: machO.cmdsStartPtr).first(
            where: {
                $0.sectionName == "__objc_protolist"
            }
           ) {
            segment = data
            __objc_protolist = section
        } else if let dataConst = loadCommands.dataConst,
                  let section = dataConst.sections(cmdsStart: machO.cmdsStartPtr).first(
                    where: {
                        $0.sectionName == "__objc_protolist"
                    }
                  ) {
            segment = dataConst
            __objc_protolist = section
        } else {
            return nil
        }

        guard let start = __objc_protolist.startPtr(
            in: segment,
            vmaddrSlide: vmaddrSlide
        ) else { return nil }

        let offsets: MemorySequence<UInt32> = .init(
            basePointer: start.assumingMemoryBound(to: UInt32.self),
            numberOfElements: __objc_protolist.size / 4
        )

        return offsets
            .compactMap { UnsafeRawPointer(bitPattern: UInt($0)) }
            .map {
                $0.assumingMemoryBound(to: ObjCProtocol32.self).pointee
            }
    }
}
