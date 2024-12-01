//
//  FixupResolvable.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/12/01
//  
//

import Foundation
@_spi(Support) import MachOKit

public protocol _FixupResolvable {
    var offset: Int { get }
}

extension _FixupResolvable where Self: LayoutWrapper {
    @_spi(Core)
    public func resolveRebase(
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

    @_spi(Core)
    public func resolveBind(
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

    @_spi(Core)
    public func isBind(
        _ keyPath: PartialKeyPath<Layout>,
        in machO: MachOFile
    ) -> Bool {
        let offset = self.offset + layoutOffset(of: keyPath)
        return machO.isBind(offset)
    }
}
