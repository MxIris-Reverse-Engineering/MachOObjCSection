import Foundation
import Testing
import MachOKit
@_spi(Internals) import MachOSymbols
@testable import MachOObjCSection

/// `SymbolLanguage.objectiveC` is this package's: defined here, recognized
/// here, and registered with MachOKitExtensions when the image loads.
@Suite
struct ObjectiveCSymbolLanguageTests {
    /// No test calls the registration: `MachOObjCSectionC`'s constructor
    /// ran when this test bundle loaded.
    @Test func objectiveCLanguageIsRegisteredAtLoad() {
        #expect(SymbolLanguageRegistry.shared.registeredLanguages.contains(.objectiveC))
        #expect(SymbolLanguage(ofSymbolNamed: "_OBJC_CLASS_$_NSView") == .objectiveC)
        #expect(SymbolLanguage(ofSymbolNamed: "-[NSView setNeedsDisplay:]") == .objectiveC)
    }

    @Test(arguments: [
        "-[NSView setNeedsDisplay:]",
        "+[NSColor redColor]",
        "_OBJC_CLASS_$_NSView",
        "_OBJC_METACLASS_$_NSView",
        "_OBJC_IVAR_$_NSView._frame",
        "__OBJC_$_INSTANCE_METHODS_NSView",
        "l_OBJC_PROTOCOL_$_NSCopying",
        "L_OBJC_SELECTOR_REFERENCES_",
        "_objc_msgSend$setNeedsDisplay:",
    ])
    func objectiveCRecognitionClaimsMethodsAndRuntimeSymbols(name: String) {
        #expect(name.withCString(ObjectiveCSymbolNameRecognition.recognizes))
    }

    @Test(arguments: [
        "_malloc",
        "",
        "-",
        "+x",
        "_OBJ",
        "_objc_msgSend",
        "__ZN4llvm5Value4dumpEv",
        "_$s7SwiftUI4TextVMn",
    ])
    func objectiveCRecognitionLeavesOtherNamesAlone(name: String) {
        #expect(!name.withCString(ObjectiveCSymbolNameRecognition.recognizes))
    }

    /// Foundation exports its classes' runtime symbols. MachOKitExtensions'
    /// C/C++ index keeps none of them, and keeps the C names.
    /// A static link (a Tuist static framework, a static library) loads
    /// symbol_language_registration.c, and the constructor that registers
    /// the language, only because SymbolLanguage+ObjectiveC.swift refers to
    /// its anchor: the constructor is static, so the file defines nothing
    /// else, and -ObjC does not load it either. SwiftPM links every target
    /// whole, so no test here can watch an archive leave the file out; this
    /// pins both halves of the reference instead.
    @Test func languageFileRefersToTheRegistrationAnchor() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let registrationSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/MachOObjCSectionC/symbol_language_registration.c"),
            encoding: .utf8
        )
        let languageSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/MachOObjCSection/Support/SymbolLanguage+ObjectiveC.swift"),
            encoding: .utf8
        )
        // Not static: a static function is no symbol a reference can name.
        #expect(registrationSource.contains("\nvoid objc_section_registration_anchor(void) {"))
        #expect(languageSource.contains("\n    objc_section_registration_anchor()\n"))
    }

    @Test func cAndCPlusPlusStoreLeavesObjectiveCNamesOut() throws {
        let foundation = try #require(MachOImage(name: "Foundation"))
        var objectiveCNameCount = 0
        var filedObjectiveCNameCount = 0
        var cNameCount = 0
        var filedCNameCount = 0
        for symbol in foundation.symbols where !symbol.nlist.isExternal && !symbol.nlist.isDebuggingEntry {
            let isFiled = SymbolIndexStore.shared.containsSymbol(named: symbol.name, in: foundation)
            switch SymbolLanguage(ofSymbolNamed: symbol.name) {
            case .objectiveC:
                objectiveCNameCount += 1
                if isFiled { filedObjectiveCNameCount += 1 }
            case .c:
                cNameCount += 1
                if isFiled { filedCNameCount += 1 }
            default:
                break
            }
        }
        #expect(objectiveCNameCount > 0)
        #expect(filedObjectiveCNameCount == 0)
        #expect(cNameCount > 0)
        #expect(filedCNameCount == cNameCount)
    }
}
