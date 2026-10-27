import Foundation
public import OutputTransformer
public import Semantic

// MARK: - C Type Transformer Module

extension Transformer {
    /// Replaces C primitive types with custom types.
    ///
    /// Example:
    /// ```swift
    /// var module = Transformer.CType()
    /// module.isEnabled = true
    /// module.replacements[.double] = "CGFloat"
    /// module.replacements[.longLong] = "NSInteger"
    /// ```
    public struct CType: Module {
        public typealias Parameter = Pattern
        public typealias Input = SemanticString
        public typealias Output = SemanticString

        public static let displayName = "C Type Replacement"

        public var isEnabled: Bool

        public var replacements: [Pattern: String]

        public init(isEnabled: Bool = false, replacements: [Pattern: String] = [:]) {
            self.isEnabled = isEnabled
            self.replacements = replacements
        }

        // Missing-key-tolerant decoding (compatible with the previous
        // MetaCodable `@Default(ifMissing:)` persistence).
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
            self.replacements = try container.decodeIfPresent([Pattern: String].self, forKey: .replacements) ?? [:]
        }

        /// A replacement stands in for a whole type: the type keywords in a
        /// row, apart only by whitespace, are looked up together, and a type
        /// with no replacement is left as it is. Matching a pattern wherever
        /// its keywords appeared turned `unsigned long` into `unsigned` plus a
        /// replacement for `long`, and a match starting at a space swallowed
        /// it: `const double` became `constCGFloat`.
        public func transform(_ input: SemanticString) -> SemanticString {
            let replacementsByKeywords = Dictionary(
                replacements
                    .filter { !$0.value.isEmpty }
                    .map { ($0.key.keywords, $0.value) },
                uniquingKeysWith: { first, _ in first }
            )
            guard !replacementsByKeywords.isEmpty else { return input }

            let components = input.components
            var result: [AtomicComponent] = []
            var index = 0

            while index < components.count {
                guard let typeSpelling = Self.typeSpelling(in: components, startingAt: index) else {
                    result.append(components[index])
                    index += 1
                    continue
                }
                if let replacement = replacementsByKeywords[typeSpelling.keywords] {
                    result.append(AtomicComponent(string: replacement, type: .type(.other, .name)))
                } else {
                    result.append(contentsOf: components[index ..< typeSpelling.endIndex])
                }
                index = typeSpelling.endIndex
            }

            return SemanticString(components: result)
        }

        /// Every keyword a C primitive type is spelled with.
        private static let typeKeywords = Set(Pattern.allCases.flatMap(\.keywords))

        private static func isTypeKeyword(_ component: AtomicComponent) -> Bool {
            component.type == .keyword && typeKeywords.contains(component.string)
        }

        private static func isWhitespace(_ component: AtomicComponent) -> Bool {
            component.type == .standard && component.string.allSatisfy(\.isWhitespace)
        }

        /// The keywords of the type spelled from `startIndex` on, and the index
        /// just past the last of them — whitespace after it is not part of the
        /// type. `nil` when no type keyword starts there.
        private static func typeSpelling(
            in components: [AtomicComponent],
            startingAt startIndex: Int
        ) -> (keywords: [String], endIndex: Int)? {
            guard isTypeKeyword(components[startIndex]) else { return nil }

            var keywords = [components[startIndex].string]
            var endIndex = startIndex + 1
            var candidateIndex = endIndex
            while candidateIndex < components.count {
                let component = components[candidateIndex]
                if isWhitespace(component) {
                    candidateIndex += 1
                } else if isTypeKeyword(component) {
                    keywords.append(component.string)
                    candidateIndex += 1
                    endIndex = candidateIndex
                } else {
                    break
                }
            }
            return (keywords, endIndex)
        }
    }
}

// MARK: - Pattern

extension Transformer.CType {
    /// C primitive type patterns.
    public enum Pattern: String, CaseIterable, Codable, Sendable, Hashable {
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

        var keywords: [String] {
            switch self {
            case .char: ["char"]
            case .uchar: ["unsigned", "char"]
            case .short: ["short"]
            case .ushort: ["unsigned", "short"]
            case .int: ["int"]
            case .uint: ["unsigned", "int"]
            case .long: ["long"]
            case .ulong: ["unsigned", "long"]
            case .longLong: ["long", "long"]
            case .ulongLong: ["unsigned", "long", "long"]
            case .float: ["float"]
            case .double: ["double"]
            case .longDouble: ["long", "double"]
            }
        }
    }
}

// MARK: - Presets

extension Transformer.CType {
    public enum Presets {
        public static let stdint: [Pattern: String] = [
            .uchar: "uint8_t",
            .ushort: "uint16_t",
            .uint: "uint32_t",
            .ulong: "uint64_t",
            .ulongLong: "uint64_t",

            .char: "int8_t",
            .short: "int16_t",
            .int: "int32_t",
            .long: "int64_t",
            .longLong: "int64_t",
        ]

        public static let foundation: [Pattern: String] = [
            .double: "CGFloat",
            .long: "NSInteger",
            .ulong: "NSUInteger",
            .longLong: "NSInteger",
            .ulongLong: "NSUInteger",
        ]

        public static let mixed: [Pattern: String] = [
            .uchar: "uint8_t",
            .ushort: "uint16_t",
            .uint: "uint32_t",
            .char: "int8_t",
            .short: "int16_t",
            .int: "int32_t",
            .long: "NSInteger",
            .ulong: "NSUInteger",
            .longLong: "NSInteger",
            .ulongLong: "NSUInteger",
            .double: "CGFloat",
        ]
    }
}
