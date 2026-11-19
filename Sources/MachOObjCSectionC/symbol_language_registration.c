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

// Defined in the `MachOObjCSection` module with `@_cdecl`.
extern void objc_section_register_symbol_language(void);

__attribute__((constructor))
static void registerSymbolLanguageAtLoad(void) {
    objc_section_register_symbol_language();
}
