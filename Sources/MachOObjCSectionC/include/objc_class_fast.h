//
//  objc_class_fast.h
//
//
//  Created by p-x9 on 2024/09/24
//  
//

#ifndef objc_class_fast_h
#define objc_class_fast_h

// ref: https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L137
#define FAST_DATA_MASK_64_IPHONE   0x0f00007ffffffff8UL
#define FAST_DATA_MASK_64          0x0f007ffffffffff8UL
#define FAST_DATA_MASK_32          0xfffffffcUL

#endif /* objc_class_fast_h */
