//
//  OwnerAttachedValues.swift
//  MachOObjCSection
//

import Foundation

/// Values that hang off an owner object and go away with it — what
/// `FileHandleHolder` does for file handles, for any other per-owner value.
internal final class OwnerAttachedValues<
    Owner: AnyObject,
    Value: AnyObject
>: @unchecked Sendable {
    private let lock = NSLock()

#if !canImport(ObjectiveC)
    private var valuesByOwner = WeakKeyStrongValueMap<Owner, Value>()
#endif

    init() {}

    /// The value hanging off `owner`, created on the first request.
    func value(
        for owner: Owner,
        creating create: () -> Value
    ) -> Value {
        lock.lock()
        defer { lock.unlock() }

#if canImport(ObjectiveC)
        let associationKey = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        if let value = objc_getAssociatedObject(owner, associationKey) as? Value {
            return value
        }
        let value = create()
        objc_setAssociatedObject(owner, associationKey, value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return value
#else
        if let value = valuesByOwner.object(forKey: owner) {
            return value
        }
        let value = create()
        valuesByOwner.setObject(value, forKey: owner)
        return value
#endif
    }
}
