//
//  ObjCMethod.swift
//  
//
//  Created by p-x9 on 2024/05/16
//  
//

import Foundation
import ptrauth

// https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L925

public struct ObjCMethod {
    let name: Selector
    let types: String
    let imp: IMP

    init(name: Selector, types: String, imp: IMP) {
        self.name = name
        self.types = types
        self.imp = imp
    }
}

extension ObjCMethod {
    public enum Kind: UInt32 {
        case big
        case small
        case bigSigned
    }
}

extension ObjCMethod {
    public struct Small {
        let name: RelativeDirectPointer<Selector>
        let types: RelativeDirectPointer<CChar>
        let imp: RelativeDirectPointer<IMP>
    }

    init(_ small: Small, at pointer: UnsafeRawPointer) {
        self.init(
            name: small.name.pointee(from: pointer),
            types: .init(
                cString: small.types
                    .address(from: pointer.advanced(by: 4))
                    .assumingMemoryBound(to: CChar.self)
            ),
            imp: small.imp.pointee(from: pointer.advanced(by: 8))
        )
    }
}

extension ObjCMethod {
    public struct Big: LayoutWrapper {
        public typealias Layout = method_t_big

        public var layout: Layout
    }

    init(_ big: Big) {
        self.init(
            name: big.name,
            types: .init(cString: big.types),
            imp: big.imp
        )
    }
}

extension ObjCMethod {
    public struct BigSigned: LayoutWrapper {
        public typealias Layout = method_t_bigSigned

        public var layout: Layout
    }

    init(_ bigSigned: BigSigned) {
        self.init(
            name: bigSigned.name,
            types: .init(cString: bigSigned.types),
            imp: bigSigned.imp
        )
    }
}
