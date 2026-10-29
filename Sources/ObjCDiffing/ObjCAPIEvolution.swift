/// One position on an evolution's ordered version axis.
public struct ObjCAPIVersionDescriptor: Sendable, Codable, Equatable {
    /// The human-readable axis name (e.g. `"26.0"`). Always present —
    /// resolved by `ObjCAPIEvolutionBuilder` from explicit labels, snapshot
    /// provenance, or a positional fallback.
    public let label: String
    public let provenance: ObjCAPIProvenance?
    /// The images the version's API was read from, in the order of its image
    /// group, when the evolution compares image groups —
    /// `ObjCAPIEvolutionBuilder.evolution(ofImageGroups:versions:)` sets it
    /// from the group. Empty for a version whose group is empty; `nil` in an
    /// evolution of one image per version.
    public let imageNames: [String]?

    public init(label: String, provenance: ObjCAPIProvenance? = nil, imageNames: [String]? = nil) {
        self.label = label
        self.provenance = provenance
        self.imageNames = imageNames
    }
}

/// A declaration present on both sides of a transition whose images differ,
/// in an evolution that compares image groups: between
/// `versions[versionIndex - 1]` and `versions[versionIndex]` the declaration
/// left `oldImageNames` for `newImageNames`.
///
/// A side's images are every image of that version's group holding the
/// declaration, in group order — one, unless it is duplicated. The order
/// does not count: two sides naming the same images are no move.
///
/// A move never changes a verdict. Whether a client bound to the old image's
/// install name still finds the symbol depends on whether the old image
/// re-exports the new one, which no snapshot records, so a move is reported
/// and not judged.
public struct ObjCImageMove: Sendable, Codable, Equatable {
    /// Always ≥ 1, as for `ObjCLineageEvent`.
    public let versionIndex: Int
    public let oldImageNames: [String]
    public let newImageNames: [String]

    public init(versionIndex: Int, oldImageNames: [String], newImageNames: [String]) {
        self.versionIndex = versionIndex
        self.oldImageNames = oldImageNames
        self.newImageNames = newImageNames
    }
}

/// One transition on a lineage: what happened between the *previous* version
/// and `versions[versionIndex]`.
///
/// `versionIndex` is always ≥ 1 — an event at index `i` describes the
/// `versions[i-1] → versions[i]` step. Presence at the first version is not
/// an event; it is the lineage's `presence[0]` baseline.
public struct ObjCLineageEvent: Sendable, Codable, Equatable {
    public let versionIndex: Int
    public let status: ObjCChangeStatus
    /// Human-readable rendering on the pre-transition side, when present.
    public let oldSignature: String?
    /// Human-readable rendering on the post-transition side, when present.
    public let newSignature: String?
    /// Record-level verdict refinement, same rule as
    /// `ObjCMemberChange.compatibilityOverride` (shared via
    /// `ObjCMemberRecord.compatibilityOverride(old:new:)`); `nil` means the
    /// plain status rule applies. Always `nil` on container-level events.
    public let compatibilityOverride: ObjCCompatibility?

    public init(versionIndex: Int, status: ObjCChangeStatus, oldSignature: String? = nil, newSignature: String? = nil, compatibilityOverride: ObjCCompatibility? = nil) {
        self.versionIndex = versionIndex
        self.status = status
        self.oldSignature = oldSignature
        self.newSignature = newSignature
        self.compatibilityOverride = compatibilityOverride
    }
}

/// The lifeline of one member identity across the version axis.
///
/// Only lineages with at least one event or image move are materialized — an
/// API that never changes never appears, mirroring `ObjCAPIDiff`'s "changes
/// only" contract.
public struct ObjCMemberLineage: Sendable, Codable, Equatable {
    public let key: ObjCAPIKey
    public let kind: ObjCMemberKind
    /// Per-version existence, one entry per version on the axis. For a
    /// member of a container this means "container present AND member
    /// present", so a container-level disappearance turns every member's bit
    /// off too.
    public let presence: [Bool]
    /// Adjacent-version transitions, ordered by `versionIndex`. Member
    /// events exist only for transitions where the owning container is
    /// present on both sides — when the container itself appears/disappears,
    /// the container's own event is the change (same rule as `ObjCAPIDiff`,
    /// whose added/removed containers carry no `memberChanges`).
    public let events: [ObjCLineageEvent]
    /// Transitions where the member changed images differently from its
    /// container, ordered by `versionIndex`: a method a category took to
    /// another image, not every method of a class that moved as a whole.
    /// `nil` when there is none, and always in an evolution of one image per
    /// version.
    public let imageMoves: [ObjCImageMove]?
    /// The member's rendering in the newest version that has it, for a
    /// lineage with no event to take one from — a member that only moved.
    /// `nil` whenever `events` is not empty.
    public let latestSignature: String?

    public init(
        key: ObjCAPIKey,
        kind: ObjCMemberKind,
        presence: [Bool],
        events: [ObjCLineageEvent],
        imageMoves: [ObjCImageMove]? = nil,
        latestSignature: String? = nil
    ) {
        self.key = key
        self.kind = kind
        self.presence = presence
        self.events = events
        self.imageMoves = imageMoves
        self.latestSignature = latestSignature
    }
}

/// The lifeline of one container (class / protocol / category) across the
/// version axis.
public struct ObjCContainerLineage: Sendable, Codable, Equatable {
    public let key: ObjCAPIKey
    /// The container's reporting name, taken from its latest appearance on
    /// the axis.
    public let name: String
    public let containerKind: ObjCContainerKind
    /// Per-version existence, one entry per version on the axis.
    public let presence: [Bool]
    /// Container-level presence transitions only (`.added` / `.removed`).
    /// "Modified at version i" is not a container event — it is derivable as
    /// "has a member event at i", so it is not stored twice.
    public let events: [ObjCLineageEvent]
    /// Member lifelines with at least one event or image move, sorted by key.
    public let memberLineages: [ObjCMemberLineage]
    /// Transitions where a class or category changed images, ordered by
    /// `versionIndex`. `nil` when there is none, always for a protocol — no
    /// image owns one, every image referencing it carries a copy — and always
    /// in an evolution of one image per version.
    public let imageMoves: [ObjCImageMove]?

    public init(
        key: ObjCAPIKey,
        name: String,
        containerKind: ObjCContainerKind,
        presence: [Bool],
        events: [ObjCLineageEvent],
        memberLineages: [ObjCMemberLineage],
        imageMoves: [ObjCImageMove]? = nil
    ) {
        self.key = key
        self.name = name
        self.containerKind = containerKind
        self.presence = presence
        self.events = events
        self.memberLineages = memberLineages
        self.imageMoves = imageMoves
    }
}

/// The structured result of tracking one binary's ObjC API across N ≥ 2
/// ordered versions — the N-way generalization of `ObjCAPIDiff`.
///
/// Buckets mirror `ObjCAPIDiff` one-for-one. A pure value type (`Codable` +
/// `Equatable`), deterministically sorted, so an evolution can be persisted
/// and two evolutions compared directly. For N == 2 the events at
/// `versionIndex == 1` correspond exactly to `ObjCAPIDiffer.diff(old:new:)`'s
/// changes — the two paths cannot disagree.
///
/// An evolution of image groups tracks several images per version as one API
/// surface, so a declaration moving between them is not a removal and an
/// addition. Its events are those of diffing each version's merged snapshot;
/// what moved where is in the lineages' `imageMoves`, which a diff has no
/// counterpart for.
public struct ObjCAPIEvolution: Sendable, Codable, Equatable {
    /// The ordered version axis every `presence` array and `versionIndex`
    /// refers into.
    public let versions: [ObjCAPIVersionDescriptor]
    public let classes: [ObjCContainerLineage]
    public let protocols: [ObjCContainerLineage]
    public let categories: [ObjCContainerLineage]
    /// Identity-key collisions per version (one entry per version on the
    /// axis, aligned with `versions`), `nil` when no version has any. A
    /// collision means first-wins keying dropped a record there, so that
    /// version's transitions can be quietly weaker than reported — the
    /// reporters surface these as warnings.
    public let keyCollisionsByVersion: [[ObjCAPIKeyCollision]]?

    public init(
        versions: [ObjCAPIVersionDescriptor],
        classes: [ObjCContainerLineage] = [],
        protocols: [ObjCContainerLineage] = [],
        categories: [ObjCContainerLineage] = [],
        keyCollisionsByVersion: [[ObjCAPIKeyCollision]]? = nil
    ) {
        self.versions = versions
        self.classes = classes
        self.protocols = protocols
        self.categories = categories
        self.keyCollisionsByVersion = keyCollisionsByVersion
    }

    public var allContainerLineages: [ObjCContainerLineage] {
        classes + protocols + categories
    }

    /// `true` when nothing changed anywhere across the whole axis.
    public var isEmpty: Bool {
        allContainerLineages.isEmpty
    }
}
