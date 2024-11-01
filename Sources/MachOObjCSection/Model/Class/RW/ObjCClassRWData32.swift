//
//  ObjCClassRWData32.swift
//
//
//  Created by p-x9 on 2024/10/31
//  
//

import Foundation
import MachOKit

// https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L2313
public struct ObjCClassRWData32: LayoutWrapper, ObjCClassRWDataProtocol {
    public typealias Pointer = UInt32
    public typealias ObjCClassROData = ObjCClassROData32
    public typealias ObjCClassRWDataExt = ObjCClassRWDataExt32

    public struct Layout: _ObjCClassRWDataLayoutProtocol {
        public let flags: UInt32
        public let witness: UInt16
        public let index: UInt16
        public let ro_or_rw_ext: Pointer

        public let firstSubclass: Pointer
        public let nextSiblingClass: Pointer
    }

    public var layout: Layout
    public var offset: Int
}

extension ObjCClassRWData32 {
    public func classROData(in machO: MachOImage) -> ObjCClassROData? {
        guard hasRO else { return nil }

        let address: Int = numericCast(layout.ro_or_rw_ext)
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

    public func ext(in machO: MachOImage) -> ObjCClassRWDataExt? {
        guard hasExt else { return nil }

        let address: Int = numericCast(layout.ro_or_rw_ext)
        guard let ptr = UnsafeRawPointer(bitPattern: address & ~1) else {
            return nil
        }
        let layout = ptr
            .assumingMemoryBound(to: ObjCClassRWDataExt.Layout.self)
            .pointee
        let classData = ObjCClassRWDataExt(
            layout: layout,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr)
        )

        return classData
    }
}
