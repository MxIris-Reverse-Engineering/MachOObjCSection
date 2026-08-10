import Foundation

/// A minimal mutual-exclusion box around a value.
///
/// Reimplemented locally instead of using FrameworkToolbox's `@Mutex` macro:
/// that macro is Apple-platform only (it builds on `os_unfair_lock`), and
/// MachOObjCSection supports Linux. `Synchronization.Mutex` is not an option
/// either — it requires macOS 15, while this package's floor is macOS 10.15.
///
/// `NSLock` is available on every platform Foundation runs on. The indexer
/// takes the lock once per property access while building an index, not in a
/// tight inner loop, so the difference against `os_unfair_lock` is not
/// material here.
final class Mutex<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ initialValue: Value) {
        self.value = initialValue
    }

    /// Runs `body` with exclusive access to the protected value.
    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
