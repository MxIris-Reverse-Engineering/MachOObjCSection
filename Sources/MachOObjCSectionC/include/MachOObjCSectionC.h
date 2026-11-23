//
//  MachOObjCSectionC.h
//  MachOObjCSectionC
//
//  The module's umbrella header: every header in this directory, and a new
//  one goes here too (MachOObjCSectionCUmbrellaHeaderTests checks).
//
//  Without it, SwiftPM and Tuist give the module the whole directory as its
//  umbrella. A header added to the directory then changes no file a
//  prebuilt module recorded, so Xcode keeps reusing the module built before
//  it and Swift reports the new declarations as not in scope. Listing the
//  header here edits this file, which rebuilds the module.
//

#ifndef MACHO_OBJC_SECTION_C_H
#define MACHO_OBJC_SECTION_C_H

#include "memory_probe.h"
#include "objc_class_data.h"
#include "objc_os.h"
#include "symbol_language_registration.h"

#endif
