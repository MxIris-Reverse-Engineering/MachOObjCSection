//
//  MachOObjCSectionRepresentable.swift
//  MachOObjCSection
//
//  Created by MxIris-Reverse-Engineering on 2026-04-23.
//

import MachOKit

/// Constraint surface for any MachO that exposes the Objective-C metadata
/// trait (ObjCSection). MachOFile and MachOImage both conform; downstream
/// (MachOKitUI) gates ObjC-section builders on this single constraint.
///
/// The supertype is `MachORepresentable` rather than the stronger
/// `MachORepresentableWithCache` (which lives in MachOSwiftSection's
/// MachOExtensions module). Pulling MachOExtensions in here would create
/// a package-level cycle (MachOSwiftSection already depends on
/// MachOObjCSection's higher-level products), so we trade the `cache` /
/// `identifier` requirements for cycle-freedom. UI consumers that need
/// those bits can grab them from `MachOFile` / `MachOImage` directly.
public protocol MachOObjCSectionRepresentable: MachORepresentable {
    associatedtype ObjCSection: ObjCSectionRepresentable

    /// Accessor for the Objective-C metadata trait of this MachO.
    var objc: ObjCSection { get }
}

extension MachOFile: MachOObjCSectionRepresentable {}
extension MachOImage: MachOObjCSectionRepresentable {}
