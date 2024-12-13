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
    public struct ObjectiveC: ObjCSectionRepresentable {
        private let machO: MachOImage

        init(machO: MachOImage) {
            self.machO = machO
        }
    }

    public var objc: ObjectiveC {
        .init(machO: self)
    }
}

extension MachOImage.ObjectiveC {
    /// `__DATA.__objc_imageinfo` or `__DATA_CONST.__objc_imageinfo`
    public var imageInfo: ObjCImageInfo? {
        guard let vmaddrSlide = machO.vmaddrSlide else { return nil }

        let segment: any SegmentCommandProtocol
        let __objc_imageinfo: any SectionProtocol

        if machO.is64Bit,
           let section = machO.findObjCSection64(for: .__objc_imageinfo) {
            __objc_imageinfo = section
        } else if let section = machO.findObjCSection32(for: .__objc_imageinfo) {
            __objc_imageinfo = section
        } else {
            return nil
        }

        guard let start = UnsafeRawPointer(
            bitPattern: __objc_imageinfo.address + vmaddrSlide
        ) else { return nil }

        return start
            .assumingMemoryBound(to: ObjCImageInfo.self)
            .pointee
    }
}

extension MachOImage.ObjectiveC {
    /// `__TEXT.__objc_methlist`
    public var methods: MachOImage.ObjCMethodLists? {
        let loadCommands = machO.loadCommands

        guard let vmaddrSlide = machO.vmaddrSlide else { return nil }

        let __objc_methlist: any SectionProtocol
        if let _text = loadCommands.text64,
           let section = _text.__objc_methlist(in: machO) {
            __objc_methlist = section
        } else if let _text = loadCommands.text,
                  let section = _text.__objc_methlist(in: machO) {
            __objc_methlist = section
        } else {
            return nil
        }

        guard let start = UnsafeRawPointer(
            bitPattern: __objc_methlist.address + vmaddrSlide
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
    /// `__DATA.__objc_protolist` or `__DATA_CONST.__objc_protolist`
    public var protocols64: [ObjCProtocol64]? {
        guard machO.is64Bit else { return nil }
        guard let vmaddrSlide = machO.vmaddrSlide else { return nil }

        guard let __objc_protolist = machO.findObjCSection64(
            for: .__objc_protolist
        ) else { return nil }

        guard let start = UnsafeRawPointer(
            bitPattern: __objc_protolist.address + vmaddrSlide
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

    /// `__DATA.__objc_protolist` or `__DATA_CONST.__objc_protolist`
    public var protocols32: [ObjCProtocol32]? {
        guard !machO.is64Bit else { return nil }
        guard let vmaddrSlide = machO.vmaddrSlide else { return nil }

        guard let __objc_protolist = machO.findObjCSection32(
            for: .__objc_protolist
        ) else { return nil }

        guard let start = UnsafeRawPointer(
            bitPattern: __objc_protolist.address + vmaddrSlide
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

extension MachOImage.ObjectiveC {
    /// `__DATA.__objc_classlist` or `__DATA_CONST.__objc_classlist`
    public var classes64: [ObjCClass64]? {
        guard machO.is64Bit else { return nil }
        guard let vmaddrSlide = machO.vmaddrSlide else { return nil }

        guard let __objc_classlist = machO.findObjCSection64(
            for: .__objc_classlist
        ) else { return nil }

        guard let start = UnsafeRawPointer(
            bitPattern: __objc_classlist.address + vmaddrSlide
        ) else { return nil }

        let offsets: MemorySequence<UInt64> = .init(
            basePointer: start.assumingMemoryBound(to: UInt64.self),
            numberOfElements: __objc_classlist.size / 8
        )
        return offsets
            .compactMap {
                let offset = $0 - numericCast(UInt(bitPattern: machO.ptr))
                guard let ptr = UnsafeRawPointer(bitPattern: UInt($0)) else {
                    return nil
                }
                let layout = ptr
                    .assumingMemoryBound(to: ObjCClass64.Layout.self)
                    .pointee
                return .init(layout: layout, offset: numericCast(offset))
            }
    }

    /// `__DATA.__objc_classlist` or `__DATA_CONST.__objc_classlist`
    public var classes32: [ObjCClass32]? {
        guard !machO.is64Bit else { return nil }
        guard let vmaddrSlide = machO.vmaddrSlide else { return nil }

        guard let __objc_classlist = machO.findObjCSection32(
            for: .__objc_classlist
        ) else { return nil }

        guard let start = UnsafeRawPointer(
            bitPattern: __objc_classlist.address + vmaddrSlide
        ) else { return nil }

        let offsets: MemorySequence<UInt32> = .init(
            basePointer: start.assumingMemoryBound(to: UInt32.self),
            numberOfElements: __objc_classlist.size / 4
        )
        return offsets
            .compactMap {
                let offset = $0 - numericCast(UInt(bitPattern: machO.ptr))
                guard let ptr = UnsafeRawPointer(bitPattern: UInt($0)) else {
                    return nil
                }
                let layout = ptr
                    .assumingMemoryBound(to: ObjCClass32.Layout.self)
                    .pointee
                return .init(layout: layout, offset: numericCast(offset))
            }
    }
}

extension MachOImage.ObjectiveC {
    /// `__DATA.__objc_classlist` or `__DATA_CONST.__objc_classlist`
    public var categories64: [ObjCCategory64]? {
        guard machO.is64Bit else { return nil }
        guard let vmaddrSlide = machO.vmaddrSlide else { return nil }

        guard let __objc_catlist = machO.findObjCSection64(
            for: .__objc_catlist
        ) else { return nil }

        guard let start = UnsafeRawPointer(
            bitPattern: __objc_catlist.address + vmaddrSlide
        ) else { return nil }

        let offsets: MemorySequence<UInt64> = .init(
            basePointer: start.assumingMemoryBound(to: UInt64.self),
            numberOfElements: __objc_catlist.size / 8
        )

        return offsets
            .compactMap {
                let offset = $0 - numericCast(UInt(bitPattern: machO.ptr))
                guard let ptr = UnsafeRawPointer(bitPattern: UInt($0)) else {
                    return nil
                }
                let layout = ptr
                    .assumingMemoryBound(to: ObjCCategory64.Layout.self)
                    .pointee
                return .init(
                    layout: layout,
                    offset: numericCast(offset),
                    isCatlist2: false
                )
            }
    }

    /// `__DATA.__objc_classlist` or `__DATA_CONST.__objc_classlist`
    public var categories32: [ObjCCategory32]? {
        guard !machO.is64Bit else { return nil }
        guard let vmaddrSlide = machO.vmaddrSlide else { return nil }

        guard let __objc_catlist = machO.findObjCSection32(
            for: .__objc_catlist
        ) else { return nil }

        guard let start = UnsafeRawPointer(
            bitPattern: __objc_catlist.address + vmaddrSlide
        ) else { return nil }

        let offsets: MemorySequence<UInt32> = .init(
            basePointer: start.assumingMemoryBound(to: UInt32.self),
            numberOfElements: __objc_catlist.size / 4
        )
        return offsets
            .compactMap {
                let offset = $0 - numericCast(UInt(bitPattern: machO.ptr))
                guard let ptr = UnsafeRawPointer(bitPattern: UInt($0)) else {
                    return nil
                }
                let layout = ptr
                    .assumingMemoryBound(to: ObjCCategory32.Layout.self)
                    .pointee
                return .init(
                    layout: layout,
                    offset: numericCast(offset),
                    isCatlist2: false
                )
            }
    }
}

extension MachOImage.ObjectiveC {
    /// `__DATA.__objc_classlist2` or `__DATA_CONST.__objc_classlist2`
    public var categories2_64: [ObjCCategory64]? {
        guard machO.is64Bit else { return nil }
        guard let vmaddrSlide = machO.vmaddrSlide else { return nil }

        guard let __objc_catlist = machO.findObjCSection64(
            for: .__objc_catlist2
        ) else { return nil }

        guard let start = UnsafeRawPointer(
            bitPattern: __objc_catlist.address + vmaddrSlide
        ) else { return nil }

        let offsets: MemorySequence<UInt64> = .init(
            basePointer: start.assumingMemoryBound(to: UInt64.self),
            numberOfElements: __objc_catlist.size / 8
        )
        return offsets
            .compactMap {
                let offset = $0 - numericCast(UInt(bitPattern: machO.ptr))
                guard let ptr = UnsafeRawPointer(bitPattern: UInt($0)) else {
                    return nil
                }
                let layout = ptr
                    .assumingMemoryBound(to: ObjCCategory64.Layout.self)
                    .pointee
                return .init(
                    layout: layout,
                    offset: numericCast(offset),
                    isCatlist2: true
                )
            }
    }

    /// `__DATA.__objc_classlist` or `__DATA_CONST.__objc_classlist`
    public var categories2_32: [ObjCCategory32]? {
        guard !machO.is64Bit else { return nil }
        guard let vmaddrSlide = machO.vmaddrSlide else { return nil }

        guard let __objc_catlist = machO.findObjCSection32(
            for: .__objc_catlist2
        ) else { return nil }

        guard let start = UnsafeRawPointer(
            bitPattern: __objc_catlist.address + vmaddrSlide
        ) else { return nil }

        let offsets: MemorySequence<UInt32> = .init(
            basePointer: start.assumingMemoryBound(to: UInt32.self),
            numberOfElements: __objc_catlist.size / 4
        )
        return offsets
            .compactMap {
                let offset = $0 - numericCast(UInt(bitPattern: machO.ptr))
                guard let ptr = UnsafeRawPointer(bitPattern: UInt($0)) else {
                    return nil
                }
                let layout = ptr
                    .assumingMemoryBound(to: ObjCCategory32.Layout.self)
                    .pointee
                return .init(
                    layout: layout,
                    offset: numericCast(offset),
                    isCatlist2: true
                )
            }
    }
}
