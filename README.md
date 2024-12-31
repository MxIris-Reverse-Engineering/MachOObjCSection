# MachOObjCSection

A Swift library for parsing mach-o files to obtain Objecteve-C information.
（Class/Protocol/Category/Image info）

> [!NOTE]
> This library is developed as an extension of [MachOKit](https://github.com/p-x9/MachOKit) for Objective-C

<!-- # Badges -->

[![Github issues](https://img.shields.io/github/issues/p-x9/MachOObjCSection)](https://github.com/p-x9/MachOObjCSection/issues)
[![Github forks](https://img.shields.io/github/forks/p-x9/MachOObjCSection)](https://github.com/p-x9/MachOObjCSection/network/members)
[![Github stars](https://img.shields.io/github/stars/p-x9/MachOObjCSection)](https://github.com/p-x9/MachOObjCSection/stargazers)
[![Github top language](https://img.shields.io/github/languages/top/p-x9/MachOObjCSection)](https://github.com/p-x9/MachOObjCSection/)

## Usage

### Basic

Objective-C information from MachOImage or MachOFile can be retrieved via the `objc` property.

The protocol named [ObjCSectionRepresentable](./Sources/MachOObjCSection/Protocol/ObjCSectionRepresentable.swift) contains the objc information that can be retrieved.

```swift
import MachOKit
import MachOObjCSection

let machO //` MachOFile` or `MachOImage`

// image info
let imageInfo = machO.objc.imageInfo

// objc classes(64bit)
let classes = machO.objc.classes64
// objc classes(32bit)
let classes = machO.objc.classes32


// objc protocols(64bit)
let classes = machO.objc.protocols64
// objc protocols(32bit)
let classes = machO.objc.protocols32

// objc category(64bit)
let classes = machO.objc.categories64
// objc category(32bit)
let classes = machO.objc.categories32
```

### Detail

#### Class

The information that can be obtained about ObjC Class is summarized in [ObjCClassProtocol](./Sources/MachOObjCSection/Protocol/Class/ObjCClassProtocol.swift).

Details such as class names and method lists can be obtained from ro(read only) data.
When retrieving from `MachOImage` in memory, it may be necessary to retrieve ro data via rw(read/write) data or further rw ext (read write external) data.

```swift
let roData: ClassROData

if let _data = classROData(in: machO) {
    roData = _data
} else if let rw = classRWData(in: machO) {
    if let _data = rw.classROData(in: machO) {
        roData = _data
    } else if let ext = rw.ext(in: machO),
              let _data = ext.classROData(in: machO) {
        roData = _data
    }
}
```

For example, to obtain a list of instance properties, write

```swift
let instancePropertyList = roData.propertyList(in: machO)!
for property in instancePropertyList.properties(in: machO) {
    print("Name: \(property.name), Attributes: \(property.attributes)")
}
```

To obtain a list of class properties or class methods, use metaclass.

```swift
let meta = cls.metaClass(in: machO)!
let roData: ClassROData64 = /* Get ro data from metaclass */
let classPropertyList = roData.propertyList(in: machO)!
for property in classPropertyList.properties(in: machO) {
    print("Name: \(property.name), Attributes: \(property.attributes)")
}
```

#### Protocol

The information that can be obtained about ObjC Protocol is summarized in [ObjCProtocolProtocol](./Sources/MachOObjCSection/Protocol/Protocol/ObjCProtocolProtocol.swift).

#### Categories

The information that can be obtained about ObjC Protocol is summarized in [ObjCCategoryProtocol](./Sources/MachOObjCSection/Protocol/Category/ObjCCategoryProtocol.swift).


### Compatible with ObjCDump library

It is compatible with the library [ObjCDump](https://github.com/p-x9/swift-objc-dump) where models such as ObjC classes are defined.
Conversion to ObjCDump models can be done via `info` properties and methods.

```swift
// property
let proeprtyInfo = property.info(isClassProperty: true)
// ivar
let ivarInfo = ivar.info(in: machO)
// method
let methodInfo = method.info(isClassMethod: true)
// class
let classInfo = cls.info(in: machO)
// protocol
let protocoInfo = proto.info(in: machO)
// category
let categoryInfo = category.info(in: machO)
```

#### Dump ObjC Header

ObjC header definitions can be retrieved from property/method/ivar/class/protocol/category model

```swift
// property
let header = propertyInfo.headerString
// ivar
let header = ivarInfo.headerString
// method
let header = methodInfo.headerString
// class
let header = classInfo.headerString
// protocol
let header =  protocolInfo.headerString
// category
let header = categoryInfo.headerString
```

<details>

<summary>Example of dumped header string</summary>

```ObjectiveC
@interface NSString : NSObject <NSItemProviderReading, NSItemProviderWriting, NSCopying, NSMutableCopying, NSSecureCoding>

@property(class, readonly, copy) NSArray *readableTypeIdentifiersForItemProvider;
@property(class, readonly, copy) NSArray *writableTypeIdentifiersForItemProvider;
@property(class, readonly) BOOL supportsSecureCoding;

@property(readonly, nonatomic) NSAttributedString *__baseAttributedString;
@property(readonly) unsigned long long hash;
@property(readonly) Class superclass;
@property(readonly, copy) NSString *description;
@property(readonly, copy) NSString *debugDescription;
@property(readonly, copy) NSArray *writableTypeIdentifiersForItemProvider;
@property(readonly, copy) NSString *stringByRemovingPercentEncoding;
@property(readonly) unsigned long long length;

+ (id)allocWithZone:(struct _NSZone *)arg0;
+ (void)initialize;
+ (id)stringWithFormat:(id)arg0;
+ (id)stringWithUTF8String:(const char *)arg0;
+ (id)string;
+ (BOOL)_subclassesMustBeExplicitlyMentionedWhenDecoded;
+ (id)stringWithCharacters:(const unsigned short *)arg0 length:(unsigned long long)arg1;
+ (BOOL)supportsSecureCoding;
+ (id)stringWithCString:(const char *)arg0 encoding:(unsigned long long)arg1;
+ (id)stringWithString:(id)arg0;
+ (id)stringWithContentsOfFile:(id)arg0 encoding:(unsigned long long)arg1 error:(id *)arg2;
+ (id)stringWithContentsOfFile:(id)arg0 usedEncoding:(unsigned long long *)arg1 error:(id *)arg2;
+ (id)localizedStringWithValidatedFormat:(id)arg0 validFormatSpecifiers:(id)arg1 error:(id *)arg2;
+ (id)_newStringFromUTF16InternalData:(id)arg0 typeIdentifier:(id)arg1 error:(id *)arg2;
+ (id)_newZStringWithCharacters:(const unsigned short *)arg0 length:(unsigned long long)arg1;
+ (id)_newZStringWithString:(id)arg0;
+ (id)_newZStringWithUTF8String:(const char *)arg0;
+ (id)_scriptStringWithPropertyAccess:(unsigned long long)arg0;
+ (id)_scriptStringWithTabCount:(unsigned long long)arg0;
+ (id)_scriptingTextWithDescriptor:(id)arg0;
+ (id)_stringWithFormat:(id)arg0 locale:(id)arg1 options:(id)arg2 arguments:(char *)arg3;
+ (id)_web_stringRepresentationForBytes:(long long)arg0;
+ (const unsigned long long *)availableStringEncodings;
+ (unsigned long long)defaultCStringEncoding;
+ (id)localizedNameOfStringEncoding:(unsigned long long)arg0;
+ (id)localizedStringWithFormat:(id)arg0;
+ (id)objectWithItemProviderData:(id)arg0 typeIdentifier:(id)arg1 error:(id *)arg2;
+ (id)pathWithComponents:(id)arg0;
+ (id)readableTypeIdentifiersForItemProvider;
+ (unsigned long long)stringEncodingForData:(id)arg0 encodingOptions:(id)arg1 convertedString:(id *)arg2 usedLossyConversion:(BOOL *)arg3;
+ (id)stringWithBytes:(const void *)arg0 length:(unsigned long long)arg1 encoding:(unsigned long long)arg2;
+ (id)stringWithCString:(const char *)arg0;
+ (id)stringWithCString:(const char *)arg0 length:(unsigned long long)arg1;
+ (id)stringWithContentsOfFile:(id)arg0;
+ (id)stringWithContentsOfURL:(id)arg0;
+ (id)stringWithContentsOfURL:(id)arg0 encoding:(unsigned long long)arg1 error:(id *)arg2;
+ (id)stringWithContentsOfURL:(id)arg0 usedEncoding:(unsigned long long *)arg1 error:(id *)arg2;
+ (id)stringWithFormat:(id)arg0 locale:(id)arg1;
+ (id)stringWithValidatedFormat:(id)arg0 validFormatSpecifiers:(id)arg1 error:(id *)arg2;
+ (id)writableTypeIdentifiersForItemProvider;

- (id)copyWithZone:(struct _NSZone *)arg0;
- (id)description;
- (unsigned long long)hash;
- (id)init;
- (BOOL)isEqual:(id)arg0;
- (id)mutableCopyWithZone:(struct _NSZone *)arg0;
- (const char *)UTF8String;
- (id)initWithUTF8String:(const char *)arg0;
- (const char *)_fastCStringContents:(BOOL)arg0;
- (double)doubleValue;
- (float)floatValue;
- (BOOL)getBytes:(void *)arg0 maxLength:(unsigned long long)arg1 usedLength:(unsigned long long *)arg2 encoding:(unsigned long long)arg3 options:(unsigned long long)arg4 range:(_NSRange)arg5 remainingRange:(struct _NSRange { unsigned long long x0; unsigned long long x1; } *)arg6;
- (id)initWithFormat:(id)arg0 arguments:(char *)arg1;
- (int)intValue;
- (BOOL)isNSString__;
- (unsigned long long)length;
- (unsigned long long)lengthOfBytesUsingEncoding:(unsigned long long)arg0;
- (long long)longLongValue;
- (const char *)cString;
- (unsigned long long)fastestEncoding;
- (id)initWithString:(id)arg0;
- (BOOL)_getCString:(char *)arg0 maxLength:(unsigned long long)arg1 encoding:(unsigned int)arg2;
- (unsigned long long)_cfTypeID;
- (id)_copyFormatStringWithConfiguration:(id)arg0;
- (id)_createSubstringWithRange:(_NSRange)arg0;
- (BOOL)_encodingCantBeStoredInEightBitCFString;
- (const unsigned short *)_fastCharacterContents;
- (unsigned int)_fastestEncodingInCFStringEncoding;
- (BOOL)_isCString;
- (id)_newSubstringWithRange:(_NSRange)arg0 zone:(struct _NSZone *)arg1;
- (unsigned int)_pathResolveFlags;
- (unsigned int)_queryResolveFlags;
- (unsigned int)_smallestEncodingInCFStringEncoding;
- (id)_stringRepresentation;
- (id)_urlStringByInsertingPathResolveFlags:(unsigned int)arg0;
- (id)_urlStringByInsertingQueryResolveFlags:(unsigned int)arg0;
- (id)_urlStringByRemovingResolveFlags;
- (BOOL)boolValue;
- (unsigned long long)cStringLength;
- (const char *)cStringUsingEncoding:(unsigned long long)arg0;
- (unsigned short)characterAtIndex:(unsigned long long)arg0;
- (Class)classForCoder;
- (long long)compare:(id)arg0;
- (long long)compare:(id)arg0 options:(unsigned long long)arg1 range:(_NSRange)arg2 locale:(id)arg3;
- (id)dataUsingEncoding:(unsigned long long)arg0 allowLossyConversion:(BOOL)arg1;
- (void)encodeWithCoder:(id)arg0;
- (const char *)fileSystemRepresentation;
- (id)formatConfiguration;
- (BOOL)getCString:(char *)arg0 maxLength:(unsigned long long)arg1 encoding:(unsigned long long)arg2;
- (void)getCharacters:(unsigned short *)arg0 range:(_NSRange)arg1;
- (BOOL)getFileSystemRepresentation:(char *)arg0 maxLength:(unsigned long long)arg1;
- (void)getLineStart:(unsigned long long *)arg0 end:(unsigned long long *)arg1 contentsEnd:(unsigned long long *)arg2 forRange:(_NSRange)arg3;
- (void)getParagraphStart:(unsigned long long *)arg0 end:(unsigned long long *)arg1 contentsEnd:(unsigned long long *)arg2 forRange:(_NSRange)arg3;
- (BOOL)hasPrefix:(id)arg0;
- (BOOL)hasSuffix:(id)arg0;
- (id)initWithCoder:(id)arg0;
- (id)initWithContentsOfFile:(id)arg0;
- (id)initWithContentsOfURL:(id)arg0;
- (long long)integerValue;
- (BOOL)isEqualToString:(id)arg0;
- (id)lowercaseStringWithLocale:(id)arg0;
- (_NSRange)rangeOfCharacterFromSet:(id)arg0 options:(unsigned long long)arg1 range:(_NSRange)arg2;
- (unsigned long long)smallestEncoding;
- (id)substringFromIndex:(unsigned long long)arg0;
- (id)substringWithRange:(_NSRange)arg0;
- (id)uppercaseStringWithLocale:(id)arg0;
- (BOOL)containsString:(id)arg0;
- (id)initWithFormat:(id)arg0;
- (id)stringByAppendingPathComponent:(id)arg0;
- (id)lowercaseString;
- (id)stringByAppendingPathExtension:(id)arg0;
- (id)capitalizedString;
- (long long)caseInsensitiveCompare:(id)arg0;
- (long long)compare:(id)arg0 options:(unsigned long long)arg1;
- (id)componentsSeparatedByString:(id)arg0;
- (id)dataUsingEncoding:(unsigned long long)arg0;
- (id)initWithBytesNoCopy:(void *)arg0 length:(unsigned long long)arg1 encoding:(unsigned long long)arg2 freeWhenDone:(BOOL)arg3;
- (id)initWithCString:(const char *)arg0 encoding:(unsigned long long)arg1;
- (id)initWithCString:(const char *)arg0 length:(unsigned long long)arg1;
- (id)initWithCharacters:(const unsigned short *)arg0 length:(unsigned long long)arg1;
- (id)initWithData:(id)arg0 encoding:(unsigned long long)arg1;
- (id)lastPathComponent;
- (long long)localizedStandardCompare:(id)arg0;
- (id)pathComponents;
- (id)pathExtension;
- (id)propertyList;
- (_NSRange)rangeOfCharacterFromSet:(id)arg0;
- (_NSRange)rangeOfCharacterFromSet:(id)arg0 options:(unsigned long long)arg1;
- (_NSRange)rangeOfString:(id)arg0;
- (_NSRange)rangeOfString:(id)arg0 options:(unsigned long long)arg1;
- (_NSRange)rangeOfString:(id)arg0 options:(unsigned long long)arg1 range:(_NSRange)arg2;
- (id)stringByAppendingFormat:(id)arg0;
- (id)stringByAppendingString:(id)arg0;
- (id)stringByApplyingTransform:(id)arg0 reverse:(BOOL)arg1;
- (id)stringByDeletingLastPathComponent;
- (id)stringByDeletingPathExtension;
- (id)stringByExpandingTildeInPath;
- (id)stringByReplacingCharactersInRange:(_NSRange)arg0 withString:(id)arg1;
- (id)stringByReplacingOccurrencesOfString:(id)arg0 withString:(id)arg1;
- (id)substringToIndex:(unsigned long long)arg0;
- (id)stringByPaddingToLength:(unsigned long long)arg0 withString:(id)arg1 startingAtIndex:(unsigned long long)arg2;
- (id)stringByStandardizingPath;
- (id)uppercaseString;
- (id)componentsSeparatedByCharactersInSet:(id)arg0;
- (void)enumerateSubstringsInRange:(_NSRange)arg0 options:(unsigned long long)arg1 usingBlock:(id /* block */)arg2;
- (void)getCharacters:(unsigned short *)arg0;
- (id)initWithContentsOfFile:(id)arg0 encoding:(unsigned long long)arg1 error:(id *)arg2;
- (_NSRange)rangeOfComposedCharacterSequenceAtIndex:(unsigned long long)arg0;
- (id)stringByReplacingOccurrencesOfString:(id)arg0 withString:(id)arg1 options:(unsigned long long)arg2 range:(_NSRange)arg3;
- (id)stringByTrimmingCharactersInSet:(id)arg0;
- (BOOL)writeToFile:(id)arg0 atomically:(BOOL)arg1;
- (id)_initWithFormat:(id)arg0 locale:(id)arg1 options:(id)arg2;
- (id)_web_parseAsKeyValuePair_nowarn;
- (id)commonPrefixWithString:(id)arg0 options:(unsigned long long)arg1;
- (_NSRange)localizedStandardRangeOfString:(id)arg0;
- (BOOL)matchesPattern:(id)arg0 caseInsensitive:(BOOL)arg1;
- (id)__baseAttributedString;
- (id)__escapeString5991;
- (BOOL)__oldnf_containsChar:(BOOL)arg0;
- (void)__oldnf_copyToUnicharBuffer:(unsigned short * *)arg0 saveLength:(long long *)arg1;
- (BOOL)__swiftFillFileSystemRepresentationWithPointer:(char *)arg0 maxLength:(long long)arg1;
- (_NSRange)significantText;
- (id)stringByResolvingSymlinksInPath;
- (id)_initWithDataOfUnknownEncoding:(id)arg0;
- (id)_web_stringByTrimmingWhitespace;
- (BOOL)isLike:(id)arg0;
- (BOOL)matchesPattern:(id)arg0;
- (id)__oldnf_componentsSeparatedBySet:(id)arg0;
- (BOOL)__oldnf_containsCharFromSet:(id)arg0;
- (BOOL)__oldnf_containsString:(id)arg0;
- (id)__oldnf_stringWithSeparator:(unsigned short)arg0 atFrequency:(long long)arg1;
- (id)stringByRemovingPercentEncoding;
- (BOOL)_allowsDirectEncoding;
- (id)_componentsSeparatedByCharactersInSet:(struct __CFCharacterSet *)arg0;
- (void)_flushRegularExpressionCaches;
- (void)_getBlockStart:(unsigned long long *)arg0 end:(unsigned long long *)arg1 contentsEnd:(unsigned long long *)arg2 forRange:(_NSRange)arg3 stopAtLineSeparators:(BOOL)arg4;
- (id)_getBracketedStringFromBuffer:(struct _NSStringBuffer { unsigned long long x0; unsigned long long x1; id x2; unsigned long long x3; unsigned long long x4; unsigned short[32] x5; unsigned short x6; unsigned short x7; } *)arg0 string:(id)arg1;
- (BOOL)_getBytesAsData:(id *)arg0 maxLength:(unsigned long long)arg1 usedLength:(unsigned long long *)arg2 encoding:(unsigned long long)arg3 options:(unsigned long long)arg4 range:(_NSRange)arg5 remainingRange:(struct _NSRange { unsigned long long x0; unsigned long long x1; } *)arg6;
- (id)_getCharactersAsStringInRange:(_NSRange)arg0;
- (id)_initWithBytesOfUnknownEncoding:(char *)arg0 length:(unsigned long long)arg1 copy:(BOOL)arg2 usedEncoding:(unsigned long long *)arg3;
- (id)_initWithFormat:(id)arg0 locale:(id)arg1 options:(id)arg2 arguments:(char *)arg3;
- (id)_initWithFormat:(id)arg0 options:(id)arg1;
- (id)_initWithFormat:(id)arg0 options:(id)arg1 arguments:(char *)arg2;
- (id)_initWithValidatedFormat:(id)arg0 validFormatSpecifiers:(id)arg1 locale:(id)arg2 options:(id)arg3 error:(id *)arg4;
- (id)_initWithValidatedFormat:(id)arg0 validFormatSpecifiers:(id)arg1 locale:(id)arg2 options:(id)arg3 error:(id *)arg4 arguments:(char *)arg5;
- (id)_initWithValidatedFormat:(id)arg0 validFormatSpecifiers:(id)arg1 options:(id)arg2 error:(id *)arg3;
- (id)_initWithValidatedFormat:(id)arg0 validFormatSpecifiers:(id)arg1 options:(id)arg2 error:(id *)arg3 arguments:(char *)arg4;
- (BOOL)_matchesCharacter:(unsigned short)arg0;
- (_NSRange)_rangeOfCharacterFromSet:(struct __CFCharacterSet *)arg0 options:(unsigned long long)arg1 range:(_NSRange)arg2;
- (_NSRange)_rangeOfRegularExpressionPattern:(id)arg0 options:(unsigned long long)arg1 range:(_NSRange)arg2 locale:(id)arg3;
- (int)_scriptingAlternativeValueRankWithDescriptor:(id)arg0;
- (id)_scriptingTextDescriptor;
- (id)_stringByAddingPercentEncodingWithAllowedCharacters:(struct __CFCharacterSet *)arg0;
- (id)_stringByReplacingOccurrencesOfRegularExpressionPattern:(id)arg0 withTemplate:(id)arg1 options:(unsigned long long)arg2 range:(_NSRange)arg3;
- (id)_stringByResolvingSymlinksInPathUsingCache:(BOOL)arg0;
- (id)_stringByStandardizingPathUsingCache:(BOOL)arg0;
- (id)_stringByTrimmingCharactersInSet:(struct __CFCharacterSet *)arg0;
- (id)_web_HTTPStyleLanguageCode;
- (id)_web_HTTPStyleLanguageCodeWithoutRegion;
- (id)_web_URLFragment;
- (id)_web_characterSetFromContentTypeHeader_nowarn;
- (long long)_web_countOfString:(id)arg0;
- (id)_web_domainFromHost;
- (BOOL)_web_domainMatches:(id)arg0;
- (unsigned int)_web_extractFourCharCode;
- (id)_web_fileNameFromContentDispositionHeader_nowarn;
- (id)_web_filenameByFixingIllegalCharacters;
- (id)_web_fixedCarbonPOSIXPath;
- (BOOL)_web_hasCaseInsensitivePrefix:(id)arg0;
- (BOOL)_web_hasCountryCodeTLD;
- (BOOL)_web_isCaseInsensitiveEqualToString:(id)arg0;
- (BOOL)_web_isFileURL;
- (BOOL)_web_isJavaScriptURL;
- (BOOL)_web_looksLikeAbsoluteURL;
- (BOOL)_web_looksLikeIPAddress;
- (id)_web_mimeTypeFromContentTypeHeader_nowarn;
- (id)_web_parseAsKeyValuePairHandleQuotes_nowarn:(BOOL)arg0;
- (_NSRange)_web_rangeOfURLHost;
- (_NSRange)_web_rangeOfURLResourceSpecifier_nowarn;
- (_NSRange)_web_rangeOfURLScheme_nowarn;
- (_NSRange)_web_rangeOfURLUserPasswordHostPort;
- (id)_web_splitAtNonDateCommas_nowarn;
- (id)_web_stringByCollapsingNonPrintingCharacters;
- (id)_web_stringByExpandingTildeInPath;
- (id)_web_stringByReplacingValidPercentEscapes_nowarn;
- (id)_widthVariants;
- (BOOL)canBeConvertedToEncoding:(unsigned long long)arg0;
- (id)capitalizedStringWithLocale:(id)arg0;
- (long long)compare:(id)arg0 options:(unsigned long long)arg1 range:(_NSRange)arg2;
- (unsigned long long)completePathIntoString:(id *)arg0 caseSensitive:(BOOL)arg1 matchesIntoArray:(id *)arg2 filterTypes:(id)arg3;
- (struct { int x0 : 8; int x1 : 4; int x2 : 1; int x3 : 1; int x4 : 18; unsigned short[8] x5; })decimalValue;
- (id)decomposedStringWithCanonicalMapping;
- (id)decomposedStringWithCompatibilityMapping;
- (id)displayableString;
- (void)enumerateLinesUsingBlock:(id /* block */)arg0;
- (void)enumerateLinguisticTagsInRange:(_NSRange)arg0 scheme:(id)arg1 options:(unsigned long long)arg2 orthography:(id)arg3 usingBlock:(id /* block */)arg4;
- (BOOL)getBytes:(char *)arg0 maxLength:(unsigned long long)arg1 filledLength:(unsigned long long *)arg2 encoding:(unsigned long long)arg3 allowLossyConversion:(BOOL)arg4 range:(_NSRange)arg5 remainingRange:(struct _NSRange { unsigned long long x0; unsigned long long x1; } *)arg6;
- (void)getCString:(char *)arg0;
- (void)getCString:(char *)arg0 maxLength:(unsigned long long)arg1;
- (void)getCString:(char *)arg0 maxLength:(unsigned long long)arg1 range:(_NSRange)arg2 remainingRange:(struct _NSRange { unsigned long long x0; unsigned long long x1; } *)arg3;
- (BOOL)getExternalRepresentation:(id *)arg0 extendedAttributes:(id *)arg1 forWritingToURLOrPath:(id)arg2 usingEncoding:(unsigned long long)arg3 error:(id *)arg4;
- (id)initWithBytesNoCopy:(void *)arg0 length:(unsigned long long)arg1 encoding:(unsigned long long)arg2 deallocator:(id /* block */)arg3;
- (id)initWithCString:(const char *)arg0;
- (id)initWithCStringNoCopy:(char *)arg0 length:(unsigned long long)arg1 freeWhenDone:(BOOL)arg2;
- (id)initWithCharactersNoCopy:(unsigned short *)arg0 length:(unsigned long long)arg1 deallocator:(id /* block */)arg2;
- (id)initWithCharactersNoCopy:(unsigned short *)arg0 length:(unsigned long long)arg1 freeWhenDone:(BOOL)arg2;
- (id)initWithContentsOfFile:(id)arg0 usedEncoding:(unsigned long long *)arg1 error:(id *)arg2;
- (id)initWithContentsOfURL:(id)arg0 encoding:(unsigned long long)arg1 error:(id *)arg2;
- (id)initWithContentsOfURL:(id)arg0 usedEncoding:(unsigned long long *)arg1 error:(id *)arg2;
- (id)initWithData:(id)arg0 usedEncoding:(unsigned long long *)arg1;
- (id)initWithFormat:(id)arg0 locale:(id)arg1;
- (id)initWithFormat:(id)arg0 locale:(id)arg1 arguments:(char *)arg2;
- (id)initWithValidatedFormat:(id)arg0 validFormatSpecifiers:(id)arg1 arguments:(char *)arg2 error:(id *)arg3;
- (id)initWithValidatedFormat:(id)arg0 validFormatSpecifiers:(id)arg1 error:(id *)arg2;
- (id)initWithValidatedFormat:(id)arg0 validFormatSpecifiers:(id)arg1 locale:(id)arg2 arguments:(char *)arg3 error:(id *)arg4;
- (id)initWithValidatedFormat:(id)arg0 validFormatSpecifiers:(id)arg1 locale:(id)arg2 error:(id *)arg3;
- (BOOL)isAbsolutePath;
- (BOOL)isCaseInsensitiveLike:(id)arg0;
- (_NSRange)lineRangeForRange:(_NSRange)arg0;
- (id)linguisticTagsInRange:(_NSRange)arg0 scheme:(id)arg1 options:(unsigned long long)arg2 orthography:(id)arg3 tokenRanges:(id *)arg4;
- (id)loadDataWithTypeIdentifier:(id)arg0 forItemProviderCompletionHandler:(id /* block */)arg1;
- (id)localizedCapitalizedString;
- (long long)localizedCaseInsensitiveCompare:(id)arg0;
- (BOOL)localizedCaseInsensitiveContainsString:(id)arg0;
- (long long)localizedCompare:(id)arg0;
- (BOOL)localizedHasPrefix:(id)arg0;
- (BOOL)localizedHasSuffix:(id)arg0;
- (id)localizedLowercaseString;
- (BOOL)localizedStandardContainsString:(id)arg0;
- (id)localizedUppercaseString;
- (const char *)lossyCString;
- (unsigned long long)maximumLengthOfBytesUsingEncoding:(unsigned long long)arg0;
- (_NSRange)paragraphRangeForRange:(_NSRange)arg0;
- (id)precomposedStringWithCanonicalMapping;
- (id)precomposedStringWithCompatibilityMapping;
- (id)propertyListFromStringsFileFormat;
- (id)quotedStringRepresentation;
- (_NSRange)rangeOfComposedCharacterSequencesForRange:(_NSRange)arg0;
- (_NSRange)rangeOfString:(id)arg0 options:(unsigned long long)arg1 range:(_NSRange)arg2 locale:(id)arg3;
- (id)replacementObjectForPortCoder:(id)arg0;
- (BOOL)scriptingBeginsWith:(id)arg0;
- (BOOL)scriptingContains:(id)arg0;
- (BOOL)scriptingEndsWith:(id)arg0;
- (BOOL)scriptingIsEqualTo:(id)arg0;
- (BOOL)scriptingIsGreaterThan:(id)arg0;
- (BOOL)scriptingIsGreaterThanOrEqualTo:(id)arg0;
- (BOOL)scriptingIsLessThan:(id)arg0;
- (BOOL)scriptingIsLessThanOrEqualTo:(id)arg0;
- (id)standardizedURLPath;
- (id)stringByAbbreviatingWithTildeInPath;
- (id)stringByAddingPercentEncodingWithAllowedCharacters:(id)arg0;
- (id)stringByAddingPercentEscapes;
- (id)stringByAddingPercentEscapesUsingEncoding:(unsigned long long)arg0;
- (id)stringByConvertingPathToURL;
- (id)stringByConvertingURLToPath;
- (id)stringByFoldingWithOptions:(unsigned long long)arg0 locale:(id)arg1;
- (id)stringByRemovingPercentEscapes;
- (id)stringByReplacingPercentEscapesUsingEncoding:(unsigned long long)arg0;
- (id)stringMarkingUpcaseTransitionsWithDelimiter2:(id)arg0;
- (id)stringsByAppendingPaths:(id)arg0;
- (id)variantFittingPresentationWidth:(long long)arg0;
- (id)writableTypeIdentifiersForItemProvider;
- (BOOL)writeToFile:(id)arg0 atomically:(BOOL)arg1 encoding:(unsigned long long)arg2 error:(id *)arg3;
- (BOOL)writeToURL:(id)arg0 atomically:(BOOL)arg1;
- (BOOL)writeToURL:(id)arg0 atomically:(BOOL)arg1 encoding:(unsigned long long)arg2 error:(id *)arg3;

@end
```

</details>

## License

MachOObjCSection is released under the MIT License. See [LICENSE](./LICENSE)
