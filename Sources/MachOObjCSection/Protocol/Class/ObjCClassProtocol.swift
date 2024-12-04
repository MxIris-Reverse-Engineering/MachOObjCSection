//
//  ObjCClassProtocol.swift
//
//
//  Created by p-x9 on 2024/08/06
//  
//

import Foundation
@_spi(Support) import MachOKit
import MachOObjCSectionC

public protocol ObjCClassProtocol: _FixupResolvable where LayoutField == ObjCClassLayoutField {
    associatedtype Layout: _ObjCClassLayoutProtocol
    associatedtype ClassROData: LayoutWrapper, ObjCClassRODataProtocol where ClassROData.Layout.Pointer == Layout.Pointer
    associatedtype ClassRWData: LayoutWrapper, ObjCClassRWDataProtocol where ClassRWData.Layout.Pointer == Layout.Pointer

    var layout: Layout { get }
    var offset: Int { get }

    @_spi(Core)
    init(layout: Layout, offset: Int)

    func metaClass(in machO: MachOFile) -> Self?
    func superClass(in machO: MachOFile) -> Self?
    func superClassName(in machO: MachOFile) -> String?
    func classROData(in machO: MachOFile) -> ClassROData?

    func hasRWPointer(in machO: MachOImage) -> Bool

    func metaClass(in machO: MachOImage) -> Self?
    func superClass(in machO: MachOImage) -> Self?
    func superClassName(in machO: MachOImage) -> String?
    func classROData(in machO: MachOImage) -> ClassROData?
    func classRWData(in machO: MachOImage) -> ClassRWData?

    func version(in machO: MachOFile) -> Int32
    func version(in machO: MachOImage) -> Int32
}

extension ObjCClassProtocol {
    /// class is a Swift class from the pre-stable Swift ABI
    public var isSwiftLegacy: Bool {
        layout.dataVMAddrAndFastFlags & numericCast(FAST_IS_SWIFT_LEGACY) != 0
    }

    /// class is a Swift class from the stable Swift ABI
    public var isSwiftStable: Bool {
        layout.dataVMAddrAndFastFlags & numericCast(FAST_IS_SWIFT_STABLE) != 0
    }

    public var isSwift: Bool {
        isSwiftStable || isSwiftLegacy
    }
}

extension ObjCClassProtocol {
    public func metaClass(in machO: MachOFile) -> Self? {
        _readClass(
            at: numericCast(layout.isa),
            field: .isa,
            in: machO
        )
    }

    public func superClass(in machO: MachOFile) -> Self? {
        _readClass(
            at: numericCast(layout.superclass),
            field: .superclass,
            in: machO
        )
    }

    public func superClassName(in machO: MachOFile) -> String? {
        _readClassName(
            at: numericCast(layout.superclass),
            field: .superclass,
            in: machO
        )
    }
}

extension ObjCClassProtocol {
    public func metaClass(in machO: MachOImage) -> Self? {
        guard layout.isa > 0 else { return nil }
        guard let ptr = UnsafeRawPointer(bitPattern: UInt(layout.isa)) else {
            return nil
        }
        let layout = ptr.assumingMemoryBound(to: Layout.self).pointee
        let offset: Int = numericCast(layout.isa) - Int(bitPattern: machO.ptr)
        return .init(layout: layout, offset: offset)
    }

    public func superClass(in machO: MachOImage) -> Self? {
        guard layout.superclass > 0 else { return nil }
        guard let ptr = UnsafeRawPointer(bitPattern: UInt(layout.superclass)) else {
            return nil
        }
        let layout = ptr.assumingMemoryBound(to: Layout.self).pointee
        let offset: Int = numericCast(layout.superclass) - Int(bitPattern: machO.ptr)
        return .init(layout: layout, offset: offset)
    }

    public func superClassName(in machO: MachOImage) -> String? {
        guard let superCls = superClass(in: machO),
              let data = superCls.classROData(in: machO) else {
            return nil
        }
        return data.name(in: machO)
    }
}

extension ObjCClassProtocol {
    private func _readClass(
        at offset: UInt64,
        field: LayoutField,
        in machO: MachOFile
    ) -> Self? {
        guard offset > 0 else { return nil }
        var offset: UInt64 = numericCast(offset) & 0x7ffffffff + numericCast(machO.headerStartOffset)

        if let resolved = resolveRebase(field, in: machO) {
            offset = resolved & 0x7ffffffff + numericCast(machO.headerStartOffset)
        }
        if isBind(field, in: machO) { return nil }

        var resolvedOffset = offset
        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.mainCacheHeader.sharedRegionStart) else {
                return nil
            }
            resolvedOffset = _offset
        }

        let layout: Layout = machO.fileHandle.read(offset: resolvedOffset)
        return .init(layout: layout, offset: numericCast(offset))
    }

    private func _readClassName(
        at offset: UInt64,
        field: LayoutField,
        in machO: MachOFile
    ) -> String? {
        guard offset > 0 else { return nil }

        if let cls = _readClass(
            at: offset,
            field: field,
            in: machO
        ), let data = cls.classROData(in: machO) {
            return data.name(in: machO)
        }

        if let bindSymbolName = resolveBind(field, in: machO) {
            return bindSymbolName
                .replacingOccurrences(of: "_OBJC_CLASS_$_", with: "")
        }

        return nil
    }
}
