//
//  MachOFile+.swift
//
//
//  Created by p-x9 on 2024/07/19
//
//

import Foundation
@_spi(Support) import MachOKit
internal import MachOKitExtensions
#if compiler(>=6.0) || (compiler(>=5.10) && hasFeature(AccessLevelOnImport))
internal import FileIO
#else
@_implementationOnly import FileIO
#endif

extension MachOFile {
    internal typealias File = MemoryMappedFile

    var fileHandle: File {
        FileHandleHolder.shared.fileHandle(
            for: fileHandleIdentity,
            initialize: {
                try! .open(url: url, isWritable: false)
            }
        )
    }
}

// MARK: - dyld cache
//
// `cache(for:)`, `cacheAndFileOffset(for:)` and `cacheAndFileOffset(fromStart:)`
// come from MachOKitExtensions, which builds each sub-cache of the file's cache
// once and hands back the same instance every time. The copies this module
// kept assembled a sub-cache afresh for every read that crossed into one, and
// from a cache opened from its main file alone that meant opening and mapping
// the file again: `fileHandle` keys its mapping on the cache instance.

// MARK: - FileIO
extension MachOFile {
    func fileHandleAndOffset(
        forAddress address: UInt64
    ) -> (File, UInt64)? {
        if !isLoadedFromDyldCache,
           let fileOffset = fileOffset(of: address) {
            return (fileHandle, fileOffset + numericCast(headerStartOffset))
        }

        // Looked up as the address it is: one below the shared region — a slot
        // still in its slide info encoding, say — lies in no mapping and
        // resolves to nil, where subtracting the region start would trap.
        if let (_cache, fileOffset) = cacheAndFileOffset(for: address) {
            return (_cache.fileHandle, fileOffset)
        }

        return nil
    }

    func fileHandleAndOffset(
        forOffset offset: UInt64
    ) -> (File, UInt64)? {
        if !isLoadedFromDyldCache {
            return (fileHandle, offset + numericCast(headerStartOffset))
        }

        if let (_cache, fileOffset) = cacheAndFileOffset(
            fromStart: offset
           ) {
            return (_cache.fileHandle, fileOffset)
        }

        return nil
    }

    func fileHandleAndOffset(
        forResolvedValue resolved: ResolvedValue
    ) -> (File, UInt64)? {
        // ResolvedValue.offset follows fileHandleAndOffset(forOffset:)'s convention:
        // Mach-O file offset for ordinary files, main-cache-start offset for dyld cache images.
        fileHandleAndOffset(forOffset: resolved.offset)
    }

    func relativeListLocation(
        for entry: RelativeListListEntry
    ) -> (image: MachOFile, cache: DyldCache, fileOffset: UInt64)? {
        let offset: UInt64 = numericCast(entry.offset + entry.listOffset)

        guard let cache,
              let located = cache._machO(at: entry.imageIndex) else {
            return nil
        }

        let address = cache.mainCacheHeader.sharedRegionStart + offset
        guard let fileOffset = located.cache.fileOffset(of: address) else {
            return nil
        }

        return (located.value, located.cache, fileOffset)
    }
}

// MARK: - rebase / bind
extension MachOFile {
    func isBind(
        _ offset: Int
    ) -> Bool {
        cached.resolveBind(at: numericCast(offset)) != nil
    }

    /// The name of the symbol that the chained fixup at `offset` binds to.
    func chainedFixupBindSymbolName(at offset: UInt64) -> String? {
        let cached = self.cached
        guard let dyldChainedFixups = cached.dyldChainedFixups,
              let (chainedImport, _) = cached.resolveBind(at: offset) else {
            return nil
        }
        return dyldChainedFixups.symbolName(for: chainedImport.info.nameOffset)
    }

    func isBind(
        _ unresolvedValue: UnresolvedValue
    ) -> Bool {
        isBind(unresolvedValue.fieldOffset)
    }

    /// Resolves a rebase from an `UnresolvedValue`.
    ///
    /// If the Mach-O is backed by dyld shared cache(s):
    /// - find which cache actually contains this offset
    /// - ask that cache to resolve the rebase at its local file offset
    /// - return the resolved address together with the “offset from the main cache start”
    ///
    /// Otherwise (non-cache Mach-O):
    /// - resolve against the file directly
    ///
    /// If it cannot be resolved, we still return a `ResolvedValue` that contains:
    /// - the raw input value (unrebased)
    /// - file offset resolved from that raw value
    ///
    /// - Parameter unresolvedValue: position (file offset) and raw pointer value stored in the image
    /// - Returns: resolved value and offset
    func resolveRebase(
        _ unresolvedValue: UnresolvedValue
    ) -> ResolvedValue? {
        let offset: UInt64 = numericCast(unresolvedValue.fieldOffset)

        if let (cache, _offset) = cacheAndFileOffset(
            fromStart: offset
        ) {
            let address = cache.resolveOptionalRebase(at: _offset) ?? unresolvedValue.value
            // The raw value stands in when the slot has no rebase to resolve,
            // and a raw slot can be null or an encoding the slide info decoder
            // did not take: neither is an address in the shared region.
            guard address >= cache.mainCacheHeader.sharedRegionStart else {
                return nil
            }
            return .init(
                address: address,
                offset: address - cache.mainCacheHeader.sharedRegionStart
            )
        }

        if let resolved = cached.resolveOptionalRebase(
            at: offset
        ) {
            guard let resolvedFileOffset = fileOffset(of: resolved) else {
                return nil
            }
            return .init(
                address: resolved,
                offset: resolvedFileOffset
            )
        }

        guard let fallbackFileOffset = fileOffset(of: unresolvedValue.value) else {
            return nil
        }
        return .init(
            address: unresolvedValue.value,
            offset: fallbackFileOffset
        )
    }
}

// MARK: - Objective-C
extension MachOFile {
    var relativeMethodSelectorBaseAddressOffset: UInt64? {
        if let cache {
            if let fullCache = cache._cachedFullCache {
                return fullCache.relativeMethodSelectorBaseAddressOffset
            }
            return cache.locateValue(\.relativeMethodSelectorBaseAddressOffset)?.value
        }

        return nil
    }

    func findObjCSection64(for section: ObjCMachOSection) -> Section64? {
        findObjCSection64(for: section.rawValue)
    }

    func findObjCSection32(for section: ObjCMachOSection) -> Section? {
        findObjCSection32(for: section.rawValue)
    }

    // [dyld implementation](https://github.com/apple-oss-distributions/dyld/blob/66c652a1f1f6b7b5266b8bbfd51cb0965d67cc44/common/MachOFile.cpp#L3880)
    func findObjCSection64(for name: String) -> Section64? {
        let segmentNames = [
            "__DATA", "__DATA_CONST", "__DATA_DIRTY"
        ]
        let segments = segments64
        for segment in segments {
            guard segmentNames.contains(segment.segmentName) else {
                continue
            }
            if let section = segment._section(for: name, in: self) {
                return section
            }
        }
        return nil
    }

    func findObjCSection32(for name: String) -> Section? {
        let segmentNames = [
            "__DATA", "__DATA_CONST", "__DATA_DIRTY"
        ]
        let segments = segments32
        for segment in segments {
            guard segmentNames.contains(segment.segmentName) else {
                continue
            }
            if let section = segment._section(for: name, in: self) {
                return section
            }
        }
        return nil
    }
}

extension MachOFile {
    var objcImageIndex: Int? {
        guard isLoadedFromDyldCache else { return nil }
        guard let cache else { return nil }
        if let (cache, headerOptimizationRO) = cache._headerOptimizationRO64,
           let info = headerOptimizationRO.headerInfo(in: cache, for: self) {
            return info.index
        }
        if let (cache, headerOptimizationRO) = cache._headerOptimizationRO32,
           let info = headerOptimizationRO.headerInfo(in: cache, for: self) {
            return info.index
        }
        return nil
    }
}
