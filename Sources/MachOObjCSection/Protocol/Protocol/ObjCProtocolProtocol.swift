//
//  ObjCProtocolProtocol.swift
//
//
//  Created by p-x9 on 2024/05/27
//
//

import Foundation
@_spi(Support) import MachOKit

public protocol ObjCProtocolProtocol: _FixupResolvable where LayoutField == ObjCProtocolLayoutField {
    associatedtype Layout: _ObjCProtocolLayoutProtocol
    associatedtype ObjCProtocolList: ObjCProtocolListProtocol where ObjCProtocolList.ObjCProtocol == Self

    var layout: Layout { get }
    var offset: Int { get }

    @_spi(Core)
    init(layout: Layout, offset: Int)

    var size: UInt32 { get }
    var flags: UInt32 { get }

    func mangledName(in machO: MachOImage) -> String
    func protocolList(in machO: MachOImage) -> ObjCProtocolList?
    func instanceMethodList(in machO: MachOImage) -> ObjCMethodList?
    func classMethodList(in machO: MachOImage) -> ObjCMethodList?
    func optionalInstanceMethodList(in machO: MachOImage) -> ObjCMethodList?
    func optionalClassMethodList(in machO: MachOImage) -> ObjCMethodList?
    func instancePropertyList(in machO: MachOImage) -> ObjCPropertyList?
    func extendedMethodTypes(in machO: MachOImage) -> String?
    func demangledName(in machO: MachOImage) -> String?
    func classPropertyList(in machO: MachOImage) -> ObjCPropertyList?

    func mangledName(in machO: MachOFile) -> String
    func protocolList(in machO: MachOFile) -> ObjCProtocolList?
    func instanceMethodList(in machO: MachOFile) -> ObjCMethodList?
    func classMethodList(in machO: MachOFile) -> ObjCMethodList?
    func optionalInstanceMethodList(in machO: MachOFile) -> ObjCMethodList?
    func optionalClassMethodList(in machO: MachOFile) -> ObjCMethodList?
    func instancePropertyList(in machO: MachOFile) -> ObjCPropertyList?
    func extendedMethodTypes(in machO: MachOFile) -> String?
    func demangledName(in machO: MachOFile) -> String?
    func classPropertyList(in machO: MachOFile) -> ObjCPropertyList?
}

extension ObjCProtocolProtocol {
    public var size: UInt32 { layout.size }
    public var flags: UInt32 { layout.flags }
}

extension ObjCProtocolProtocol {
    public func mangledName(in machO: MachOImage) -> String {
        let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.mangledName)
        )
        return .init(cString: ptr!.assumingMemoryBound(to: CChar.self))
    }

    public func protocolList(in machO: MachOImage) -> ObjCProtocolList? {
        guard let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.protocols)
        ) else {
            return nil
        }
        return .init(
            ptr: ptr,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr)
        )
    }

    public func instanceMethodList(in machO: MachOImage) -> ObjCMethodList? {
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

    public func classMethodList(in machO: MachOImage) -> ObjCMethodList? {
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

    public func optionalInstanceMethodList(in machO: MachOImage) -> ObjCMethodList? {
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

    public func optionalClassMethodList(in machO: MachOImage) -> ObjCMethodList? {
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

    public func instancePropertyList(in machO: MachOImage) -> ObjCPropertyList? {
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

    public func classPropertyList(in machO: MachOImage) -> ObjCPropertyList? {
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

extension ObjCProtocolProtocol {
    public func mangledName(in machO: MachOFile) -> String {
        let headerStartOffset = machO.headerStartOffset/* + machO.headerStartOffsetInCache*/

        var offset: UInt64 = machO.fileOffset(
            of: numericCast(layout.mangledName)
        )  + numericCast(headerStartOffset)

        var fileHandle = machO.fileHandle

        if let (_cache, _offset) = machO.cacheAndFileOffset(
            fromStart: offset
        ) {
            offset = _offset
            fileHandle = _cache.fileHandle
        }

        return fileHandle.readString(
            offset: offset
        ) ?? ""
    }

    public func protocolList(in machO: MachOFile) -> ObjCProtocolList? {
        guard layout.protocols > 0 else { return nil }

        let headerStartOffset = machO.headerStartOffset

        var offset: UInt64 = machO.fileOffset(
            of: numericCast(layout.protocols)
        ) + numericCast(headerStartOffset)

        if let resolved = resolveRebase(.protocols, in: machO),
            resolved != offset {
            offset = machO.fileOffset(of: resolved) + numericCast(machO.headerStartOffset)
        }
//        if isBind(\.protocols, in: machO) { return nil }

        var resolvedOffset = offset

        var fileHandle = machO.fileHandle

        if let (_cache, _offset) = machO.cacheAndFileOffset(
            fromStart: offset
        ) {
            resolvedOffset = _offset
            fileHandle = _cache.fileHandle
        }

        let data = fileHandle.readData(
            offset: resolvedOffset,
            size: MemoryLayout<ObjCProtocolList64.Header>.size
        )
        return data.withUnsafeBytes {
            guard let baseAddress = $0.baseAddress else { return nil }
            return .init(
                ptr: baseAddress,
                offset: numericCast(offset) - machO.headerStartOffset
            )
        }
    }

    public func instanceMethodList(in machO: MachOFile) -> ObjCMethodList? {
        _readObjCMethodList(in: machO, offset: numericCast(layout.instanceMethods))
    }

    public func classMethodList(in machO: MachOFile) -> ObjCMethodList? {
        _readObjCMethodList(in: machO, offset: numericCast(layout.classMethods))
    }

    public func optionalInstanceMethodList(in machO: MachOFile) -> ObjCMethodList? {
        _readObjCMethodList(
            in: machO,
            offset: numericCast(layout.optionalInstanceMethods)
        )
    }

    public func optionalClassMethodList(in machO: MachOFile) -> ObjCMethodList? {
        _readObjCMethodList(
            in: machO,
            offset: numericCast(layout.optionalClassMethods)
        )
    }

    public func instancePropertyList(in machO: MachOFile) -> ObjCPropertyList? {
        _readObjCPropertyList(
            in: machO,
            offset: numericCast(layout.instanceProperties)
        )
    }

    public func extendedMethodTypes(in machO: MachOFile) -> String? {
        let offset = layoutOffset(of: ._extendedMethodTypes)
        guard size >= offset + MemoryLayout<Layout.Pointer>.size else {
            return nil
        }
        guard layout._extendedMethodTypes > 0 else { return nil }
        let headerStartOffset = machO.headerStartOffset/* + machO.headerStartOffsetInCache*/

        let _extendedMethodTypes = machO.fileOffset(
            of: UInt64(layout._extendedMethodTypes)
        )
        if machO.is64Bit {
            var offset = UInt64(_extendedMethodTypes)

            var fileHandle = machO.fileHandle

            if let (_cache, _offset) = machO.cacheAndFileOffset(
                fromStart: offset
            ) {
                offset = _offset
                fileHandle = _cache.fileHandle
            }

            offset = fileHandle.read(
                offset: numericCast(headerStartOffset) + numericCast(offset)
            )
            offset = machO.fileOffset(of: offset)

            if let (_cache, _offset) = machO.cacheAndFileOffset(
                fromStart: offset
            ) {
                offset = _offset
                fileHandle = _cache.fileHandle
            }

            return machO.fileHandle.readString(
                offset: numericCast(headerStartOffset) + numericCast(offset)
            )
        } else {
            var offset = UInt64(_extendedMethodTypes)

            var fileHandle = machO.fileHandle

            if let (_cache, _offset) = machO.cacheAndFileOffset(
                fromStart: offset
            ) {
                offset = _offset
                fileHandle = _cache.fileHandle
            }

            let _offset: UInt32 = fileHandle.read(
                offset: numericCast(headerStartOffset) + offset
            )
            offset = numericCast(_offset)

            if let (_cache, _offset) = machO.cacheAndFileOffset(
                fromStart: offset
            ) {
                offset = _offset
                fileHandle = _cache.fileHandle
            }

            return fileHandle.readString(
                offset: numericCast(headerStartOffset) + numericCast(offset)
            )
        }
    }

    public func demangledName(in machO: MachOFile) -> String? {
        let offset = layoutOffset(of: ._demangledName)
        guard size >= offset + MemoryLayout<Layout.Pointer>.size else {
            return nil
        }
        guard layout._demangledName > 0 else { return nil }
        let headerStartOffset = machO.headerStartOffset/* + machO.headerStartOffsetInCache*/

        var _demangledName = machO.fileOffset(
            of: numericCast(layout._demangledName)
        )

        var fileHandle = machO.fileHandle

        if let (_cache, _offset) = machO.cacheAndFileOffset(
            fromStart: numericCast(_demangledName)
        ) {
            _demangledName = numericCast(_offset)
            fileHandle = _cache.fileHandle
        }

        return fileHandle.readString(
            offset: numericCast(headerStartOffset) + numericCast(_demangledName)
        )
    }

    public func classPropertyList(in machO: MachOFile) -> ObjCPropertyList? {
        let offset = layoutOffset(of: ._classProperties)
        guard size >= offset + MemoryLayout<Layout.Pointer>.size else {
            return nil
        }
        guard layout._classProperties > 0 else { return nil }
        return _readObjCPropertyList(
            in: machO,
            offset: numericCast(layout._classProperties)
        )
    }
}

extension ObjCProtocolProtocol {
    fileprivate func _readObjCMethodList(
        in machO: MachOFile,
        offset: UInt64
    ) -> ObjCMethodList? {
        guard offset > 0 else { return nil }

        let headerStartOffset = machO.headerStartOffset /*+ machO.headerStartOffsetInCache*/
        let offset = machO.fileOffset(of: offset)
        var resolvedOffset = offset

        var fileHandle = machO.fileHandle

        if let (_cache, _offset) = machO.cacheAndFileOffset(
            fromStart: offset
        ) {
            resolvedOffset = _offset
            fileHandle = _cache.fileHandle
        }

        let data = fileHandle.readData(
            offset: numericCast(headerStartOffset) + numericCast(resolvedOffset),
            size: MemoryLayout<ObjCMethodList.Header>.size
        )
        return data.withUnsafeBytes {
            guard let baseAddress = $0.baseAddress else { return nil }
            return .init(
                ptr: baseAddress,
                offset: numericCast(offset),
                is64Bit: machO.is64Bit
            )
        }
    }

    fileprivate func _readObjCPropertyList(
        in machO: MachOFile,
        offset: UInt64
    ) -> ObjCPropertyList? {
        guard offset > 0 else { return nil }

        let headerStartOffset = machO.headerStartOffset/* + machO.headerStartOffsetInCache*/
        let offset = machO.fileOffset(of: offset)
        var resolvedOffset = offset

        var fileHandle = machO.fileHandle

        if let (_cache, _offset) = machO.cacheAndFileOffset(
            fromStart: offset
        ) {
            resolvedOffset = _offset
            fileHandle = _cache.fileHandle
        }

        let data = fileHandle.readData(
            offset: numericCast(headerStartOffset) + numericCast(resolvedOffset),
            size: MemoryLayout<ObjCPropertyList.Header>.size
        )
        return data.withUnsafeBytes {
            guard let baseAddress = $0.baseAddress else { return nil }
            return .init(
                ptr: baseAddress,
                offset: numericCast(offset),
                is64Bit: machO.is64Bit
            )
        }
    }
}
