//
//  ObjCMethodList.swift
//
//
//  Created by p-x9 on 2024/05/16
//
//

import Foundation
@_spi(Support) import MachOKit

// https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L707

// https://github.com/apple-oss-distributions/dyld/blob/25174f1accc4d352d9e7e6294835f9e6e9b3c7bf/common/ObjCVisitor.h#L191

public struct ObjCMethodList: EntrySizeListProtocol {
    public typealias Entry = ObjCMethod

    /// Offset from machO header start
    public let offset: Int
    public let header: Header
    public let is64Bit: Bool
}

extension ObjCMethodList {
    init(
        ptr: UnsafeRawPointer,
        offset: Int,
        is64Bit: Bool
    ) {
        self.offset = offset
        self.header = ptr.assumingMemoryBound(to: Header.self).pointee
        self.is64Bit = is64Bit
    }
}

extension ObjCMethodList {
    public var isListOfLists: Bool {
        offset & 1 == 1
    }
}

extension ObjCMethodList {
    public static var flagMask: UInt32 { 0xffff0003 }
}

extension ObjCMethodList {
    typealias Mask = ObjCMethodListMask

    public var listKind: ObjCMethod.Kind {
        if usesRelativeOffsets {
            if usesOffsetsFromTypeBuffer {
                return .relativeDirectSelectorsAndTypes
            } else if usesOffsetsFromSelectorBuffer {
                return .relativeDirectSelectors
            }
            return .relativeIndirect
        }
        return .pointer
    }

    public var usesOffsetsFromTypeBuffer: Bool {
        header.entsizeAndFlags & Mask.usesTypeOffsets != 0
    }

    public var usesOffsetsFromSelectorBuffer: Bool {
        header.entsizeAndFlags & Mask.usesSelectorOffsets != 0
    }

    public var usesRelativeOffsets: Bool {
        header.entsizeAndFlags & Mask.isRelative != 0
    }
}

extension ObjCMethodList {
    func isValidEntrySize(is64Bit: Bool) -> Bool {
        switch listKind {
        case .pointer where is64Bit:
            MemoryLayout<ObjCMethod.Pointer64>.size == entrySize
        case .pointer:
            MemoryLayout<ObjCMethod.Pointer32>.size == entrySize
        case .relativeDirectSelectors:
            MemoryLayout<ObjCMethod.RelativeDirect>.size == entrySize
        case .relativeDirectSelectorsAndTypes:
            MemoryLayout<ObjCMethod.RelativeDirect>.size == entrySize
        case .relativeIndirect:
            MemoryLayout<ObjCMethod.RelativeInDirect>.size == entrySize
        }
    }
}

extension ObjCMethodList {
    public func methods(
        in machO: MachOImage
    ) -> [ObjCMethod] {
        // TODO: Support listOfLists
        guard !isListOfLists else { return [] }

        let ptr = machO.ptr.advanced(by: offset)
        let start = ptr.advanced(by: MemoryLayout<Header>.size)

        switch listKind {
        case .pointer:
            let sequence = MemorySequence(
                basePointer: start.assumingMemoryBound(
                    to: ObjCMethod.Pointer.self
                ),
                numberOfElements: count
            )
            return sequence
                .map { ObjCMethod($0) }

        case .relativeDirectSelectors:
            let sequence = MemorySequence(
                basePointer: start.assumingMemoryBound(
                    to: ObjCMethod.RelativeDirect.self
                ),
                numberOfElements: count
            )
            let size = MemoryLayout<ObjCMethod.RelativeDirect>.size
            return sequence
                .enumerated()
                .map {
                    ObjCMethod(
                        $1,
                        at: start.advanced(by: size * $0),
                        isRelativeDirectType: false
                    )
                }

        case .relativeDirectSelectorsAndTypes:
            let sequence = MemorySequence(
                basePointer: start.assumingMemoryBound(
                    to: ObjCMethod.RelativeDirect.self
                ),
                numberOfElements: count
            )
            let size = MemoryLayout<ObjCMethod.RelativeDirect>.size
            return sequence
                .enumerated()
                .map {
                    ObjCMethod(
                        $1,
                        at: start.advanced(by: size * $0),
                        isRelativeDirectType: true
                    )
                }

        case .relativeIndirect:
            let sequence = MemorySequence(
                basePointer: start.assumingMemoryBound(
                    to: ObjCMethod.RelativeInDirect.self
                ),
                numberOfElements: count
            )
            let size = MemoryLayout<ObjCMethod.RelativeInDirect>.size
            return sequence
                .enumerated()
                .map {
                    ObjCMethod($1, at: start.advanced(by: size * $0))
                }
        }
    }

    public func methods(
        in machO: MachOFile
    ) -> [ObjCMethod]? {
        guard !isListOfLists else {
            assertionFailure()
            return nil
        }

        let offset: UInt64 = numericCast(offset + MemoryLayout<Header>.size)
        guard let (fileHandle, fileOffset) = machO.fileHandleAndOffset(forOffset: offset) else {
            return nil
        }

        switch listKind {
        case .pointer where machO.is64Bit:
            let sequence: DataSequence<ObjCMethod.Pointer64> = fileHandle.readDataSequence(
                offset: fileOffset,
                numberOfElements: count,
                swapHandler: nil
            )
            let size = MemoryLayout<ObjCMethod.Pointer64>.size
            return sequence.enumerated()
                .map {
                    pointerMethod(
                        $1,
                        in: machO,
                        entryOffset: numericCast(offset) + $0 * size
                    )
                }
        case .pointer:
            let sequence: DataSequence<ObjCMethod.Pointer32> = fileHandle.readDataSequence(
                offset: fileOffset,
                numberOfElements: count,
                swapHandler: nil
            )
            let size = MemoryLayout<ObjCMethod.Pointer32>.size
            return sequence.enumerated()
                .map {
                    pointerMethod(
                        $1,
                        in: machO,
                        entryOffset: numericCast(offset) + $0 * size
                    )
                }

        case .relativeIndirect:
            let sequence: DataSequence<ObjCMethod.RelativeInDirect> = fileHandle.readDataSequence(
                offset: fileOffset,
                numberOfElements: count,
                swapHandler: nil
            )
            let size = MemoryLayout<ObjCMethod.RelativeInDirect>.size
            return sequence.enumerated()
                .map {
                    let offset = numericCast(offset) + $0 * size
                    let fileOffset = numericCast(fileOffset) + $0 * size
                    return indirectMethod(
                        $1,
                        in: machO,
                        fileHandle: fileHandle,
                        entryOffset: numericCast(offset),
                        fileOffset: numericCast(fileOffset)
                    )
                }

        case .relativeDirectSelectors:
            let sequence: DataSequence<ObjCMethod.RelativeDirect> = fileHandle.readDataSequence(
                offset: fileOffset,
                numberOfElements: count,
                swapHandler: nil
            )

            let size = MemoryLayout<ObjCMethod.RelativeDirect>.size
            let nameOffsetInCache = machO.relativeMethodSelectorBaseAddressOffset ?? 0
            return sequence.enumerated()
                .map {
                    let offset = numericCast(offset) + $0 * size
                    return directMethod(
                        $1,
                        in: machO,
                        entryOffset: numericCast(offset),
                        nameBaseOffset: nameOffsetInCache,
                        typeBaseOffset: nil
                    )
                }

        case .relativeDirectSelectorsAndTypes:
            let sequence: DataSequence<ObjCMethod.RelativeDirect> = fileHandle.readDataSequence(
                offset: fileOffset,
                numberOfElements: count,
                swapHandler: nil
            )

            let size = MemoryLayout<ObjCMethod.RelativeDirect>.size
            let nameOffsetInCache = machO.relativeMethodSelectorBaseAddressOffset ?? 0
            return sequence.enumerated()
                .map {
                    let offset = numericCast(offset) + $0 * size
                    return directMethod(
                        $1,
                        in: machO,
                        entryOffset: numericCast(offset),
                        nameBaseOffset: nameOffsetInCache,
                        typeBaseOffset: nameOffsetInCache // NOTE: offset from selector
                    )
                }
        }
    }
}

extension ObjCMethodList {
    // Every field of a pointer-format entry is a pointer slot. In a dyld cache
    // a slot holds its mapping's slide info encoding, not an address — under
    // slide info v5 an offset from the cache start, which is below the shared
    // region — so each one is resolved through its rebase before it is read.
    private func pointerMethod(
        _ pointer: ObjCMethod.Pointer64,
        in machO: MachOFile,
        entryOffset: Int
    ) -> ObjCMethod {
        ObjCMethod(
            name: resolveString(
                in: machO,
                slot: .init(fieldOffset: entryOffset, value: pointer.name)
            ),
            types: resolveString(
                in: machO,
                slot: .init(fieldOffset: entryOffset + 8, value: pointer.types)
            ),
            imp: resolveOffset(
                in: machO,
                slot: .init(fieldOffset: entryOffset + 16, value: pointer.imp)
            )
        )
    }

    private func pointerMethod(
        _ pointer: ObjCMethod.Pointer32,
        in machO: MachOFile,
        entryOffset: Int
    ) -> ObjCMethod {
        ObjCMethod(
            name: resolveString(
                in: machO,
                slot: .init(fieldOffset: entryOffset, value: numericCast(pointer.name))
            ),
            types: resolveString(
                in: machO,
                slot: .init(fieldOffset: entryOffset + 4, value: numericCast(pointer.types))
            ),
            imp: resolveOffset(
                in: machO,
                slot: .init(fieldOffset: entryOffset + 8, value: numericCast(pointer.imp))
            )
        )
    }

    private func indirectMethod(
        _ relativeIndirect: ObjCMethod.RelativeInDirect,
        in machO: MachOFile,
        fileHandle: MachOFile.File,
        entryOffset: UInt64,
        fileOffset: UInt64
    ) -> ObjCMethod {
        let namePointerOffset = resolvedOffset(
            base: fileOffset,
            relative: relativeIndirect.name.offset
        ) ?? 0
        let nameAddress: UInt64 = (try? fileHandle.read(
            offset: numericCast(namePointerOffset),
            as: UInt64.self
        )) ?? 0
        let types = resolvedOffset(
            base: fileOffset,
            relative: relativeIndirect.types.offset,
            adjustment: 4
        ) ?? 0

        let imp = resolvedOffset(
            base: entryOffset,
            relative: relativeIndirect.imp.offset,
            adjustment: 8
        ) ?? 0

        return ObjCMethod(
            name: resolveString(
                in: machO,
                forAddress: nameAddress
            ),
            types: fileHandle.readString(
                offset: numericCast(types)
            ) ?? "",
            imp: imp
        )
    }

    private func directMethod(
        _ relativeDirect: ObjCMethod.RelativeDirect,
        in machO: MachOFile,
        entryOffset: UInt64,
        nameBaseOffset: UInt64,
        typeBaseOffset: UInt64?
    ) -> ObjCMethod {
        let nameOffset = resolvedOffset(
            base: nameBaseOffset,
            relative: relativeDirect.name.offset
        ) ?? 0

        let typesOffset: UInt64
        if let typeBaseOffset {
            typesOffset = resolvedOffset(
                base: typeBaseOffset,
                relative: relativeDirect.types.offset
            ) ?? 0
        } else {
            typesOffset = resolvedOffset(
                base: entryOffset,
                relative: relativeDirect.types.offset,
                adjustment: 4
            ) ?? 0
        }

        let imp = resolvedOffset(
            base: entryOffset,
            relative: relativeDirect.imp.offset,
            adjustment: 8
        ) ?? 0

        return ObjCMethod(
            name: resolveString(
                in: machO,
                forOffset: nameOffset
            ),
            types: resolveString(
                in: machO,
                forOffset: typesOffset
            ),
            imp: imp
        )
    }
}

extension ObjCMethodList {
    private func resolvedOffset<Offset: BinaryInteger>(
        base: UInt64,
        relative: Offset,
        adjustment: UInt64 = 0
    ) -> UInt64? {
        guard let base = Int64(exactly: base),
              let relative = Int64(exactly: relative),
              let adjustment = Int64(exactly: adjustment) else {
            return nil
        }
        let resolved = base + relative + adjustment
        guard resolved >= 0 else {
            return nil
        }
        return UInt64(resolved)
    }

    private func resolveString(
        in machO: MachOFile,
        forAddress address: UInt64
    ) -> String {
        guard let (fileHandle, fileOffset) = machO.fileHandleAndOffset(forAddress: address) else {
            return ""
        }
        return fileHandle.readString(offset: fileOffset) ?? ""
    }

    private func resolveString(
        in machO: MachOFile,
        forOffset offset: UInt64
    ) -> String {
        guard let (fileHandle, fileOffset) = machO.fileHandleAndOffset(forOffset: offset) else {
            return ""
        }
        return fileHandle.readString(offset: fileOffset) ?? ""
    }

    /// The string a pointer slot points to, the slot resolved through its
    /// rebase first.
    private func resolveString(
        in machO: MachOFile,
        slot: UnresolvedValue
    ) -> String {
        guard slot.value != 0,
              let resolved = machO.resolveRebase(slot),
              let (fileHandle, fileOffset) = machO.fileHandleAndOffset(forResolvedValue: resolved) else {
            return ""
        }
        return fileHandle.readString(offset: fileOffset) ?? ""
    }

    /// The offset a pointer slot points to, the slot resolved through its
    /// rebase first: from the main cache's start for a dyld cache image, from
    /// the Mach-O header for a file. A null slot — every protocol method's
    /// `imp` — stays 0.
    private func resolveOffset(
        in machO: MachOFile,
        slot: UnresolvedValue
    ) -> UInt64 {
        guard slot.value != 0,
              let resolved = machO.resolveRebase(slot) else {
            return 0
        }
        return resolved.offset
    }
}
