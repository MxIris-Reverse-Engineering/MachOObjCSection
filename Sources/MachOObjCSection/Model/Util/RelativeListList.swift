//
//  RelativeListList.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/11/02
//  
//

import Foundation
@_spi(Support) import MachOKit

// https://github.com/apple-oss-distributions/objc4/blob/89543e2c0f67d38ca5211cea33f42c51500287d5/runtime/objc-runtime-new.h#L1482

public struct RelativeListListHeader: LayoutWrapper {
    public struct Layout {
        public let entsizeAndFlags: UInt32
        public let count: UInt32
    }
    public var layout: Layout
}

public struct RelativeListListEntry: LayoutWrapper {
    public typealias Layout = relative_list_list_entry_t

    public let offset: Int
    public var layout: Layout

    public var imageIndex: Int { numericCast(layout.imageIndex) }
    public var listOffset: Int { numericCast(layout.listOffset) }
}

public protocol RelativeListListProtocol {
    associatedtype List
    typealias Header = RelativeListListHeader
    typealias Entry = RelativeListListEntry

    static var flagMask: UInt32 { get }

    var offset: Int { get }
    var header: Header { get }

    func lists(in machO: MachOImage) -> [List]
    func list(in machO: MachOImage, for entry: Entry) -> List?
}

extension RelativeListListProtocol {
    public static var flagMask: UInt32 { 0 }

    public var entrySize: Int {
        numericCast(header.entsizeAndFlags & ~Self.flagMask)
    }

    public var count: Int { numericCast(header.count) }

    public func entries(in machO: MachOImage) -> [Entry] {
        let ptr = machO.ptr.advanced(by: offset)
        let sequnece = MemorySequence(
            basePointer: ptr
                .advanced(by: MemoryLayout<Header>.size)
                .assumingMemoryBound(to: Entry.Layout.self),
            numberOfElements: numericCast(header.count)
        )

        let baseOffset = offset + MemoryLayout<Header>.size
        let entrySize = MemoryLayout<Entry.Layout>.size
        return sequnece.enumerated()
            .map { i, layout in
                Entry(
                    offset: baseOffset + entrySize * i,
                    layout: layout
                )
            }
    }

    public func lists(in machO: MachOImage) -> [List] {
        entries(in: machO)
            .compactMap {
                list(in: machO, for: $0)
            }
    }
}

extension RelativeListListEntry {
    public func isLoaded(in machO: MachOImage) -> Bool {
        let cache: DyldCacheLoaded = .current

        func _isLoaded(rw: some ObjCHeaderOptimizationRWProtocol) -> Bool {
            let headerInfos = rw.headerInfos(in: cache)
            if 0 <= imageIndex , imageIndex < headerInfos.count {
                return headerInfos[AnyIndex(imageIndex)].isLoaded
            }
            return false
        }

        if let objcOptimization = cache.objcOptimization{
            if machO.is64Bit,
               let rw = objcOptimization.headerOptimizationRW64(in: cache) {
                return _isLoaded(rw: rw)
            } else if let rw = objcOptimization.headerOptimizationRW64(in: cache) {
                return _isLoaded(rw: rw)
            }
        }

        if let objcOptimization = cache.oldObjcOptimization{
            if machO.is64Bit,
               let rw = objcOptimization.headerOptimizationRW64(in: cache) {
                return _isLoaded(rw: rw)
            } else if let rw = objcOptimization.headerOptimizationRW64(in: cache) {
                return _isLoaded(rw: rw)
            }
        }

        return false
    }
}
