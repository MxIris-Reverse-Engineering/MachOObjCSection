//
//  MachORepresentable+.swift
//
//
//  Created by p-x9 on 2024/09/25
//  
//

import Foundation
import MachOKit

extension MachORepresentable {
    var isPhysicalIPhone: Bool {
        if let cache = (self as? MachOFile)?.cache {
            return cache.header.platform == .iOS
        }
        guard let buildVersion = loadCommands.info(of: LoadCommand.buildVersion) else {
            return false
        }
        return buildVersion.platform == .iOS
    }

    var isSimulatorIPhone: Bool {
        if let cache = (self as? MachOFile)?.cache {
            return cache.header.platform == .iOSSimulator
        }
        guard let buildVersion = loadCommands.info(of: LoadCommand.buildVersion) else {
            return false
        }
        return buildVersion.platform == .iOSSimulator
    }
}

extension MachORepresentable {
    func sectionNumber(for section: ObjCMachOSection) -> Int? {
        guard let index = sections.firstIndex(where: {
            $0.sectionName == section.rawValue
        }) else { return nil }
        return index + 1
    }
}
