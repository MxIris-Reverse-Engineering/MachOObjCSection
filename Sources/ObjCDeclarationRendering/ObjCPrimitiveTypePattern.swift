import Foundation

/// The C primitive types a renderer can substitute for something else.
///
/// This mirrors the pattern set of swift-semantic-string's
/// `Transformer.CType`, but is declared locally on purpose: rendering only
/// needs to *look up* a replacement string, not to know how that string was
/// produced. Keeping the enum here means library users get C-type substitution
/// without depending on the template engine; callers that do drive rendering
/// from a `Transformer.CType` convert at the call site.
public enum ObjCPrimitiveTypePattern: String, CaseIterable, Codable, Sendable, Hashable {
    case char
    case uchar
    case short
    case ushort
    case int
    case uint
    case long
    case ulong
    case longLong
    case ulongLong
    case float
    case double
    case longDouble

    /// The type as it is spelled in Objective-C source.
    public var displayName: String {
        switch self {
        case .char: "char"
        case .uchar: "unsigned char"
        case .short: "short"
        case .ushort: "unsigned short"
        case .int: "int"
        case .uint: "unsigned int"
        case .long: "long"
        case .ulong: "unsigned long"
        case .longLong: "long long"
        case .ulongLong: "unsigned long long"
        case .float: "float"
        case .double: "double"
        case .longDouble: "long double"
        }
    }
}
