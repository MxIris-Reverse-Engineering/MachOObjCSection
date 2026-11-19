import MachOSymbols

extension SymbolLanguage {
    /// An Objective-C method implementation (`-[…]`, `+[…]`) or a symbol of
    /// the Objective-C runtime (`_OBJC_…`, `__OBJC_…`, `l_OBJC_…`,
    /// `L_OBJC_…`, `_objc_msgSend$…`).
    ///
    /// Registered with MachOKitExtensions' `SymbolLanguageRegistry` when the
    /// image holding this module loads, so MachOKitExtensions'
    /// `SymbolIndexStore` keeps only where these symbols sit. Its name,
    /// `"Objective-C"`, is its identity.
    public static let objectiveC = SymbolLanguage(rawValue: "Objective-C")
}

/// The rules that tell an Objective-C symbol name from its leading bytes.
enum ObjectiveCSymbolNameRecognition {
    static func recognizes(_ name: UnsafePointer<CChar>) -> Bool {
        switch UInt8(bitPattern: name.pointee) {
        case UInt8(ascii: "-"), UInt8(ascii: "+"):
            UInt8(bitPattern: name[1]) == UInt8(ascii: "[")
        case UInt8(ascii: "_"):
            hasPrefix(name, "_OBJC_") || hasPrefix(name, "__OBJC_") || hasPrefix(name, "_objc_msgSend$")
        case UInt8(ascii: "l"):
            hasPrefix(name, "l_OBJC_")
        case UInt8(ascii: "L"):
            hasPrefix(name, "L_OBJC_")
        default:
            false
        }
    }

    /// Whether the NUL-terminated `name` starts with `prefix`. Never reads
    /// past the terminator: the prefixes hold no NUL byte, so a shorter name
    /// mismatches at its terminator first.
    private static func hasPrefix(_ name: UnsafePointer<CChar>, _ prefix: StaticString) -> Bool {
        prefix.withUTF8Buffer { prefixBytes in
            for (index, prefixByte) in prefixBytes.enumerated() where UInt8(bitPattern: name[index]) != prefixByte {
                return false
            }
            return true
        }
    }
}

/// Registers ``SymbolLanguage/objectiveC``. `MachOObjCSectionC`'s
/// constructor calls it once, when the image loads.
@_cdecl("objc_section_register_symbol_language")
func registerObjectiveCSymbolLanguage() {
    SymbolLanguageRegistry.shared.register(.objectiveC, where: ObjectiveCSymbolNameRecognition.recognizes)
}
