//
//  ObjCClassRWDataExtProtocol.swift
//
//
//  Created by p-x9 on 2024/10/31
//
//

import Foundation
import MachOKit

public protocol ObjCClassRWDataExtProtocol {
    associatedtype Layout: _ObjCClassRWDataExtLayoutProtocol
    associatedtype ObjCClassROData: ObjCClassRODataProtocol
    associatedtype ObjCProtocolArray: ObjCProtocolArrayProtocol

    var layout: Layout { get }
    var offset: Int { get }

    func classROData(in machO: MachOImage) -> ObjCClassROData?

    func methods(in machO: MachOImage) -> ObjCMethodArray?
    func properties(in machO: MachOImage) -> ObjCPropertyArray?
    func protocols(in machO: MachOImage) -> ObjCProtocolArray?
    func demangledName(in machO: MachOImage) -> String?
}

