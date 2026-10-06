//
//  FileHandleHolder.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2026/02/09
//  
//

import Foundation
#if compiler(>=6.0) || (compiler(>=5.10) && hasFeature(AccessLevelOnImport))
internal import FileIO
#else
@_implementationOnly import FileIO
#endif

internal final class FileHandleHolder<
    Owner: AnyObject,
    File: FileIOProtocol & AnyObject
>: @unchecked Sendable {
    private let lock: NSRecursiveLock = .init()

#if !canImport(ObjectiveC)
    private var _mapTable = WeakKeyStrongValueMap<Owner, File>()
#endif

    init() {}

    @inline(__always)
    @_optimize(speed)
    func fileHandle(
        for owner: Owner,
        initialize: () -> File
    ) -> File {
        lock.lock()
        defer { lock.unlock() }

#if canImport(ObjectiveC)
        // The file hangs off its owner and goes away with it. A weak-to-strong
        // `NSMapTable` keeps the value of a key that went away until the table
        // next resizes, so the mapping of a dropped cache stayed open.
        let associationKey = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        if let fileHandle = objc_getAssociatedObject(owner, associationKey) as? File {
            return fileHandle
        }
        let fileHandle = initialize()
        objc_setAssociatedObject(owner, associationKey, fileHandle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return fileHandle
#else
        if let fileHandle = _mapTable.object(forKey: owner) {
            return fileHandle
        } else {
            let fileHandle = initialize()
            _mapTable.setObject(fileHandle, forKey: owner)
            return fileHandle
        }
#endif
    }
}
