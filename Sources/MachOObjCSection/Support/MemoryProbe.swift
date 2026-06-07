//
//  MemoryProbe.swift
//  MachOObjCSection
//
//  Lightweight check for whether a virtual address is mapped and readable
//  in the current task. The ObjC runtime stores some `class_rw_t` /
//  `class_rw_ext_t` fields as preopt cache offsets that only resolve when
//  the matching dyld shared cache is mapped — when a foreign-platform
//  binary (e.g. an iOS simulator framework) is `dlopen`'d on a macOS host,
//  those fields can contain stale low addresses (`0x...c04001` style) that
//  segfault on dereference. Probing first lets us bail out cleanly.
//

import Foundation
import MachOObjCSectionC

@inline(__always)
internal func isPointerSafelyReadable(
    _ ptr: UnsafeRawPointer,
    length: Int = 1
) -> Bool {
    MachOObjCSectionIsMemoryReadable(ptr, length)
}
