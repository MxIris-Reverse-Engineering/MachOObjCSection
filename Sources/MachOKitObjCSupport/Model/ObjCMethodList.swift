//
//  ObjCMethodList.swift
//
//
//  Created by p-x9 on 2024/05/16
//  
//

import Foundation

// https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L707

public struct ObjCMethodList {
    static let FlagMask: UInt32 = 0xffff0003

    struct Header {
        let entsizeAndFlags: UInt32
        let count: UInt32
    }

    let header: Header
}

extension ObjCMethodList {
    public var entrySize: Int {
        numericCast(header.entsizeAndFlags & ~Self.FlagMask)
    }

    public var flags: UInt32 {
        header.entsizeAndFlags & Self.FlagMask
    }

    public var count: Int {
        numericCast(header.count)
    }

    public var listKind: ObjCMethod.Kind {
        if header.entsizeAndFlags & numericCast(bigSignedMethodListFlag >> 8) != 0 {
            return .bigSigned
        }
        if flags & 0x80000000 != 0 {
            return .small
        }
        return .big
    }
}

extension ObjCMethodList {
    public func methods(sectionStart: UnsafeRawPointer) -> AnyRandomAccessCollection<ObjCMethod> {
        let start = sectionStart.advanced(by: MemoryLayout<Header>.size)
        switch listKind {
        case .big:
            let sequence = MemorySequence(
                basePointer: start.assumingMemoryBound(to: ObjCMethod.Big.self),
                numberOfElements: count
            )
            return AnyRandomAccessCollection(
                sequence
                    .map { ObjCMethod($0) }
            )

        case .bigSigned:
            let sequence = MemorySequence(
                basePointer: start.assumingMemoryBound(to: ObjCMethod.BigSigned.self),
                numberOfElements: count
            )
            return AnyRandomAccessCollection(
                sequence
                    .map { ObjCMethod($0) }
            )

        case .small:
            let sequence = MemorySequence(
                basePointer: start.assumingMemoryBound(to: ObjCMethod.Small.self),
                numberOfElements: count
            )
            let size = MemoryLayout<ObjCMethod.Small>.size
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
