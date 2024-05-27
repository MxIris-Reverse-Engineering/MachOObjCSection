//
//  ObjCProtocolListHeader.swift
//
//
//  Created by p-x9 on 2024/05/25
//  
//

import Foundation
import MachOKit

public struct ObjCProtocolListHeader32 {
    public let count: UInt32
}

public struct ObjCProtocolListHeader64 {
    public let count: UInt64
}
