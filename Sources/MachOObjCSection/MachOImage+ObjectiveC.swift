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
    public var imageInfo: ObjCImageInfo? {
        guard let vmaddrSlide = machO.vmaddrSlide else { return nil }

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

extension MachOImage.ObjectiveC {
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

// MARK: - Category
extension MachOImage.ObjectiveC {
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
}

extension MachOImage.ObjectiveC {
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

extension MachOImage.ObjectiveC {
    func _readCategories<
        Categgory: ObjCCategoryProtocol
    >(
        from section: any SectionProtocol,
        in machO: MachOImage,
        isCatlist2: Bool = false
    ) -> [Categgory]? {
        guard let vmaddrSlide = machO.vmaddrSlide else { return nil }

        guard let start = UnsafeRawPointer(
            bitPattern: section.address + vmaddrSlide
        ) else { return nil }

        typealias Pointer = Categgory.Layout.Pointer
        let pointerSize: Int = MemoryLayout<Pointer>.size
        let offsets: MemorySequence<Pointer> = .init(
            basePointer: start.assumingMemoryBound(to: Pointer.self),
            numberOfElements: section.size / pointerSize
        )
        return offsets
            .compactMap {
                let offset = $0 - numericCast(UInt(bitPattern: machO.ptr))
                guard let ptr = UnsafeRawPointer(bitPattern: UInt($0)) else {
                    return nil
                }
                let layout = ptr
                    .assumingMemoryBound(to: Categgory.Layout.self)
                    .pointee
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
        in machO: MachOImage
    ) -> [Class]? {
        guard let vmaddrSlide = machO.vmaddrSlide else { return nil }
        guard let start = UnsafeRawPointer(
            bitPattern: section.address + vmaddrSlide
        ) else { return nil }

        typealias Pointer = Class.Layout.Pointer
        let pointerSize: Int = MemoryLayout<Pointer>.size
        let offsets: MemorySequence<Pointer> = .init(
            basePointer: start.assumingMemoryBound(to: Pointer.self),
            numberOfElements: section.size / pointerSize
        )
        return offsets
            .compactMap {
                let offset = $0 - numericCast(UInt(bitPattern: machO.ptr))
                guard let ptr = UnsafeRawPointer(bitPattern: UInt($0)) else {
                    return nil
                }
                let layout = ptr
                    .assumingMemoryBound(to: Class.Layout.self)
                    .pointee
                return .init(layout: layout, offset: numericCast(offset))
            }
    }

    func _readProtocols<
        Protocol: ObjCProtocolProtocol
    >(
        from section: any SectionProtocol,
        in machO: MachOImage
    ) -> [Protocol]? {
        guard let vmaddrSlide = machO.vmaddrSlide else { return nil }
        guard let start = UnsafeRawPointer(
            bitPattern: section.address + vmaddrSlide
        ) else { return nil }

        typealias Pointer = Protocol.Layout.Pointer
        let pointerSize: Int = MemoryLayout<Pointer>.size
        let offsets: MemorySequence<Pointer> = .init(
            basePointer: start.assumingMemoryBound(to: Pointer.self),
            numberOfElements: section.size / pointerSize
        )

        return offsets
            .compactMap { UnsafeRawPointer(bitPattern: UInt($0)) }
            .map {
                $0.assumingMemoryBound(to: Protocol.self).pointee
            }
    }
}
