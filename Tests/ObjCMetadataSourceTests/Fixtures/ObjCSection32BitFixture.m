// Source of libObjCSection32BitFixture.dylib, an arm64_32 (watchOS) image
// whose method lists the linker emits in the relative format, each name an
// offset to a 4-byte selector reference. Rebuild it with:
//
//   xcrun --sdk watchos clang -arch arm64_32 -mwatchos-version-min=9.0 \
//     -dynamiclib -fobjc-arc -framework Foundation \
//     -install_name @rpath/libObjCSection32BitFixture.dylib \
//     -o libObjCSection32BitFixture.dylib ObjCSection32BitFixture.m

#import <Foundation/Foundation.h>

@interface ObjCSection32BitFixture : NSObject
- (NSInteger)fixtureValue;
- (void)setFixtureValue:(NSInteger)value;
- (NSString *)fixtureDescriptionWithPrefix:(NSString *)prefix suffix:(NSString *)suffix;
+ (instancetype)fixtureWithValue:(NSInteger)value;
@end

@implementation ObjCSection32BitFixture
- (NSInteger)fixtureValue { return 0; }
- (void)setFixtureValue:(NSInteger)value {}
- (NSString *)fixtureDescriptionWithPrefix:(NSString *)prefix suffix:(NSString *)suffix { return prefix; }
+ (instancetype)fixtureWithValue:(NSInteger)value { return [self new]; }
@end
