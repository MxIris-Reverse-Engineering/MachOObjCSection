// Source of libObjCSection64BitFixture.dylib, the arm64 (macOS) counterpart of
// ObjCSection32BitFixture.m: the same relative method lists, with 8-byte
// selector references. It also holds ObjCSection64BitIvarLayoutFixture, whose
// eight non-pointer words before a strong ivar give it the ivar layout byte
// 0x81 (skip 8 words, then 1 strong one). Rebuild it with:
//
//   xcrun --sdk macosx clang -arch arm64 -mmacosx-version-min=13.0 \
//     -dynamiclib -fobjc-arc -framework Foundation \
//     -install_name @rpath/libObjCSection64BitFixture.dylib \
//     -o libObjCSection64BitFixture.dylib ObjCSection64BitFixture.m

#import <Foundation/Foundation.h>

@interface ObjCSection64BitFixture : NSObject
- (NSInteger)fixtureValue;
- (void)setFixtureValue:(NSInteger)value;
- (NSString *)fixtureDescriptionWithPrefix:(NSString *)prefix suffix:(NSString *)suffix;
+ (instancetype)fixtureWithValue:(NSInteger)value;
@end

@implementation ObjCSection64BitFixture
- (NSInteger)fixtureValue { return 0; }
- (void)setFixtureValue:(NSInteger)value {}
- (NSString *)fixtureDescriptionWithPrefix:(NSString *)prefix suffix:(NSString *)suffix { return prefix; }
+ (instancetype)fixtureWithValue:(NSInteger)value { return [self new]; }
@end

@interface ObjCSection64BitIvarLayoutFixture : NSObject
@end

@implementation ObjCSection64BitIvarLayoutFixture {
    uint64_t _first;
    uint64_t _second;
    uint64_t _third;
    uint64_t _fourth;
    uint64_t _fifth;
    uint64_t _sixth;
    uint64_t _seventh;
    uint64_t _eighth;
    id _object;
}
@end
