import Testing
import Foundation
import MachO
import MachOKit

/// Two images, compiled once per process, whose classes and ivars cover each
/// way a linker symbol publishes them or leaves them unpublished: one written
/// in Swift, one in Objective-C. Neither is built for library evolution or
/// with testability, so what is `internal` stays out of the export trie.
enum ExportedDeclarationsFixture {
    /// Swift publishes a class object under `$s…CN`, and under an
    /// `_OBJC_CLASS_$_` alias only when the class has an Objective-C ancestor;
    /// an ivar's offset variable is the field offset `$s…Wvd`.
    static let swiftSource = """
    import Foundation

    public final class PublicSwiftRoot {
        public var publicValue: Int = 0
        var internalValue: Int = 0
        public init() {}
    }

    final class InternalSwiftRoot {
        var value: Int = 0
    }

    public class PublicObjCSubclass: NSObject {
        public var publicValue: Int = 0
        var internalValue: Int = 0
    }

    class InternalObjCSubclass: NSObject {
        var value: Int = 0
    }
    """

    /// clang publishes a class object under `_OBJC_CLASS_$_` and an ivar's
    /// offset variable under `_OBJC_IVAR_$_`, hidden for a hidden class and
    /// for a `@private` ivar. The categories stay in `__objc_catlist` only
    /// because the image is linked without category merging.
    static let objectiveCSource = """
    #import <Foundation/Foundation.h>

    __attribute__((visibility("default")))
    @interface ExportedFixtureClass : NSObject {
    @public
        int publicIvar;
    @private
        int privateIvar;
    }
    @end

    @implementation ExportedFixtureClass
    @end

    __attribute__((visibility("hidden")))
    @interface HiddenFixtureClass : NSObject {
    @public
        int publicIvarOfHiddenClass;
    }
    @end

    @implementation HiddenFixtureClass
    @end

    @interface ExportedFixtureClass (FixtureCategory)
    - (void)categoryMethod;
    @end

    @implementation ExportedFixtureClass (FixtureCategory)
    - (void)categoryMethod {}
    @end

    @interface HiddenFixtureClass (FixtureCategory)
    - (void)categoryMethod;
    @end

    @implementation HiddenFixtureClass (FixtureCategory)
    - (void)categoryMethod {}
    @end

    @interface NSObject (ExportedDeclarationsFixture)
    - (void)exportedDeclarationsFixtureMethod;
    @end

    @implementation NSObject (ExportedDeclarationsFixture)
    - (void)exportedDeclarationsFixtureMethod {}
    @end
    """

    /// The Objective-C runtime names of the Swift image's classes.
    enum SwiftClassName {
        static let publicSwiftRoot = "_TtC27ExportedDeclarationsFixture15PublicSwiftRoot"
        static let internalSwiftRoot = "_TtC27ExportedDeclarationsFixture17InternalSwiftRoot"
        static let publicObjCSubclass = "_TtC27ExportedDeclarationsFixture18PublicObjCSubclass"
        static let internalObjCSubclass = "_TtC27ExportedDeclarationsFixture20InternalObjCSubclass"
    }

    /// The Objective-C image's classes and categories.
    enum ObjectiveCName {
        static let exportedClass = "ExportedFixtureClass"
        static let hiddenClass = "HiddenFixtureClass"
        static let categoryOnExportedClass = "ExportedFixtureClass(FixtureCategory)"
        static let categoryOnHiddenClass = "HiddenFixtureClass(FixtureCategory)"
        static let categoryOnAnotherImagesClass = "NSObject(ExportedDeclarationsFixture)"
    }

    struct Libraries {
        let swiftLibraryURL: URL
        let objectiveCLibraryURL: URL
    }

    private static let compilation = Result { () throws -> Libraries in
        let workingDirectory = try SuppliedClassFixture.makeWorkingDirectory(named: "ExportedDeclarationsFixture")
        let swiftSourceURL = workingDirectory.appendingPathComponent("ExportedDeclarationsFixture.swift")
        let objectiveCSourceURL = workingDirectory.appendingPathComponent("ExportedDeclarationsObjCFixture.m")
        let swiftLibraryURL = workingDirectory.appendingPathComponent("libExportedDeclarationsSwiftFixture.dylib")
        let objectiveCLibraryURL = workingDirectory.appendingPathComponent("libExportedDeclarationsObjCFixture.dylib")
        try swiftSource.write(to: swiftSourceURL, atomically: true, encoding: .utf8)
        try objectiveCSource.write(to: objectiveCSourceURL, atomically: true, encoding: .utf8)
        try SuppliedClassFixture.run([
            "swiftc", "-emit-library",
            "-module-name", "ExportedDeclarationsFixture",
            swiftSourceURL.path, "-o", swiftLibraryURL.path,
        ])
        try SuppliedClassFixture.run([
            "clang", "-dynamiclib", "-framework", "Foundation",
            "-Wl,-no_objc_category_merging",
            objectiveCSourceURL.path, "-o", objectiveCLibraryURL.path,
        ])
        return Libraries(swiftLibraryURL: swiftLibraryURL, objectiveCLibraryURL: objectiveCLibraryURL)
    }

    static func libraries() throws -> Libraries {
        try compilation.get()
    }

    static func swiftLibraryFile() throws -> MachOFile {
        try SuppliedClassFixture.loadMachOFile(at: try libraries().swiftLibraryURL)
    }

    static func objectiveCLibraryFile() throws -> MachOFile {
        try SuppliedClassFixture.loadMachOFile(at: try libraries().objectiveCLibraryURL)
    }

    /// Each image is loaded once and stays loaded: an image that registered
    /// Objective-C classes cannot be unloaded, and loading a second copy
    /// would register the same class names twice.
    private static let loadedSwiftLibrary = Result { () throws -> MachOImage in
        try loadImage(at: try libraries().swiftLibraryURL, findingSymbolNamed: "$s27ExportedDeclarationsFixture15PublicSwiftRootCN")
    }

    private static let loadedObjectiveCLibrary = Result { () throws -> MachOImage in
        try loadImage(at: try libraries().objectiveCLibraryURL, findingSymbolNamed: "OBJC_CLASS_$_ExportedFixtureClass")
    }

    static func swiftLibraryImage() throws -> MachOImage {
        try loadedSwiftLibrary.get()
    }

    static func objectiveCLibraryImage() throws -> MachOImage {
        try loadedObjectiveCLibrary.get()
    }

    private static func loadImage(at url: URL, findingSymbolNamed symbolName: String) throws -> MachOImage {
        let handle = try #require(dlopen(url.path, RTLD_NOW), "\(dlerror().map { String(cString: $0) } ?? "dlopen failed")")
        return try SuppliedClassFixture.imageOffset(ofSymbolNamed: symbolName, handle: handle).image
    }
}
