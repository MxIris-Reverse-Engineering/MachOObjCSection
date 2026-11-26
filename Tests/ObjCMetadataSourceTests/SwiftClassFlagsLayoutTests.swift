import Testing
import Foundation
import MachOKit
import MachOObjCSection

/// `swiftClassFlags` is the field `objc_class` adds after the five pointers of
/// `class_t` when the class is a Swift class.
///
/// Upstream p-x9/MachOObjCSection took it out of `ObjCClass64.Layout` and
/// `ObjCClass32.Layout` in `fa97301` (0.9.0), so that reading the layout of an
/// Objective-C class stops at the end of `class_t`, and reads it through
/// `swiftClassFlags(in:)` instead. The fork keeps the field, because
/// MachOSwiftSection compares `layout.swiftClassFlags`, and answers
/// `swiftClassFlags(in:)` from it. A later upstream merge that drops the field
/// again stops this file from compiling.
@Suite("Swift class flags stay in the class layout")
struct SwiftClassFlagsLayoutTests {
    @Test("The field follows the five pointers of class_t")
    func fieldFollowsClassLayout() {
        #expect(MemoryLayout<ObjCClass64.Layout>.offset(of: \.swiftClassFlags) == 5 * 8)
        #expect(MemoryLayout<ObjCClass32.Layout>.offset(of: \.swiftClassFlags) == 5 * 4)
    }

    /// The bytes right after `class_t` are what upstream's `swiftClassFlags(in:)`
    /// reads; the fork answers from the field instead, and the two must agree.
    @Test("swiftClassFlags(in:) answers a Swift class's flags and nil for any other class")
    func flagsQueryAnswersFromLayout() throws {
        let image = try #require(MachOImage(name: "Foundation"), "Foundation is not loaded in the test process")
        let classes = try #require(image.objc.classes64, "Foundation has no class list")
        let swiftClass = try #require(classes.first { $0.isSwift }, "Foundation defines no Swift class")
        let objectiveCClass = try #require(classes.first { !$0.isSwift }, "Foundation defines no Objective-C class")

        let flagsAfterClassLayout = image.ptr
            .advanced(by: swiftClass.offset + 5 * MemoryLayout<UInt64>.size)
            .load(as: UInt32.self)
        #expect(swiftClass.swiftClassFlags(in: image) == flagsAfterClassLayout)
        #expect(objectiveCClass.swiftClassFlags(in: image) == nil)
    }
}
