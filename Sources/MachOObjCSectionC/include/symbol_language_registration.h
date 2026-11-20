//
//  symbol_language_registration.h
//  MachOObjCSectionC
//
//  The anchor of the load-time registration in symbol_language_registration.c.
//

#ifndef OBJC_SECTION_SYMBOL_LANGUAGE_REGISTRATION_H
#define OBJC_SECTION_SYMBOL_LANGUAGE_REGISTRATION_H

/// Does nothing. Calling it makes a static link that loads the caller load
/// symbol_language_registration.c — and its constructor — too.
void objc_section_registration_anchor(void);

#endif
