import Testing
import Foundation
import MachOKit
import MachOKitExtensions
@testable import MachOObjCSection

/// The running system's dyld shared cache, whichever architecture this machine
/// is. `nil` when there is none to read, which gates the suite off rather than
/// failing it.
private func systemDyldSharedCachePath() -> String? {
    ["arm64e", "x86_64h", "x86_64"]
        .map { "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_\($0)" }
        .first { FileManager.default.fileExists(atPath: $0) }
}

/// Two lookups that used to subtract the shared region's start from a value
/// that need not be an address in it, and trapped when the value was below.
/// A pointer slot still in its slide info encoding is such a value — under
/// slide info v5 it is an offset from the cache start — and so is the raw
/// value `resolveRebase` falls back to for a slot it cannot resolve. Neither
/// depends on the slide info version, so the running system's cache reaches
/// both.
@Suite(
    "A value below the shared region resolves to nothing",
    .enabled(if: systemDyldSharedCachePath() != nil)
)
struct SharedRegionAddressGuardTests {
    private static func foundationInSystemCache() throws -> MachOFile {
        let cachePath = try #require(systemDyldSharedCachePath())
        let cache = try DyldCache(url: URL(fileURLWithPath: cachePath))
        return try #require(cache.machOFile(by: .name("Foundation")), "no Foundation image in the system cache")
    }

    /// `0x24B0EDE` is the slot that took the macOS 15.0 cache down: a types
    /// pointer of `NSXPCListenerDelegate`, stored as its offset from the cache
    /// start.
    @Test("An address below the shared region has no file location")
    func addressBelowSharedRegionHasNoFileLocation() throws {
        let foundation = try Self.foundationInSystemCache()
        #expect(foundation.fileHandleAndOffset(forAddress: 0x24B0EDE) == nil)
    }

    /// A null slot has no rebase to resolve, so `resolveRebase` falls back to
    /// the raw value: zero, far below the shared region.
    @Test("A null slot resolves to nothing")
    func nullSlotResolvesToNothing() throws {
        let foundation = try Self.foundationInSystemCache()
        let protocolRecords = try #require(foundation.objc.protocols64, "Foundation has no protocol list")
        let coding = try #require(protocolRecords.first { $0.mangledName(in: foundation) == "NSCoding" }, "Foundation defines no NSCoding")
        let classMethodsSlot = coding.unresolvedValue(of: .classMethods)

        // The premise: NSCoding declares no class method, so its slot is null.
        try #require(classMethodsSlot.value == 0)
        #expect(foundation.resolveRebase(classMethodsSlot) == nil)
    }
}
