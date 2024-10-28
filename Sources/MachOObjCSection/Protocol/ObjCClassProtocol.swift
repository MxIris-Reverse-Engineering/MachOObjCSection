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

public protocol ObjCClassProtocol {
    associatedtype Layout: _ObjCClassLayoutProtocol
    associatedtype ClassROData: LayoutWrapper, ObjCClassRODataProtocol where ClassROData.Layout.Pointer == Layout.Pointer

    var layout: Layout { get }
    var offset: Int { get }

    func metaClass(in machO: MachOFile) -> Self?
    func superClass(in machO: MachOFile) -> Self?
    func superClassName(in machO: MachOFile) -> String?
    func classData(in machO: MachOFile) -> ClassROData?

    func metaClass(in machO: MachOImage) -> Self?
    func superClass(in machO: MachOImage) -> Self?
    func superClassName(in machO: MachOImage) -> String?
    func classData(in machO: MachOImage) -> ClassROData?
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

extension ObjCClassProtocol where Self: LayoutWrapper {
    func resolveRebase(
        _ keyPath: PartialKeyPath<Layout>,
        in machO: MachOFile
    ) -> UInt64? {
        let offset = self.offset + layoutOffset(of: keyPath)
        if let resolved = machO.resolveOptionalRebase(at: UInt64(offset)) {
            if let cache = machO.cache {
                return resolved - cache.header.sharedRegionStart
            }
            return resolved
        }
        return nil
    }

    func resolveBind(
        _ keyPath: PartialKeyPath<Layout>,
        in machO: MachOFile
    ) -> String? {
        let offset = self.offset + layoutOffset(of: keyPath)
        guard let fixup = machO.dyldChainedFixups else { return nil }
        if let resolved = machO.resolveBind(at: UInt64(offset)) {
            return fixup.symbolName(for: resolved.0.info.nameOffset)
        }
        return nil
    }

    func isBind(
        _ keyPath: PartialKeyPath<Layout>,
        in machO: MachOFile
    ) -> Bool {
        let offset = self.offset + layoutOffset(of: keyPath)
        return machO.isBind(offset)
    }
}
