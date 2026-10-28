//
//  DyldCacheRepresentable+.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2025/10/12
//  
//

import Foundation
import MachOKit

/// What the name of a method in a relative method list the dyld cache builder
/// wrote counts its offset from.
///
/// Such a list (flag `0x40000000`) names each method by an offset straight to
/// its selector string rather than to a selector reference, and where that
/// offset starts changed with macOS 12.
enum RelativeMethodNameBase: Equatable {
    /// The selector the cache builder picked as the base, `@selector(🤯)`, at
    /// this offset from the main cache's start. objc4-838 (macOS 12, iOS 15)
    /// reads names this way; `objc_opt_t` v16 and the `objc_opts` header that
    /// replaced it record the base.
    case selectorBase(offset: UInt64)
    /// The name field itself, like every other relative offset. objc4-818
    /// (macOS 11, iOS 14) reads names this way; `objc_opt_t` v15 and earlier
    /// record no base.
    case nameField

    /// The offset, from the main cache's start, that the name in the name
    /// field at `nameFieldOffset` counts from.
    func offset(forNameFieldAt nameFieldOffset: UInt64) -> UInt64 {
        switch self {
        case .selectorBase(let offset): offset
        case .nameField: nameFieldOffset
        }
    }
}

extension DyldCacheRepresentable {
    /// Decided by the version of the cache's Objective-C optimization data,
    /// not by whether it records a base: a cache whose data cannot be read is
    /// `nil`, so a failed read of a newer cache is not taken for a macOS 11 one.
    var relativeMethodNameBase: RelativeMethodNameBase? {
        if let objcOpt = objcOptimization {
            return .selectorBase(offset: objcOpt.relativeMethodSelectorBaseAddressOffset)
        }
        switch oldObjcOptimization {
        case let .v16(oldObjCOptimization16)?:
            return .selectorBase(
                offset: numericCast(oldObjCOptimization16.relativeMethodSelectorBaseAddressOffset) + numericCast(oldObjCOptimization16.offset)
            )
        case .v12?, .v13?, .v15?:
            return .nameField
        case nil:
            return nil
        }
    }
}
