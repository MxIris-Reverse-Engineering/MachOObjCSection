//
//  RelativeDirectPointer.swift
//
//
//  Created by p-x9 on 2024/05/16
//
//

// https://github.com/apple/swift/blob/98e65d015979c7b5a58a6ecf2d8598a6f7c85794/include/swift/Basic/RelativePointer.h#L391

public struct RelativeDirectPointer<T> {
    public typealias Offset = UInt32

    public var rawPointer: RelativeDirectRawPointer

    public var isNull: Bool {
        rawPointer.isNull
    }

    public func address(from ptr: UnsafeRawPointer) -> UnsafeRawPointer {
        rawPointer.address(from: ptr)
    }

    public func pointee(from ptr: UnsafeRawPointer) -> T {
        address(from: ptr)
            .assumingMemoryBound(to: T.self)
            .pointee
    }
}

public struct RelativeDirectRawPointer {
    public typealias Offset = UInt32

    public var offset: Offset

    public var isNull: Bool {
        offset == 0
    }

    public func address(from ptr: UnsafeRawPointer) -> UnsafeRawPointer {
        ptr + numericCast(offset)
    }
}
