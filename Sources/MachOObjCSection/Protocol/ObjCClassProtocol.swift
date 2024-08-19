//
//  ObjCClassProtocol.swift
//
//
//  Created by p-x9 on 2024/08/06
//  
//

import Foundation
@_spi(Support) import MachOKit

public protocol ObjCClassProtocol {
    associatedtype Layout: _ObjCClassLayoutProtocol
    associatedtype ClassData: LayoutWrapper, ObjCClassDataProtocol where ClassData.Layout.Pointer == Layout.Pointer

    var layout: Layout { get }
    var offset: Int { get }

    func metaClass(in machO: MachOFile) -> Self?
    func superClass(in machO: MachOFile) -> Self?
    func classData(in machO: MachOFile) -> ClassData?
}

extension ObjCClassProtocol where Self: LayoutWrapper {
    public func classData(in machO: MachOFile) -> ClassData? {
        var offset: UInt64 = numericCast(layout.dataVMAddrAndFastFlags) & 0x00007ffffffffff8 + numericCast(machO.headerStartOffset)
        offset &= 0x7ffffffff
        if let cache = machO.cache {
            guard let _offset = cache.fileOffset(of: offset + cache.header.sharedRegionStart) else {
                return nil
            }
            offset = _offset
        }
        return machO.fileHandle.read(offset: offset)
    }
}

extension ObjCClassProtocol {
    /// class is a Swift class from the pre-stable Swift ABI
    public var isSwiftLegacy: Bool {
        layout.dataVMAddrAndFastFlags & 0x1 != 0
    }

    /// class is a Swift class from the stable Swift ABI
    public var isSwiftStable: Bool {
        layout.dataVMAddrAndFastFlags & 0x2 != 0
    }

    public var isSwift: Bool {
        isSwiftStable || isSwiftLegacy
    }
}

extension ObjCClassProtocol where Self: LayoutWrapper {
    func resolveRebase(
        _ keyPath: PartialKeyPath<Layout>,
        in machO: MachOFile
    ) -> UInt64? {
        let offset = self.offset + layoutOffset(of: keyPath)
        if let resolved = machO.resolveRebase(at: UInt64(offset)) {
            if let cache = machO.cache {
                return resolved - cache.header.sharedRegionStart
            }
            return resolved
        }
        return nil
    }
}
