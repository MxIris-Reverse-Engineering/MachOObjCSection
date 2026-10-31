import MachOKit
import MachOKitExtensions
import ObjCMetadataSource
import Semantic

extension ObjCMetadataSource {
    /// Safely format an IMP address into a resolved virtual address string.
    ///
    /// Returns `nil` when the raw value holds no usable implementation
    /// pointer, meaning the caller should treat it as invalid.
    ///
    /// What counts as "usable" differs between a file on disk and a loaded
    /// image, because the raw `imp` field does not mean the same thing in the
    /// two — see ``ObjCMetadataSource/objcResolvedIMPAddress(forRawValue:)``.
    public func formattedAddress(forRawValue rawValue: UInt64) -> String? {
        guard let resolvedAddress = objcResolvedIMPAddress(forRawValue: rawValue) else {
            return nil
        }
        return "0x\(String(resolvedAddress, radix: 16, uppercase: true))"
    }

    /// The comment for an IMP address: `// IMP: 0x1A2B3C` when the address is
    /// valid, `// IMP: <invalid 0x0>` — the raw value written as an error —
    /// when it is not.
    func impAddressComment(label: String, rawValue: UInt64) -> ObjCComment {
        if let resolved = formattedAddress(forRawValue: rawValue) {
            .impAddress(label: label, address: resolved)
        } else {
            .impAddress(label: label, invalidAddress: "<invalid 0x\(String(UInt(rawValue), radix: 16, uppercase: true))>")
        }
    }

    /// Format an IMP address into a plain string suitable for data models.
    ///
    /// Returns a resolved virtual address when valid, or a raw hex
    /// representation prefixed with `<invalid>` when not.
    public func formattedAddressString(forRawValue rawValue: UInt64) -> String {
        if let resolved = formattedAddress(forRawValue: rawValue) {
            return resolved
        }
        return "<invalid 0x\(String(UInt(rawValue), radix: 16, uppercase: true))>"
    }
}
