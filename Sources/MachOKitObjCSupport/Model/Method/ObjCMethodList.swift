//
//  ObjCMethodList.swift
//
//
//  Created by p-x9 on 2024/05/16
//  
//

import Foundation
@testable import MachOKit

// https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L707

// https://github.com/apple-oss-distributions/dyld/blob/25174f1accc4d352d9e7e6294835f9e6e9b3c7bf/common/ObjCVisitor.h#L191

public struct ObjCMethodList {
    public typealias Header = ObjCMethodListHeader
    
    /// Offset from machO header start
    public let offset: Int
    public let header: Header
    public let isListOfLists: Bool

    init(
        ptr: UnsafeRawPointer,
        offset: Int,
        is64Bit: Bool
    ) {
        self.offset = offset
        self.header = ptr.assumingMemoryBound(to: Header.self).pointee
        if is64Bit {
            self.isListOfLists = (ptr.assumingMemoryBound(to: UInt64.self).pointee & 1) != 0
        } else {
            self.isListOfLists = (ptr.assumingMemoryBound(to: UInt32.self).pointee & 1) != 0
        }
    }
}

extension ObjCMethodList {
    typealias Mask = ObjCMethodListMask

    public var entrySize: Int { header.entrySize }

    public var flags: UInt32 { header.flags }

    public var count: Int {
        numericCast(header.count)
    }

    public var listKind: ObjCMethod.Kind {
        if usesRelativeOffsets {
            return usesOffsetsFromSelectorBuffer ? .relativeDirect : .relativeIndirect
        }
        return .pointer
    }

    public var usesOffsetsFromSelectorBuffer: Bool {
        header.entsizeAndFlags & Mask.usesSelectorOffsets != 0
    }

    public var usesRelativeOffsets: Bool {
        header.entsizeAndFlags & Mask.isRelative != 0
    }

    public var size: Int { header.listSize }
}

extension ObjCMethodList {
    func isValidEntrySize(is64Bit: Bool) -> Bool {
        switch listKind {
        case .pointer where is64Bit:
            MemoryLayout<ObjCMethod.Pointer64>.size == entrySize
        case .pointer:
            MemoryLayout<ObjCMethod.Pointer32>.size == entrySize
        case .relativeDirect:
            MemoryLayout<ObjCMethod.RelativeDirect>.size == entrySize
        case .relativeIndirect:
            MemoryLayout<ObjCMethod.RelativeInDirect>.size == entrySize
        }
    }
}

extension ObjCMethodList {
    public func methods(
        in machO: MachOImage
    ) -> AnyRandomAccessCollection<ObjCMethod> {
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
            return AnyRandomAccessCollection(
                sequence
                    .map { ObjCMethod($0) }
            )

        case .relativeDirect:
            let sequence = MemorySequence(
                basePointer: start.assumingMemoryBound(
                    to: ObjCMethod.RelativeDirect.self
                ),
                numberOfElements: count
            )
            let size = MemoryLayout<ObjCMethod.RelativeInDirect>.size
            return AnyRandomAccessCollection(
                sequence
                    .enumerated()
                    .map {
                        ObjCMethod($1, at: start.advanced(by: size * $0))
                    }
            )

        case .relativeIndirect:
            let sequence = MemorySequence(
                basePointer: start.assumingMemoryBound(
                    to: ObjCMethod.RelativeInDirect.self
                ),
                numberOfElements: count
            )
            let size = MemoryLayout<ObjCMethod.RelativeInDirect>.size
            return AnyRandomAccessCollection(
                sequence
                    .enumerated()
                    .map {
                        ObjCMethod($1, at: start.advanced(by: size * $0))
                    }
            )
        }
    }

    public func methods(
        in machO: MachOFile
    ) -> AnyRandomAccessCollection<ObjCMethod>? {
        switch listKind {
        case .pointer where machO.is64Bit:
            let sequence: DataSequence<ObjCMethod.Pointer64> = machO.fileHandle.readDataSequence(
                offset: numericCast(offset + MemoryLayout<Header>.size),
                numberOfElements: count, 
                swapHandler: nil
            )
            let offset = machO.headerStartOffset + machO.headerStartOffsetInCache
            return AnyRandomAccessCollection(
                sequence
                    .map {
                        let name = UInt($0.name) & 0x7ffffffff
                        let types = UInt($0.types) & 0x7ffffffff
                        return ObjCMethod(
                            name: machO.fileHandle.readString(
                                offset: numericCast(offset) + numericCast(name),
                                size: 1000
                            ) ?? "",
                            types: machO.fileHandle.readString(
                                offset: numericCast(offset) + numericCast(types),
                                size: 1000
                            ) ?? "",
                            imp: nil
                        )
                    }
            )
        case .pointer:
            let sequence: DataSequence<ObjCMethod.Pointer32> = machO.fileHandle.readDataSequence(
                offset: numericCast(offset + MemoryLayout<Header>.size),
                numberOfElements: count,
                swapHandler: nil
            )
            let offset = machO.headerStartOffset + machO.headerStartOffsetInCache
            return AnyRandomAccessCollection(
                sequence
                    .map {
                        let name = UInt($0.name)
                        let types = UInt($0.types)
                        return ObjCMethod(
                            name: machO.fileHandle.readString(
                                offset: numericCast(offset) + numericCast(name),
                                size: 1000
                            ) ?? "",
                            types: machO.fileHandle.readString(
                                offset: numericCast(offset) + numericCast(types),
                                size: 1000
                            ) ?? "",
                            imp: nil
                        )
                    }
            )
        case .relativeIndirect:
            let offset = offset + MemoryLayout<Header>.size
            let sequence: DataSequence<ObjCMethod.RelativeInDirect> = machO.fileHandle.readDataSequence(
                offset: numericCast(offset),
                numberOfElements: count,
                swapHandler: nil
            )
            let size = MemoryLayout<ObjCMethod.RelativeInDirect>.size
            return AnyRandomAccessCollection(
                sequence.enumerated()
                    .map {
                        let offset = offset + $0 * size
                        let name: UInt = machO.fileHandle.read(
                            offset: numericCast(offset) + numericCast($1.name.offset)
                        ) & 0x7ffffffff
                        let types: Int = numericCast(offset) + numericCast($1.types.offset) + 4
                        return ObjCMethod(
                            name: machO.fileHandle.readString(
                                offset: numericCast(machO.headerStartOffset + machO.headerStartOffsetInCache) + numericCast(name),
                                size: 1000 // FIXME: length
                            ) ?? "",
                            types: machO.fileHandle.readString(
                                offset: numericCast(types),
                                size: 1000 // FIXME: length
                            ) ?? "",
                            imp: nil
                        )
                    }
            )
        default:
            return nil
        }
    }
}

extension FileHandle {
    func readDataSequence<Element>(
        offset: UInt64,
        numberOfElements: Int,
        swapHandler: ((inout Data) -> Void)? = nil
    ) -> DataSequence<Element> {
        seek(toFileOffset: offset)
        let size = MemoryLayout<Element>.size * numberOfElements
        var data = readData(
            ofLength: size
        )
        precondition(
            data.count >= size,
            "Invalid Data Size"
        )
        if let swapHandler { swapHandler(&data) }
        return .init(
            data: data,
            numberOfElements: numberOfElements
        )
    }
}
