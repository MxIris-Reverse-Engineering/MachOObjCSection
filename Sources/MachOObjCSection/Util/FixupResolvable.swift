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

extension _FixupResolvable {
    @_spi(Core)
    public func resolveRebase(
        fileOffset: Int,
        in machO: MachOFile
    ) -> UInt64? {
        var offset: UInt64 = numericCast(fileOffset)
        offset = resolveCacheStartOffsetIfNeeded(offset: offset, in: machO)

        if let resolved = machO.resolveOptionalRebase(at: offset) {
            if let cache = machO.cache {
                return resolved - cache.header.sharedRegionStart
            }
            return resolved
        }
        return nil
    }

    @_spi(Core)
    public func resolveBind(
        fileOffset: Int,
        in machO: MachOFile
    ) -> String? {
        guard let fixup = machO.dyldChainedFixups else { return nil }

        var offset: UInt64 = numericCast(fileOffset)
        offset = resolveCacheStartOffsetIfNeeded(offset: offset, in: machO)

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
        var offset: UInt64 = numericCast(fileOffset)
        offset = resolveCacheStartOffsetIfNeeded(offset: offset, in: machO)

        return machO.isBind(numericCast(offset))
    }
}

extension _FixupResolvable {
    func resolveCacheStartOffsetIfNeeded(
        offset: UInt64,
        in machO: MachOFile
    ) -> UInt64 {
        if let (_, _offset) = machO.cacheAndFileOffset(
            fromStart: offset
        ) {
            return _offset
        }
        return offset
    }
}
//
//@testable import MachOKit
//extension DyldCache {
//    public func resolveOptionalRebase2(at offset: UInt64) -> UInt64? {
//        // swiftlint:disable:previous cyclomatic_complexity
//        guard let mappingInfos,
//              let unslidLoadAddress = mappingInfos.first?.address else {
//            return nil
//        }
//        guard let mapping = mappingAndSlideInfo(forFileOffset: offset) else {
//            return nil
//        }
//        guard let slideInfo = mapping.slideInfo(in: self) else {
//            let version = mapping.slideInfoVersion(in: self) ?? .none
//            if version == .none {
//                if cpu.is64Bit {
//                    let value: UInt64 = fileHandle.read(offset: offset)
//                    guard value != 0 else { return nil }
//                    return value
//                } else {
//                    let value: UInt32 = fileHandle.read(offset: offset)
//                    guard value != 0 else { return nil }
//                    return numericCast(value)
//                }
//            } else {
//                return nil
//            }
//        }
//
//        let runtimeOffset: UInt64
//        let onDiskDylibChainedPointerBaseAddress: UInt64
//        switch slideInfo {
//        case .v1:
//            let value: UInt32 = fileHandle.read(offset: offset)
//            guard value != 0 else { return nil }
//            runtimeOffset = numericCast(value) - unslidLoadAddress
//            onDiskDylibChainedPointerBaseAddress = unslidLoadAddress
//
//        case let .v2(slideInfo):
//            let rawValue: UInt64 = fileHandle.read(offset: offset)
//            guard rawValue != 0 else { return nil }
//            let deltaMask: UInt64 = 0x00FFFF0000000000
//            let valueMask: UInt64 = ~deltaMask
//            runtimeOffset = rawValue & valueMask
//            onDiskDylibChainedPointerBaseAddress = slideInfo.value_add
////            onDiskDylibChainedPointerBaseAddress = unslidLoadAddress
//
//        case .v3:
//            let rawValue: UInt64 = fileHandle.read(offset: offset)
//            guard rawValue != 0 else { return nil }
//            let _fixup = DyldChainedFixupPointerInfo.ARM64E(rawValue: rawValue)
//            let fixup: DyldChainedFixupPointerInfo = .arm64e(_fixup)
//            let pointer: DyldChainedFixupPointer = .init(
//                offset: Int(offset),
//                fixupInfo: fixup
//            )
//            guard let _runtimeOffset = pointer.rebaseTargetRuntimeOffset(
//                preferedLoadAddress: unslidLoadAddress
//            ) else { return nil }
//            runtimeOffset = _runtimeOffset
//            onDiskDylibChainedPointerBaseAddress = unslidLoadAddress
//
//        case let .v4(slideInfo):
//            let rawValue: UInt32 = fileHandle.read(offset: offset)
//            guard rawValue != 0 else { return nil }
//            let deltaMask: UInt64 = 0x00000000C0000000
//            let valueMask: UInt64 = ~deltaMask
//            runtimeOffset = numericCast(rawValue) & valueMask
////            onDiskDylibChainedPointerBaseAddress = slideInfo.value_add
//            onDiskDylibChainedPointerBaseAddress = unslidLoadAddress
//
//        case let .v5(slideInfo):
//            let rawValue: UInt64 = fileHandle.read(offset: offset)
//            guard rawValue != 0 else { return nil }
//            let _fixup = DyldChainedFixupPointerInfo.ARM64ESharedCache(
//                rawValue: rawValue
//            )
//            let fixup: DyldChainedFixupPointerInfo = .arm64e_shared_cache(_fixup)
//            guard let rebase = fixup.rebase else {
//                return nil
//            }
//            runtimeOffset = numericCast(rebase.unpackedTarget)
////            onDiskDylibChainedPointerBaseAddress = slideInfo.value_add
//            onDiskDylibChainedPointerBaseAddress = unslidLoadAddress
//        }
//
//        return runtimeOffset + onDiskDylibChainedPointerBaseAddress
//    }
//}
//
//extension MachOFile {
//    public func resolveOptionalRebase2(at offset: UInt64) -> UInt64? {
//        if isLoadedFromDyldCache,
//           let cache = try? DyldCache(url: url) {
//            return cache.resolveOptionalRebase2(at: offset)
//        }
//
//        guard let chainedFixup = dyldChainedFixups,
//              let startsInImage = chainedFixup.startsInImage else {
//            return nil
//        }
//        let startsInSegments = chainedFixup.startsInSegments(
//            of: startsInImage
//        )
//
//        for segment in startsInSegments {
//            let pointers = chainedFixup.pointers(of: segment, in: self)
//            guard let pointer = pointers.first(where: {
//                $0.offset == offset
//            }) else { continue }
//            guard pointer.fixupInfo.rebase != nil,
//                  let offset = pointer.rebaseTargetRuntimeOffset(for: self) else {
//                return nil
//            }
//            if is64Bit {
//                let value: UInt64 = fileHandle.read(
//                    offset: numericCast(headerStartOffset + pointer.offset)
//                )
//                if value == 0 { return nil }
//            } else {
//                let value: UInt32 = fileHandle.read(
//                    offset: numericCast(headerStartOffset + pointer.offset)
//                )
//                if value == 0 { return nil }
//            }
//            return offset
//        }
//        return nil
//    }
//}
