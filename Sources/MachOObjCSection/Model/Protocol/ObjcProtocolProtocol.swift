//
//  ObjcProtocolProtocol.swift
//
//
//  Created by p-x9 on 2024/05/27
//
//

import Foundation
@testable @_spi(Support) import MachOKit

public protocol ObjcProtocolProtocol {
    associatedtype Layout: _ObjcProtocolLayoutProtocol

    var layout: Layout { get }

    func mangledName(in machO: MachOImage) -> String

    func protocols32(in machO: MachOImage) -> ObjCProtocolList32?
    func protocols64(in machO: MachOImage) -> ObjCProtocolList64?

    func instanceMethods(in machO: MachOImage) -> ObjCMethodList?
    func classMethods(in machO: MachOImage) -> ObjCMethodList?
    func optionalInstanceMethods(in machO: MachOImage) -> ObjCMethodList?
    func optionalClassMethods(in machO: MachOImage) -> ObjCMethodList?

    func instanceProperties(in machO: MachOImage) -> ObjCPropertyList?

    var size: UInt32 { get }
    var flags: UInt32 { get }

    func extendedMethodTypes(in machO: MachOImage) -> String?
    func demangledName(in machO: MachOImage) -> String?
    func classProperties(in machO: MachOImage) -> ObjCPropertyList?
}

extension ObjcProtocolProtocol {
    public func mangledName(in machO: MachOImage) -> String {
        let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.mangledName)
        )
        return .init(cString: ptr!.assumingMemoryBound(to: CChar.self))
    }

    public func protocols32(in machO: MachOImage) -> ObjCProtocolList32? {
        guard !machO.is64Bit,
              let ptr = UnsafeRawPointer(
                bitPattern: UInt(layout.protocols)
              ) else {
            return nil
        }
        return .init(
            ptr: ptr,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr)
        )
    }

    public func protocols64(in machO: MachOImage) -> ObjCProtocolList64? {
        guard machO.is64Bit,
              let ptr = UnsafeRawPointer(
                bitPattern: UInt(layout.protocols)
              ) else {
            return nil
        }
        return .init(
            ptr: ptr,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr)
        )
    }

    public func instanceMethods(in machO: MachOImage) -> ObjCMethodList? {
        guard let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.instanceMethods)
        ) else {
            return nil
        }
        return .init(
            ptr: ptr,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr),
            is64Bit: machO.is64Bit
        )
    }

    public func classMethods(in machO: MachOImage) -> ObjCMethodList? {
        guard let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.classMethods)
        ) else {
            return nil
        }
        return .init(
            ptr: ptr,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr),
            is64Bit: machO.is64Bit
        )
    }

    public func optionalInstanceMethods(in machO: MachOImage) -> ObjCMethodList? {
        guard let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.optionalInstanceMethods)
        ) else {
            return nil
        }
        return .init(
            ptr: ptr,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr),
            is64Bit: machO.is64Bit
        )
    }

    public func optionalClassMethods(in machO: MachOImage) -> ObjCMethodList? {
        guard let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.optionalClassMethods)
        ) else {
            return nil
        }
        return .init(
            ptr: ptr,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr),
            is64Bit: machO.is64Bit
        )
    }

    public func instanceProperties(in machO: MachOImage) -> ObjCPropertyList? {
        guard let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.instanceProperties)
        ) else {
            return nil
        }
        return .init(
            ptr: ptr,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr),
            is64Bit: machO.is64Bit
        )
    }

    public var size: UInt32 { layout.size }
    public var flags: UInt32 { layout.flags }

    public func extendedMethodTypes(in machO: MachOImage) -> String? {
        let offset = machO.is64Bit ? 72 : 40
        guard size >= offset + MemoryLayout<Layout.Pointer>.size else {
            return nil
        }
        guard let _extendedMethodTypes = UnsafeRawPointer(
            bitPattern: UInt(layout._extendedMethodTypes)
        ) else {
            return nil
        }
        return .init(
            cString: _extendedMethodTypes
                .assumingMemoryBound(to: UnsafePointer<CChar>.self)
                .pointee
        )
    }

    public func demangledName(in machO: MachOImage) -> String? {
        let offset = machO.is64Bit ? 80 : 44
        guard size >= offset + MemoryLayout<Layout.Pointer>.size else {
            return nil
        }
        guard let _demangledName = UnsafeRawPointer(
            bitPattern: UInt(layout._demangledName)
        ) else {
            return nil
        }
        return .init(
            cString: _demangledName
                .assumingMemoryBound(to: CChar.self)
        )
    }

    public func classProperties(in machO: MachOImage) -> ObjCPropertyList? {
        let offset = machO.is64Bit ? 88 : 48
        guard size >= offset + MemoryLayout<Layout.Pointer>.size else {
            return nil
        }
        guard let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout._classProperties)
        ) else {
            return nil
        }
        return .init(
            ptr: ptr,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr),
            is64Bit: machO.is64Bit
        )
    }
}
