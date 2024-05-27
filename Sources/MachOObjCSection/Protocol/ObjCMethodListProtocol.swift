//
//  ObjCMethodListProtocol.swift
//
//
//  Created by p-x9 on 2024/05/23
//  
//

import Foundation

// https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L707

// https://github.com/apple-oss-distributions/dyld/blob/25174f1accc4d352d9e7e6294835f9e6e9b3c7bf/common/ObjCVisitor.h#L191

public protocol ObjCMethodListProtocol {
    var header: ObjCMethodListHeader { get }

    var isListOfLists: Bool { get }

    var methods: [ObjCMethod] { get }
}

extension ObjCMethodListProtocol {
    typealias Mask = ObjCMethodListMask

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

    public var size: Int {
        MemoryLayout<ObjCMethodListHeader>.size + entrySize * count
    }
}
