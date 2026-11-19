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
