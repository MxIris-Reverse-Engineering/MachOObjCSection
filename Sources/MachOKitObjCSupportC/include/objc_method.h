//
//  objc_method.h
//  
//
//  Created by p-x9 on 2024/05/16
//  
//

#ifndef objc_method_h
#define objc_method_h

#include <stdint.h>
#include <objc/runtime.h>
#include <ptrauth.h>

#if TARGET_OS_EXCLAVEKIT
    // No TBI on ExclaveKit, but we assume *all* big method lists are signed
    static const uintptr_t bigSignedMethodListFlag = 0x0;
#elif __has_feature(ptrauth_calls)
    // This flag is ORed into method list pointers to indicate that the list is
    // a big list with signed pointers. Use a bit in TBI so we don't have to
    // mask it out to use the pointer.
    static const uintptr_t bigSignedMethodListFlag = 0x80000000/*0x8000000000000000*/;
#else
    static const uintptr_t bigSignedMethodListFlag = 0x0;
#endif

#if TARGET_OS_EXCLAVEKIT && __has_feature(ptrauth_calls)
#define ptrauth_method_list_types \
    __ptrauth(ptrauth_key_process_dependent_data, 1, \
    ptrauth_string_discriminator("method_t::bigSigned::types"))
#define ptrauth_objc_sel __ptrauth_objc_sel
#else
#define ptrauth_method_list_types
#define ptrauth_objc_sel
#endif

struct method_t_big {
    SEL name;
    const char *types;
    IMP __ptrauth_objc_method_list_imp imp;
};

struct method_t_bigSigned {
    SEL __ptrauth_objc_sel name;
    const char * ptrauth_method_list_types types;
    IMP __ptrauth_objc_method_list_imp imp;
};

#endif /* objc_method_h */
