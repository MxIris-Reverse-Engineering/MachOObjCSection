import Foundation

extension Optional where Wrapped: RangeReplaceableCollection {
    /// The wrapped collection, or an empty one when `nil`.
    ///
    /// Lets the indexer concatenate the optional section arrays
    /// (`classes64`, `classes32`, `nonLazyClasses64`, …) without unwrapping
    /// each one. Reimplemented locally rather than pulled from
    /// SwiftStdlibToolbox, which is Apple-platform only.
    var orEmpty: Wrapped {
        self ?? Wrapped()
    }
}
