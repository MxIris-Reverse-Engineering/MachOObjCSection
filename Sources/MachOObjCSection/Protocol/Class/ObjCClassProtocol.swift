//
//  ObjCClassProtocol.swift
//
//
//  Created by p-x9 on 2024/08/06
//  
//

import Foundation
@_spi(Support) import MachOKit
import MachOObjCSectionC

public protocol ObjCClassProtocol: _FixupResolvable where LayoutField == ObjCClassLayoutField {
    associatedtype Layout: _ObjCClassLayoutProtocol
    associatedtype ClassROData: LayoutWrapper, ObjCClassRODataProtocol where ClassROData.Layout.Pointer == Layout.Pointer
    associatedtype ClassRWData: LayoutWrapper, ObjCClassRWDataProtocol where ClassRWData.Layout.Pointer == Layout.Pointer

    var layout: Layout { get }
    var offset: Int { get }

    func metaClass(in machO: MachOFile) -> Self?
    func superClass(in machO: MachOFile) -> Self?
    func superClassName(in machO: MachOFile) -> String?
    func classROData(in machO: MachOFile) -> ClassROData?

    func hasRWPointer(in machO: MachOImage) -> Bool

    func metaClass(in machO: MachOImage) -> Self?
    func superClass(in machO: MachOImage) -> Self?
    func superClassName(in machO: MachOImage) -> String?
    func classROData(in machO: MachOImage) -> ClassROData?
    func classRWData(in machO: MachOImage) -> ClassRWData?

    func version(in machO: MachOFile) -> Int32
    func version(in machO: MachOImage) -> Int32
}

extension ObjCClassProtocol {
    /// class is a Swift class from the pre-stable Swift ABI
    public var isSwiftLegacy: Bool {
        layout.dataVMAddrAndFastFlags & numericCast(FAST_IS_SWIFT_LEGACY) != 0
    }

    /// class is a Swift class from the stable Swift ABI
    public var isSwiftStable: Bool {
        layout.dataVMAddrAndFastFlags & numericCast(FAST_IS_SWIFT_STABLE) != 0
    }

    public var isSwift: Bool {
        isSwiftStable || isSwiftLegacy
    }
}
