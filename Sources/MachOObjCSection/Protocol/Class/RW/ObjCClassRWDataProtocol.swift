//
//  ObjCClassRWDataProtocol.swift
//
//
//  Created by p-x9 on 2024/10/31
//  
//

import Foundation
@_spi(Support) import MachOKit

public protocol ObjCClassRWDataProtocol {
    associatedtype Layout: _ObjCClassRWDataLayoutProtocol
    associatedtype ObjCClassROData: ObjCClassRODataProtocol
    associatedtype ObjCClassRWDataExt: ObjCClassRWDataExtProtocol

    var layout: Layout { get }
    var offset: Int { get }

    func classROData(in machO: MachOImage) -> ObjCClassROData?
    func ext(in machO: MachOImage) -> ObjCClassRWDataExt?
}

extension ObjCClassRWDataProtocol {
    public var flags: ObjCClassRWDataFlags {
        .init(rawValue: layout.flags)
    }

    public var index: Int {
        numericCast(layout.index)
    }

    public var hasRO: Bool {
        layout.ro_or_rw_ext & 1 == 0
    }

    public var hasExt: Bool {
        layout.ro_or_rw_ext & 1 != 0
    }
}
