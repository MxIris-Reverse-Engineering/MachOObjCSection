import Foundation

/// The ten switches that decide what a rendered Objective-C declaration
/// contains: which members get stripped, and which explanatory comments get
/// added.
///
/// Every switch defaults to `false`, i.e. ``default`` renders the declaration
/// exactly as the metadata describes it — nothing removed, nothing annotated.
public struct ObjCGenerationOptions: Sendable, Equatable, Hashable, Codable {
    /// Drops the `<Protocol, …>` conformance list from the class declaration.
    public var stripProtocolConformance: Bool
    /// Drops methods that merely override a superclass method.
    public var stripOverrides: Bool
    /// Drops ivars synthesized by `@property`.
    public var stripSynthesizedIvars: Bool
    /// Drops getters/setters synthesized by `@property`.
    public var stripSynthesizedMethods: Bool
    /// Drops `.cxx_construct`.
    public var stripCtorMethod: Bool
    /// Drops `.cxx_destruct`.
    public var stripDtorMethod: Bool
    /// Appends `// offset: …` after each ivar.
    public var addIvarOffsetComments: Bool
    /// Appends the raw `@property` attribute string as a comment.
    public var addPropertyAttributesComments: Bool
    /// Appends `// IMP: 0x…` after each method.
    public var addMethodIMPAddressComments: Bool
    /// Appends `// getter: 0x… setter: 0x…` after each property.
    public var addPropertyAccessorAddressComments: Bool

    public init(
        stripProtocolConformance: Bool = false,
        stripOverrides: Bool = false,
        stripSynthesizedIvars: Bool = false,
        stripSynthesizedMethods: Bool = false,
        stripCtorMethod: Bool = false,
        stripDtorMethod: Bool = false,
        addIvarOffsetComments: Bool = false,
        addPropertyAttributesComments: Bool = false,
        addMethodIMPAddressComments: Bool = false,
        addPropertyAccessorAddressComments: Bool = false
    ) {
        self.stripProtocolConformance = stripProtocolConformance
        self.stripOverrides = stripOverrides
        self.stripSynthesizedIvars = stripSynthesizedIvars
        self.stripSynthesizedMethods = stripSynthesizedMethods
        self.stripCtorMethod = stripCtorMethod
        self.stripDtorMethod = stripDtorMethod
        self.addIvarOffsetComments = addIvarOffsetComments
        self.addPropertyAttributesComments = addPropertyAttributesComments
        self.addMethodIMPAddressComments = addMethodIMPAddressComments
        self.addPropertyAccessorAddressComments = addPropertyAccessorAddressComments
    }

    // Missing-key-tolerant decoding (compatible with the previous MetaCodable
    // `@Default(false)` persistence).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.stripProtocolConformance = try container.decodeIfPresent(Bool.self, forKey: .stripProtocolConformance) ?? false
        self.stripOverrides = try container.decodeIfPresent(Bool.self, forKey: .stripOverrides) ?? false
        self.stripSynthesizedIvars = try container.decodeIfPresent(Bool.self, forKey: .stripSynthesizedIvars) ?? false
        self.stripSynthesizedMethods = try container.decodeIfPresent(Bool.self, forKey: .stripSynthesizedMethods) ?? false
        self.stripCtorMethod = try container.decodeIfPresent(Bool.self, forKey: .stripCtorMethod) ?? false
        self.stripDtorMethod = try container.decodeIfPresent(Bool.self, forKey: .stripDtorMethod) ?? false
        self.addIvarOffsetComments = try container.decodeIfPresent(Bool.self, forKey: .addIvarOffsetComments) ?? false
        self.addPropertyAttributesComments = try container.decodeIfPresent(Bool.self, forKey: .addPropertyAttributesComments) ?? false
        self.addMethodIMPAddressComments = try container.decodeIfPresent(Bool.self, forKey: .addMethodIMPAddressComments) ?? false
        self.addPropertyAccessorAddressComments = try container.decodeIfPresent(Bool.self, forKey: .addPropertyAccessorAddressComments) ?? false
    }

    public static let `default` = Self()
}
