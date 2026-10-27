import Foundation

/// A second extension of NSString, in a file of its own, compiled apart from
/// the one in `ObjCIndexingTests.swift`: Swift names the category of each
/// after the module. `sameNamedCategoriesAreAllIndexed` relies on it.
extension NSString {
    @objc func objcIndexingSecondFixtureMethod() {}
}
