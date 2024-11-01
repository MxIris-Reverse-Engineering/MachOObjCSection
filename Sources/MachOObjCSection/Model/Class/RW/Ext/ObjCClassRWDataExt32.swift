//
//  ObjCClassRWDataExt32.swift
//
//
//  Created by p-x9 on 2024/10/31
//
//

import Foundation
import MachOKit

public struct ObjCClassRWDataExt32: LayoutWrapper, ObjCClassRWDataExtProtocol {
    public typealias Pointer = UInt32
    public typealias ObjCClassROData = ObjCClassROData32
    public typealias ObjCProtocolArray = ObjCProtocolArray32

    public struct Layout: _ObjCClassRWDataExtLayoutProtocol {
        public let ro: Pointer
        public let methods: Pointer
        public let properties: Pointer
        public let protocols: Pointer

        public let demangledName: Pointer
        public let version: UInt32
    }

    public var layout: Layout
    public var offset: Int
}

extension ObjCClassRWDataExt32 {
    public func classROData(in machO: MachOImage) -> ObjCClassROData? {
        let address: Int = numericCast(layout.ro)
        guard let ptr = UnsafeRawPointer(bitPattern: address) else {
            return nil
        }
        let layout = ptr
            .assumingMemoryBound(to: ObjCClassROData.Layout.self)
            .pointee
        let classData = ObjCClassROData(
            layout: layout,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr)
        )

        return classData
    }

    public func methods(in machO: MachOImage) -> ObjCMethodArray? {
        guard layout.methods > 0 else { return nil }
        guard let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.methods)
        ) else {
            return nil
        }

        let lists = ObjCMethodArray(
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr),
            is64Bit: machO.is64Bit
        )

        return lists
    }

    public func properties(in machO: MachOImage) -> ObjCPropertyArray? {
        guard layout.properties > 0 else { return nil }
        guard let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.properties)
        ) else {
            return nil
        }
        let lists = ObjCPropertyArray(
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr),
            is64Bit: machO.is64Bit
        )
        return lists
    }

    public func protocols(in machO: MachOImage) -> ObjCProtocolArray? {
        guard layout.protocols > 0 else { return nil }
        guard let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.protocols)
        ) else {
            return nil
        }
        let lists = ObjCProtocolArray(
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr)
        )

        return lists
    }


    public func demangledName(in machO: MachOImage) -> String? {
        guard layout.demangledName > 0 else { return nil }
        guard let ptr = UnsafeRawPointer(bitPattern: UInt(layout.demangledName)) else {
            return nil
        }
        return .init(
            cString: ptr.assumingMemoryBound(to: CChar.self),
            encoding: .utf8
        )
    }
}
