import MachOSymbols
import MachOObjCSectionC

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
///
/// Public, behind an SPI nobody imports, only so that its C symbol keeps
/// external linkage. Internal, the symbol is hidden, and Xcode links each
/// package target into a single relocatable object (`ld -r`) first, which
/// turns a hidden symbol local: the constructor, in another target, then
/// fails to link in a Release build ("Undefined symbols:
/// _objc_section_register_symbol_language").
@_spi(SymbolLanguageRegistration)
@_cdecl("objc_section_register_symbol_language")
public func registerObjectiveCSymbolLanguage() {
    SymbolLanguageRegistry.shared.register(.objectiveC, where: ObjectiveCSymbolNameRecognition.recognizes)
    // Does nothing at run time. The reference is what counts: a static link
    // that loads this file (any link with -ObjC) loads
    // symbol_language_registration.c and its constructor with it, which
    // nothing else refers to. See that file.
    objc_section_registration_anchor()
}
