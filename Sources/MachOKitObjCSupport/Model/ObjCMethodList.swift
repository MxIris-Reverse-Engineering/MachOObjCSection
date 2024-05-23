//
//  ObjCMethodList.swift
//
//
//  Created by p-x9 on 2024/05/16
//  
//

import Foundation

// https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L707

// https://github.com/apple-oss-distributions/dyld/blob/25174f1accc4d352d9e7e6294835f9e6e9b3c7bf/common/ObjCVisitor.h#L191

public struct ObjCMethodList {
    enum Mask {
        static let isUniqued: UInt32 = 0x1
        static let isSorted: UInt32 = 0x2

        static let usesSelectorOffsets: UInt32 = 0x40000000
        static let isRelative: UInt32 = 0x80000000

        static let sizeMask: UInt32 = 0x0000FFFC
        static var flagMask: UInt32 { ~sizeMask }
    }

    struct Header {
        let entsizeAndFlags: UInt32
        let count: UInt32
    }

    public let ptr: UnsafeRawPointer
    let header: Header

    init(ptr: UnsafeRawPointer) {
        self.ptr = ptr
        self.header = ptr.load(as: Header.self)
    }
}

extension ObjCMethodList {
    public var entrySize: Int {
        numericCast(header.entsizeAndFlags & Mask.sizeMask)
    }

    public var flags: UInt32 {
        header.entsizeAndFlags & Mask.flagMask
    }

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

    public var isListOfLists: Bool {
        (ptr.load(as: uintptr_t.self) & 1) != 0
    }

    public var size: Int {
        MemoryLayout<Header>.size + entrySize * count
    }
}

extension ObjCMethodList {
    public var methods: AnyRandomAccessCollection<ObjCMethod> {
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
}
