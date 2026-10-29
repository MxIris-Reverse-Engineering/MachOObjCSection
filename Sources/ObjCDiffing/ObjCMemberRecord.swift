import ObjCDump
import ObjCTypeDecodeKit

/// The kind of a diffed member, used for reporting and to keep members of
/// different kinds in distinct identity namespaces.
public enum ObjCMemberKind: Sendable, Codable, Equatable {
    case instanceMethod
    case classMethod
    case instanceProperty
    case classProperty
    case ivar
    /// A directly adopted protocol (`adopts:` namespace) — only ever
    /// added/removed, never modified.
    case protocolAdoption
    /// A class container's superclass, projected as a pseudo-member so a
    /// reparenting reports the class as modified (old → new) instead of
    /// removed + added.
    case superclass
}

/// A diff-ready projection of one member.
///
/// Two keys drive the algorithm:
/// - `identityKey` matches members across the two sides (added / removed /
///   common). It is the member's runtime identity: `+`/`-` plus the selector
///   for methods, `+`/`-` plus the name for properties, the name for ivars.
/// - `payloadKey` detects a change *among matched* members. It folds in every
///   comparison-relevant attribute the identity does not already encode: the
///   type encoding for methods and ivars, the normalized attribute string for
///   properties (with the synthesized backing-ivar `V` attribute stripped —
///   ivar renames are the ivar axis's story), and the required/optional flag
///   for protocol members (so a requiredness migration reports `.modified`).
///
/// Deliberately excluded from both keys: `ObjCMethodInfo.imp` (an address,
/// different on every build), `ObjCIvarInfo.offset` (slid by the non-fragile
/// runtime, and one mid-list insertion would cascade-modify every later
/// ivar), and `ObjCClassInfo.instanceSize` / `.imageName` (derived values).
public struct ObjCMemberRecord: Sendable, Codable, Equatable {
    public let identityKey: ObjCAPIKey
    public let payloadKey: ObjCAPIKey
    public let kind: ObjCMemberKind
    /// Human-readable rendering, surfaced on `ObjCMemberChange`.
    public let signature: String
    /// Protocol members only: whether the requirement is `@optional`.
    /// Verdict metadata for the compatibility refinement (a required
    /// requirement added to a protocol breaks existing conformers), never
    /// part of the keys — the keys carry it separately. `nil` for anything
    /// that is not a protocol member.
    public let isOptionalRequirement: Bool?

    public init(
        identityKey: ObjCAPIKey,
        payloadKey: ObjCAPIKey,
        kind: ObjCMemberKind,
        signature: String,
        isOptionalRequirement: Bool? = nil
    ) {
        self.identityKey = identityKey
        self.payloadKey = payloadKey
        self.kind = kind
        self.signature = signature
        self.isOptionalRequirement = isOptionalRequirement
    }
}

// MARK: - Projection from the ObjCDump model

extension ObjCMemberRecord {
    /// A method, keyed on its dispatch identity (`+`/`-` + selector) with the
    /// type encoding as payload. Unlike SwiftDiffing — where a re-signed
    /// function is a new mangled symbol and honestly reports removed + added —
    /// an ObjC method's entry point *is* its selector, so an encoding change
    /// at the same selector reports `.modified` (old → new side by side).
    public static func make(_ methodInfo: ObjCMethodInfo, isOptionalRequirement: Bool? = nil) -> ObjCMemberRecord {
        ObjCMemberRecord(
            identityKey: identityKey(of: methodInfo),
            payloadKey: ObjCAPIKey(rawValue: "enc:\(methodInfo.typeEncoding)" + optionalitySuffix(isOptionalRequirement)),
            kind: methodInfo.isClassMethod ? .classMethod : .instanceMethod,
            signature: methodInfo.headerString,
            isOptionalRequirement: isOptionalRequirement
        )
    }

    /// A property, keyed on `+`/`-` + name with the normalized attribute list
    /// as payload. The `V<ivarName>` attribute (the synthesized backing ivar)
    /// is stripped from the payload: it is an implementation detail whose
    /// changes the ivar axis already reports, and folding it in would turn
    /// every backing-ivar rename into property noise.
    public static func make(_ propertyInfo: ObjCPropertyInfo, isOptionalRequirement: Bool? = nil) -> ObjCMemberRecord {
        let normalizedAttributes = propertyInfo.attributes
            .filter { attribute in
                if case .ivar = attribute { return false }
                return true
            }
            .map { $0.encoded() }
            .joined(separator: ",")
        return ObjCMemberRecord(
            identityKey: identityKey(of: propertyInfo),
            payloadKey: ObjCAPIKey(rawValue: "attr:\(normalizedAttributes)" + optionalitySuffix(isOptionalRequirement)),
            kind: propertyInfo.isClassProperty ? .classProperty : .instanceProperty,
            signature: propertyInfo.headerString,
            isOptionalRequirement: isOptionalRequirement
        )
    }

    /// An ivar, keyed by name with the type encoding as payload. The offset is
    /// deliberately not folded in (see the type doc).
    public static func make(_ ivarInfo: ObjCIvarInfo) -> ObjCMemberRecord {
        ObjCMemberRecord(
            identityKey: identityKey(of: ivarInfo),
            payloadKey: ObjCAPIKey(rawValue: "enc:\(ivarInfo.typeEncoding)"),
            kind: .ivar,
            signature: ivarInfo.headerString
        )
    }

    /// The identity key of a method's record, without the rest of the record:
    /// `method:` with `+` or `-` and the selector.
    package static func identityKey(of methodInfo: ObjCMethodInfo) -> ObjCAPIKey {
        ObjCAPIKey(rawValue: "method:\(methodInfo.isClassMethod ? "+" : "-")\(methodInfo.name)")
    }

    /// The identity key of a property's record: `property:` with `+` or `-`
    /// and the name.
    package static func identityKey(of propertyInfo: ObjCPropertyInfo) -> ObjCAPIKey {
        ObjCAPIKey(rawValue: "property:\(propertyInfo.isClassProperty ? "+" : "-")\(propertyInfo.name)")
    }

    /// The identity key of an ivar's record: `ivar:` and the name.
    package static func identityKey(of ivarInfo: ObjCIvarInfo) -> ObjCAPIKey {
        ObjCAPIKey(rawValue: "ivar:\(ivarInfo.name)")
    }

    /// A directly adopted protocol. Identity equals payload — an adoption can
    /// only appear or disappear.
    public static func makeProtocolAdoption(protocolName: String) -> ObjCMemberRecord {
        let key = ObjCAPIKey(rawValue: Self.protocolAdoptionKeyPrefix + protocolName)
        return ObjCMemberRecord(
            identityKey: key,
            payloadKey: key,
            kind: .protocolAdoption,
            signature: "adopts <\(protocolName)>"
        )
    }

    private static let protocolAdoptionKeyPrefix = "adopts:"

    /// The protocol a `protocolAdoption` record adopts; `nil` for any other
    /// record. Read back from the key, which is the persisted format.
    var adoptedProtocolName: String? {
        guard kind == .protocolAdoption,
              identityKey.rawValue.hasPrefix(Self.protocolAdoptionKeyPrefix) else {
            return nil
        }
        return String(identityKey.rawValue.dropFirst(Self.protocolAdoptionKeyPrefix.count))
    }

    /// A class's superclass as a pseudo-member: stable identity, the
    /// superclass name as payload, so a reparenting reports `.modified` with
    /// both sides visible. A root class carries an empty payload name.
    public static func makeSuperclass(superclassName: String?) -> ObjCMemberRecord {
        ObjCMemberRecord(
            identityKey: ObjCAPIKey(rawValue: "superclass"),
            payloadKey: ObjCAPIKey(rawValue: "super:\(superclassName ?? "")"),
            kind: .superclass,
            signature: "superclass: \(superclassName ?? "(root)")"
        )
    }

    /// The record-level compatibility refinement shared by the two-sided
    /// differ and the evolution builder (one rule, so N == 2 verdicts cannot
    /// disagree). `nil` means "no refinement — use the status rule".
    ///
    /// A protocol member **added as required** is breaking: existing
    /// conformers lack the implementation, so callers relying on the new
    /// contract hit `unrecognized selector`. Added as optional stays additive
    /// (the plain status rule). An adoption a protocol gains is judged by
    /// ``adoptionCompatibilityOverride(adding:toProtocolNamed:oldRequirements:newRequirements:)``,
    /// which needs both snapshots' protocol tables.
    static func compatibilityOverride(old: ObjCMemberRecord?, new: ObjCMemberRecord?) -> ObjCCompatibility? {
        if old == nil, let newRecord = new, newRecord.isOptionalRequirement == false {
            return .breaking
        }
        return nil
    }

    /// The refinement for an adoption a *protocol* gains, shared by the
    /// two-sided differ and the evolution builder like the rule above.
    ///
    /// `@protocol P <Q>` makes every conformer of P implement Q's required
    /// members, as adding them to P directly would. So the adoption is
    /// breaking when Q, followed through its own adoptions in the new
    /// snapshot, requires a member that P, followed the same way in the old
    /// one, did not; otherwise — Q's members all optional, or already required
    /// through another adoption — it stays additive. A Q the new snapshot does
    /// not hold cannot be followed and is judged breaking rather than risk
    /// missing a break. A class or category that adopts a protocol takes on
    /// the implementing side, so this is never applied to them.
    static func adoptionCompatibilityOverride(
        adding adoption: ObjCMemberRecord,
        toProtocolNamed adoptingProtocolName: String,
        oldRequirements: ObjCProtocolRequirements,
        newRequirements: ObjCProtocolRequirements
    ) -> ObjCCompatibility? {
        guard let adoptedProtocolName = adoption.adoptedProtocolName,
              let adoptedRequiredMemberKeys = newRequirements.requiredMemberKeys(ofProtocolNamed: adoptedProtocolName) else {
            return .breaking
        }
        let previouslyRequiredMemberKeys = oldRequirements.requiredMemberKeys(ofProtocolNamed: adoptingProtocolName) ?? []
        return adoptedRequiredMemberKeys.isSubset(of: previouslyRequiredMemberKeys) ? nil : .breaking
    }

    private static func optionalitySuffix(_ isOptionalRequirement: Bool?) -> String {
        guard let isOptionalRequirement else { return "" }
        return "|optional:" + (isOptionalRequirement ? "1" : "0")
    }

    /// The payload without the required/optional part a protocol member's
    /// carries: the payload the same declaration has in a class or category.
    var payloadKeyWithoutOptionality: ObjCAPIKey {
        let optionalitySuffix = Self.optionalitySuffix(isOptionalRequirement)
        guard !optionalitySuffix.isEmpty, payloadKey.rawValue.hasSuffix(optionalitySuffix) else {
            return payloadKey
        }
        return ObjCAPIKey(rawValue: String(payloadKey.rawValue.dropLast(optionalitySuffix.count)))
    }
}
