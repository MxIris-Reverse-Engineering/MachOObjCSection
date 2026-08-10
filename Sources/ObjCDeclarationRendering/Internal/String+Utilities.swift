import Foundation

extension String {
    /// Uppercases only the first character, leaving the rest untouched.
    ///
    /// Used to derive a setter selector from a property name
    /// (`title` → `setTitle:`). `capitalized` is deliberately not used: it
    /// would lowercase the remainder and mangle names like `URLString`.
    ///
    /// Reimplemented locally rather than pulled from FrameworkToolbox, which
    /// is Apple-platform only — MachOObjCSection supports Linux.
    var uppercasedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }

    /// Lowercases only the first character, leaving the rest untouched.
    ///
    /// Used when deriving a parameter name from a selector fragment
    /// (`WithObject` → `withObject`). As with ``uppercasedFirst``, the rest of
    /// the string is preserved so that names like `URL` survive intact.
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
