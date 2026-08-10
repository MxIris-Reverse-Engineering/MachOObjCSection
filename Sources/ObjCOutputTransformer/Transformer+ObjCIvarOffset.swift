import Foundation
public import OutputTransformer

// MARK: - ObjC Ivar Offset Transformer Module

extension Transformer {
    /// Customizes ObjC ivar offset comment format using token templates.
    public struct ObjCIvarOffset: Module {
        public typealias Parameter = Token
        public typealias Output = String

        public static let displayName = "ObjC Ivar Offset Comment"

        public var isEnabled: Bool

        public var template: String

        public var useHexadecimal: Bool

        public init(isEnabled: Bool = false, template: String = Templates.standard, useHexadecimal: Bool = true) {
            self.isEnabled = isEnabled
            self.template = template
            self.useHexadecimal = useHexadecimal
        }

        // Missing-key-tolerant decoding (compatible with the previous
        // MetaCodable `@Default(ifMissing:)` persistence).
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
            self.template = try container.decodeIfPresent(String.self, forKey: .template) ?? Templates.standard
            self.useHexadecimal = try container.decodeIfPresent(Bool.self, forKey: .useHexadecimal) ?? true
        }

        public func transform(_ input: Input) -> String {
            template
                .replacingOccurrences(of: Token.offset.placeholder, with: formatValue(input.offset))
        }

        private func formatValue(_ value: Int) -> String {
            useHexadecimal ? "0x\(String(value, radix: 16, uppercase: true))" : String(value)
        }

        public func contains(_ token: Token) -> Bool {
            template.contains(token.placeholder)
        }
    }
}

// MARK: - Input

extension Transformer.ObjCIvarOffset {
    public struct Input: Sendable {
        public let offset: Int

        public init(offset: Int) {
            self.offset = offset
        }
    }
}

// MARK: - Token

extension Transformer.ObjCIvarOffset {
    public enum Token: String, CaseIterable, Sendable {
        case offset

        public var placeholder: String { "${\(rawValue)}" }

        public var displayName: String {
            switch self {
            case .offset: "Offset"
            }
        }
    }
}

// MARK: - Templates

extension Transformer.ObjCIvarOffset {
    public enum Templates {
        public static let standard = "offset: ${offset}"
        public static let labeled = "ivar offset: ${offset}"
        public static let bare = "${offset}"

        public static let all: [(name: String, template: String)] = [
            ("Standard", standard),
            ("Labeled", labeled),
            ("Bare", bare),
        ]
    }
}
