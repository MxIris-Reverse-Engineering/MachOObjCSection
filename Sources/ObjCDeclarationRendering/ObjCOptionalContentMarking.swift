import Semantic

// MARK: - Option Names

extension ObjCGenerationOptions {
    /// The ten switches, as the option names the `VisibilityRegion`s of a
    /// marked rendering are conditioned on (see
    /// `ObjCInterfaceBuilder.markedClassInterface(named:cTypeReplacements:ivarOffsetCommentBuilder:)`).
    public enum VisibilityOption: String, CaseIterable, Sendable {
        case stripProtocolConformance = "objc.stripProtocolConformance"
        case stripOverrides = "objc.stripOverrides"
        case stripSynthesizedIvars = "objc.stripSynthesizedIvars"
        case stripSynthesizedMethods = "objc.stripSynthesizedMethods"
        case stripCtorMethod = "objc.stripCtorMethod"
        case stripDtorMethod = "objc.stripDtorMethod"
        case addIvarOffsetComments = "objc.addIvarOffsetComments"
        case addPropertyAttributesComments = "objc.addPropertyAttributesComments"
        case addMethodIMPAddressComments = "objc.addMethodIMPAddressComments"
        case addPropertyAccessorAddressComments = "objc.addPropertyAccessorAddressComments"
    }

    /// Whether `option` is on.
    public func isEnabled(_ option: VisibilityOption) -> Bool {
        switch option {
        case .stripProtocolConformance: stripProtocolConformance
        case .stripOverrides: stripOverrides
        case .stripSynthesizedIvars: stripSynthesizedIvars
        case .stripSynthesizedMethods: stripSynthesizedMethods
        case .stripCtorMethod: stripCtorMethod
        case .stripDtorMethod: stripDtorMethod
        case .addIvarOffsetComments: addIvarOffsetComments
        case .addPropertyAttributesComments: addPropertyAttributesComments
        case .addMethodIMPAddressComments: addMethodIMPAddressComments
        case .addPropertyAccessorAddressComments: addPropertyAccessorAddressComments
        }
    }

    /// Whether the switch named `optionName` is on — the predicate to
    /// project a marked rendering with. A name that is not one of these
    /// switches reads as off.
    public func isVisibilityOptionEnabled(_ optionName: String) -> Bool {
        VisibilityOption(rawValue: optionName).map(isEnabled) ?? false
    }
}

// MARK: - Marking

/// What a marked rendering needs besides the metadata: for each member some
/// strip switch would remove, the switches that would.
///
/// A member is visible when every one of its switches is off. Comments need
/// nothing here: in a marked rendering each comment is conditioned on its
/// own `add…Comments` switch.
public struct ObjCOptionalContentMarking: Sendable {
    /// Which list a member comes from, since a class method and an instance
    /// method, or a property and an ivar, can share a name.
    public enum MemberKind: Hashable, Sendable {
        case ivar
        case classProperty
        case property
        case classMethod
        case method
    }

    public struct Member: Hashable, Sendable {
        public let kind: MemberKind
        public let name: String

        public init(kind: MemberKind, name: String) {
            self.kind = kind
            self.name = name
        }
    }

    /// The strip switches that would remove each member; a member absent
    /// here is always shown.
    public var strippingOptionsByMember: [Member: Set<ObjCGenerationOptions.VisibilityOption>]

    public init(strippingOptionsByMember: [Member: Set<ObjCGenerationOptions.VisibilityOption>] = [:]) {
        self.strippingOptionsByMember = strippingOptionsByMember
    }

    /// When the member is visible: every switch that would remove it is off.
    public func condition(for kind: MemberKind, named name: String) -> VisibilityCondition {
        guard let strippingOptions = strippingOptionsByMember[Member(kind: kind, name: name)], !strippingOptions.isEmpty else {
            return .always
        }
        return .all(strippingOptions.map { .disabled($0.rawValue) })
    }
}

// MARK: - Rendering Helpers

extension ObjCRenderingContext {
    /// A member the marking may hide, or `content` itself when not marking.
    @SemanticStringBuilder
    func member(_ kind: ObjCOptionalContentMarking.MemberKind, named name: String, @SemanticStringBuilder content: () -> SemanticString) -> SemanticString {
        if let optionalContentMarking {
            VisibilityRegion(optionalContentMarking.condition(for: kind, named: name), content: content())
        } else {
            content()
        }
    }

    /// `content` when `option` is on. When marking, always, conditioned on
    /// `option`.
    @SemanticStringBuilder
    func optionalContent(_ option: ObjCGenerationOptions.VisibilityOption, @SemanticStringBuilder content: () -> SemanticString) -> SemanticString {
        if optionalContentMarking != nil {
            VisibilityRegion(.enabled(option.rawValue), content: content())
        } else if options.isEnabled(option) {
            content()
        }
    }
}
