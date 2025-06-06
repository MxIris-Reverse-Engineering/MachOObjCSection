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
    associatedtype ClassRWData: LayoutWrapper, ObjCClassRWDataProtocol where ClassRWData.Layout.Pointer == Layout.Pointer, ClassRWData.ObjCClassROData == ClassROData

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
    // https://github.com/apple-oss-distributions/objc4/blob/89543e2c0f67d38ca5211cea33f42c51500287d5/runtime/objc-runtime-new.h#L2998C10-L2998C21
    // https://github.com/swiftlang/swift/blob/main/docs/ObjCInterop.md
    // https://github.com/swiftlang/swift/blob/643cbd15e637ece615b911cce1e1bf96a28297e3/lib/IRGen/GenClass.cpp#L2613
    public var isStubClass: Bool {
        let isa = layout.isa
        return 1 <= isa && isa < 16
    }
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
        guard let superCls = superClass(in: machO) else {
            return nil
        }

        var data: ClassROData?
        if let _data = superCls.classROData(in: machO) {
            data = _data
        }
        if let rw = superCls.classRWData(in: machO) {
            if let _data = rw.classROData(in: machO) {
                data = _data
            }
            if let ext = rw.ext(in: machO),
               let _data = ext.classROData(in: machO) {
                data = _data
            }
        }
        return data?.name(in: machO)
    }
}

extension ObjCClassProtocol {
    private func _readClass(
        at offset: UInt64,
        field: LayoutField,
        in machO: MachOFile
    ) -> Self? {
        guard offset > 0 else { return nil }
        var offset: UInt64 = machO.fileOffset(
            of: numericCast(offset)
        ) + numericCast(machO.headerStartOffset)

        if let resolved = resolveRebase(field, in: machO) {
            offset = machO.fileOffset(of: resolved) + numericCast(machO.headerStartOffset)
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
        return .init(
            layout: layout,
            offset: numericCast(offset) - machO.headerStartOffset
        )
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
