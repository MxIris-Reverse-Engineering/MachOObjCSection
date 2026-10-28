import Testing
import Foundation
import MachOKit
import MachOObjCSection
import ObjCDump

/// Whether `name` is shaped like a selector: ASCII identifier characters and
/// colons, plus the dot of the `.cxx_construct` and `.cxx_destruct` methods
/// the compiler emits.
private func isSelectorShaped(_ name: String) -> Bool {
    !name.isEmpty && name.allSatisfy { character in
        character.isASCII && (character.isLetter || character.isNumber || "_:.".contains(character))
    }
}

/// The method names of the relative method lists a dyld shared cache builder
/// writes, each an offset straight to the selector string rather than to a
/// selector reference.
///
/// What that offset is measured from changed with macOS 12. objc4-818 (macOS
/// 11) reads it, like every other relative offset, from the name field itself;
/// objc4-838 (macOS 12) on reads it from the selector the cache picked as the
/// base, which `objc_opt_t` v16 and the `objc_opts` header after it record. A
/// macOS 11 cache, `objc_opt_t` v15, records no base, and the reader measured
/// every name from the cache start instead: each one came out as whatever bytes
/// that landed on.
///
/// One cache per layout: `objc_opt_t` v15, `objc_opt_t` v16 and the `objc_opts`
/// header. Only the archive volume carries them.
@Suite("Method names of relative method lists in a dyld shared cache")
struct DyldCacheRelativeMethodNameTests {
    static let appKitImages: [ArchivedCacheImage] = [
        .init(version: "11.0.1", imageName: "AppKit"),
        .init(version: "12.0.1", imageName: "AppKit"),
        .init(version: "13.0", imageName: "AppKit"),
    ]

    static var presentAppKitImages: [ArchivedCacheImage] {
        appKitImages.filter { ArchivedMacOSCache.isPresent(version: $0.version) }
    }

    @Test(
        "NSView declares -initWithFrame: with its type encoding",
        .enabled(if: !presentAppKitImages.isEmpty),
        arguments: presentAppKitImages
    )
    func viewDeclaresInitWithFrame(_ archivedImage: ArchivedCacheImage) throws {
        let appKit = try ArchivedMacOSCache.image(named: archivedImage.imageName, version: archivedImage.version)
        let viewClass = try #require(
            appKit.objc.classes64?.first { $0.classROData(in: appKit)?.name(in: appKit) == "NSView" },
            "no NSView in \(archivedImage.testDescription)"
        )
        let viewInfo = try #require(viewClass.info(in: appKit))

        let initializer = viewInfo.methods.first { $0.name == "initWithFrame:" }
        #expect(initializer?.typeEncoding == "@48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16")
    }

    @Test(
        "Every class and category method is named by a selector",
        .enabled(if: !presentAppKitImages.isEmpty),
        arguments: presentAppKitImages
    )
    func everyMethodIsNamedBySelector(_ archivedImage: ArchivedCacheImage) throws {
        let appKit = try ArchivedMacOSCache.image(named: archivedImage.imageName, version: archivedImage.version)
        let classes = appKit.objc.classes64 ?? []

        // The premise: the classes keep their methods in the lists the cache
        // builder writes, whose names point at selectors directly.
        let directSelectorListCount = classes
            .compactMap { $0.classROData(in: appKit)?.methodList(in: appKit) }
            .filter { $0.listKind == .relativeDirectSelectors }
            .count
        try #require(directSelectorListCount > 0, "no method list names selectors directly in \(archivedImage.testDescription)")

        let classMethods = classes
            .compactMap { $0.info(in: appKit) }
            .flatMap { classInfo in
                (classInfo.methods + classInfo.classMethods).map { (owner: classInfo.name, method: $0) }
            }
        let categoryMethods = ((appKit.objc.categories64 ?? []) + (appKit.objc.categories2_64 ?? []))
            .compactMap { $0.info(in: appKit) }
            .flatMap { categoryInfo in
                (categoryInfo.methods + categoryInfo.classMethods).map {
                    (owner: "\(categoryInfo.className) (\(categoryInfo.name))", method: $0)
                }
            }
        let ownedMethods = classMethods + categoryMethods
        try #require(!ownedMethods.isEmpty, "no class or category method in \(archivedImage.testDescription)")

        let misnamedMethods = ownedMethods.filter { !isSelectorShaped($0.method.name) }
        #expect(
            misnamedMethods.isEmpty,
            """
            \(misnamedMethods.count) of \(ownedMethods.count) methods are not named by a selector, the first of them:
            \(misnamedMethods.prefix(10).map { "\($0.owner): \($0.method.name.debugDescription) \($0.method.typeEncoding)" }.joined(separator: "\n"))
            """
        )
    }
}
