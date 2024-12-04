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
    associatedtype LayoutField

    var offset: Int { get }

    func layoutOffset(of field: LayoutField) -> Int
}

extension _FixupResolvable {
    @_spi(Core)
    public func resolveRebase(
        _ field: LayoutField,
        in machO: MachOFile
    ) -> UInt64? {
        let offset = self.offset + layoutOffset(of: field)
        return resolveRebase(fileOffset: offset, in: machO)
    }

    @_spi(Core)
    public func resolveBind(
        _ field: LayoutField,
        in machO: MachOFile
    ) -> String? {
        let offset = self.offset + layoutOffset(of: field)
        return resolveBind(fileOffset: offset, in: machO)
    }

    @_spi(Core)
    public func isBind(
        _ field: LayoutField,
        in machO: MachOFile
    ) -> Bool {
        let offset = self.offset + layoutOffset(of: field)
        return isBind(fileOffset: offset, in: machO)
    }
}

#if false
extension _FixupResolvable where Self: LayoutWrapper {
    @_spi(Core)
    public func resolveRebase(
        _ keyPath: PartialKeyPath<Layout>,
        in machO: MachOFile
    ) -> UInt64? {
        let offset = self.offset + layoutOffset(of: keyPath)
        return resolveRebase(fileOffset: offset, in: machO)
    }

    @_spi(Core)
    public func resolveBind(
        _ keyPath: PartialKeyPath<Layout>,
        in machO: MachOFile
    ) -> String? {
        let offset = self.offset + layoutOffset(of: keyPath)
        return resolveBind(fileOffset: offset, in: machO)
    }

    @_spi(Core)
    public func isBind(
        _ keyPath: PartialKeyPath<Layout>,
        in machO: MachOFile
    ) -> Bool {
        let offset = self.offset + layoutOffset(of: keyPath)
        return isBind(fileOffset: offset, in: machO)
    }
}
#endif

extension _FixupResolvable {
    @_spi(Core)
    public func resolveRebase(
        fileOffset: Int,
        in machO: MachOFile
    ) -> UInt64? {
        let offset: UInt64 = numericCast(fileOffset)
        if let (cache, _offset) = resolveCacheStartOffsetIfNeeded(offset: offset, in: machO),
           let resolved = cache.resolveOptionalRebase(at: _offset) {
            return resolved - cache.mainCacheHeader.sharedRegionStart
        }

        if machO.cache != nil {
            return nil
        }

        if let resolved = machO.resolveOptionalRebase(at: offset) {
            return resolved
        }
        return nil
    }

    @_spi(Core)
    public func resolveBind(
        fileOffset: Int,
        in machO: MachOFile
    ) -> String? {
        guard !machO.isLoadedFromDyldCache else { return nil }
        guard let fixup = machO.dyldChainedFixups else { return nil }

        let offset: UInt64 = numericCast(fileOffset)

        if let resolved = machO.resolveBind(at: offset) {
            return fixup.symbolName(for: resolved.0.info.nameOffset)
        }
        return nil
    }

    @_spi(Core)
    public func isBind(
        fileOffset: Int,
        in machO: MachOFile
    ) -> Bool {
        guard !machO.isLoadedFromDyldCache else { return false }
        let offset: UInt64 = numericCast(fileOffset)
        return machO.isBind(numericCast(offset))
    }
}

extension _FixupResolvable {
    func resolveCacheStartOffsetIfNeeded(
        offset: UInt64,
        in machO: MachOFile
    ) -> (DyldCache, UInt64)? {
        if let (cache, _offset) = machO.cacheAndFileOffset(
            fromStart: offset
        ) {
            return (cache, _offset)
        }
        return nil
    }
}
