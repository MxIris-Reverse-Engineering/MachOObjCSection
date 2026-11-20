//
//  symbol_language_registration.c
//  MachOObjCSectionC
//
//  Registers `SymbolLanguage.objectiveC` with MachOKitExtensions' symbol
//  language registry when the image holding this package loads, so that
//  every classification and the C/C++ symbol index see the language before
//  any code asks. Swift has no load-time initializers; a constructor here,
//  in the C target `MachOObjCSection` depends on, runs with no caller
//  involved.
//

#include "symbol_language_registration.h"

// Defined in the `MachOObjCSection` module with `@_cdecl`.
extern void objc_section_register_symbol_language(void);

__attribute__((constructor))
static void registerSymbolLanguageAtLoad(void) {
    objc_section_register_symbol_language();
}

// A linker that reads MachOObjCSectionC from a static archive (a Tuist static
// framework, a static library) loads an object only for a symbol something
// refers to, and -ObjC does not load an object that defines no Objective-C
// class or category and no Swift type. The constructor above is static, so
// without this function the object would define nothing and never be loaded:
// the image would run without the Objective-C symbol language registered.
// MachOObjCSection calls this function from the file that registers the
// language, which every link with -ObjC loads.
void objc_section_registration_anchor(void) {}
