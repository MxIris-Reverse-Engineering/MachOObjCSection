//
//  ObjCMethodListProtocol.swift
//
//
//  Created by p-x9 on 2024/05/23
//  
//

import Foundation

public protocol ObjCMethodListProtocol {
    var header: ObjCMethodListHeader { get }

    var isListOfLists: Bool { get }

    var methods: AnyRandomAccessCollection<ObjCMethod> { get }
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
