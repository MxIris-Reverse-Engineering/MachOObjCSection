//
//  ObjCIvarProtocol.swift
//
//
//  Created by p-x9 on 2024/08/22
//  
//

import Foundation
@_spi(Support) import MachOKit

public protocol ObjCIvarProtocol {
    associatedtype Layout: _ObjCIvarLayoutProtocol

    var layout: Layout { get }
    var offset: Int { get }

    func offset(in machO: MachOFile) -> UInt32?
    func name(in machO: MachOFile) -> String?
    func type(in machO: MachOFile) -> String?

    func offset(in machO: MachOImage) -> UInt32?
    func name(in machO: MachOImage) -> String
    func type(in machO: MachOImage) -> String
}

extension ObjCIvarProtocol {
    public func offset(in machO: MachOImage) -> UInt32? {
        let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.offset)
        )
        return ptr!.assumingMemoryBound(to: UInt32.self).pointee
    }

    public func name(in machO: MachOImage) -> String {
        let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.name)
        )
        return .init(cString: ptr!.assumingMemoryBound(to: CChar.self))
    }

    public func type(in machO: MachOImage) -> String {
        let ptr = UnsafeRawPointer(
            bitPattern: UInt(layout.type)
        )
        return .init(cString: ptr!.assumingMemoryBound(to: CChar.self))
    }
}

extension ObjCIvarProtocol where Self: LayoutWrapper {
    func resolveRebase(
        _ keyPath: PartialKeyPath<Layout>,
        in machO: MachOFile
    ) -> UInt64? {
        let offset = self.offset + layoutOffset(of: keyPath)
        if let resolved = machO.resolveRebase(at: UInt64(offset)) {
            if let cache = machO.cache {
                return resolved - cache.header.sharedRegionStart
            }
            return resolved
        }
        return nil
    }

    func isBind(
        _ keyPath: PartialKeyPath<Layout>,
        in machO: MachOFile
    ) -> Bool {
        let offset = self.offset + layoutOffset(of: keyPath)
        return machO.isBind(offset)
    }
}
