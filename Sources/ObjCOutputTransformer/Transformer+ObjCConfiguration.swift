import Foundation
public import OutputTransformer

// MARK: - ObjC Configuration

extension Transformer {
    /// Configuration for the ObjC-specific transformer modules.
    public struct ObjCConfiguration: Sendable, Equatable, Hashable, Codable {
        public var cType: Transformer.CType
        public var ivarOffset: Transformer.ObjCIvarOffset

        public init(cType: CType = .init(), ivarOffset: ObjCIvarOffset = .init()) {
            self.cType = cType
            self.ivarOffset = ivarOffset
        }

        // Missing-key-tolerant decoding (compatible with the previous
        // MetaCodable `@Default(ifMissing:)` persistence).
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.cType = try container.decodeIfPresent(CType.self, forKey: .cType) ?? .init()
            self.ivarOffset = try container.decodeIfPresent(ObjCIvarOffset.self, forKey: .ivarOffset) ?? .init()
        }

        /// Whether any ObjC module is enabled.
        public var hasEnabledModules: Bool {
            cType.isEnabled || ivarOffset.isEnabled
        }
    }
}
