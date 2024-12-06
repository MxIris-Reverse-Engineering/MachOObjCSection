//
//  ObjCCategoryProtocol.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/12/06
//  
//

import Foundation
@_spi(Support) import MachOKit

public protocol ObjCCategoryProtocol: _FixupResolvable where LayoutField == ObjCCategoryLayoutField {
    associatedtype Layout: _ObjCCategoryLayoutProtocol
    associatedtype ObjCClass: ObjCClassProtocol
    typealias ObjCProtocolList = ObjCClass.ClassROData.ObjCProtocolList

    var layout: Layout { get }
    var offset: Int { get }

    var isCatlist2: Bool { get }

    @_spi(Core)
    init(layout: Layout, offset: Int, isCatlist2: Bool)
}
