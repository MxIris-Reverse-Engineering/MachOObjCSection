//
//  FullDyldCache+.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2025/09/28
//  
//

import Foundation
@_spi(Support) import MachOKit
#if compiler(>=6.0) || (compiler(>=5.10) && hasFeature(AccessLevelOnImport))
internal import FileIO
#else
@_implementationOnly import FileIO
#endif

extension FileHandleHolder<any FileHandleIdentity & AnyObject, FullDyldCache.File> {
    fileprivate static let shared: FileHandleHolder<Owner, File> = .init()
}

extension FullDyldCache {
    internal typealias File = ConcatenatedMemoryMappedFile

    var fileHandle: File {
        FileHandleHolder.shared.fileHandle(
            for: fileHandleIdentity,
            initialize: {
                try! .open(
                    urls: urls,
                    isWritable: false
                )
            }
        )
    }
}

extension FullDyldCache {
    func fileSegment(forOffset offset: UInt64) -> File.FileSegment? {
        try? fileHandle._file(for: numericCast(offset))
    }
}

extension FullDyldCache {
    /// Locate a value for a given optional KeyPath within this cache hierarchy.
    ///
    /// This resolves the value by checking:
    /// 1. The main cache
    /// 2. Any subcaches derived from `mainCache`
    ///
    /// - Parameter keyPath: A keyPath returning an optional value.
    /// - Returns: A tuple of `(cache, value)` if resolved, or `nil` if not found.
    @inline(__always)
    func locateValue<V>(
        _ keyPath: KeyPath<DyldCache, V?>
    ) -> DyldCache.LocatedValue<V>? {
        locateValue({ $0[keyPath: keyPath] })
    }
}

extension FullDyldCache {
    /// Locate a value using a custom resolver function running against each cache in the hierarchy.
    ///
    /// Resolution order:
    /// 1. The main cache
    /// 2. Each subcache of the main cache
    ///
    /// - Parameter resolver: A closure returning an optional value for a given DyldCache.
    /// - Parameter excludedCache: A cache to skip because it has already been checked.
    /// - Returns: A tuple of `(cache, value)` if resolution is successful; otherwise `nil`.
    @inline(__always)
    func locateValue<V>(
        _ resolver: (DyldCache) throws -> V?,
        excluding excludedCache: DyldCache? = nil
    ) rethrows -> DyldCache.LocatedValue<V>? {
        let excludedURL = excludedCache?.url

        let mainCache = mainCache
        if mainCache.url != excludedURL,
           let value = try resolver(mainCache) {
            return (mainCache, value)
        }

        for subCache in subCaches {
            if subCache.url == excludedURL {
                continue
            }

            if let value = try resolver(subCache) {
                return (subCache, value)
            }
        }
        return nil
    }
}
