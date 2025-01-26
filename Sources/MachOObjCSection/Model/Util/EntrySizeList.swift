//
//  EntrySizeList.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2025/01/26
//  
//

import Foundation

public struct EntrySizeListHeader: LayoutWrapper {
    public struct Layout {
        public let entsizeAndFlags: UInt32
        public let count: UInt32
    }
    public var layout: Layout
}

public protocol EntrySizeListProtocol {
    associatedtype Entry

    typealias Header = EntrySizeListHeader

    static var flagMask: UInt32 { get }

    var offset: Int { get }
    var header: EntrySizeListHeader { get }
}

extension EntrySizeListProtocol {
    public var entrySize: Int {
        numericCast(header.entsizeAndFlags & ~Self.flagMask)
    }

    public var _flags: UInt32 {
        numericCast(header.entsizeAndFlags & Self.flagMask)
    }

    public var count: Int { numericCast(header.count) }
}

extension EntrySizeListProtocol {
    public var listSize: Int {
        MemoryLayout<EntrySizeListHeader>.size + entrySize * numericCast(count)
    }
}
