/// Builds an `ObjCAPIEvolution` from N ≥ 2 ordered snapshots by computing a
/// key → per-version presence/payload matrix directly — not by joining N−1
/// pairwise diffs. The matrix makes cross-version stories ("removed in v2,
/// re-added in v4") natural products rather than join special-cases, while
/// every per-transition comparison uses exactly the two-sided differ's
/// semantics (identity match on `identityKey`, change detection on
/// `payloadKey`, the record `ObjCMemberSelection` takes for an identity held
/// more than once, the first container for a container key held twice), so
/// for N == 2 the events are the two-sided `ObjCAPIDiff` verbatim.
///
/// `evolution(ofImageGroups:versions:)` tracks several images per version as
/// one API surface instead, merging each version's images before the matrix
/// is computed and recording where declarations moved between them.
public struct ObjCAPIEvolutionBuilder: Sendable {
    public init() {}

    /// Track a binary's ObjC API across ordered persisted baselines (oldest
    /// first).
    ///
    /// Label resolution per version: the explicit `labels` entry if
    /// provided, else the document's `provenance.label`, else a positional
    /// `"v<n>"`.
    public func evolution(of documents: [ObjCAPISnapshotDocument], labels: [String]? = nil) throws -> ObjCAPIEvolution {
        if let labels, labels.count != documents.count {
            throw ObjCAPIEvolutionError.labelCountMismatch(labelCount: labels.count, versionCount: documents.count)
        }
        let versions = documents.enumerated().map { index, document in
            ObjCAPIVersionDescriptor(
                label: labels?[index] ?? document.provenance?.label ?? "v\(index + 1)",
                provenance: document.provenance
            )
        }
        return try evolution(of: documents.map(\.snapshot), versions: versions)
    }

    /// Track a binary's ObjC API across ordered snapshots (oldest first)
    /// under an explicit version axis.
    public func evolution(of snapshots: [ObjCAPISnapshot], versions: [ObjCAPIVersionDescriptor]) throws -> ObjCAPIEvolution {
        try validate(versionCount: snapshots.count, versions: versions)
        return evolution(
            snapshots: snapshots,
            versions: versions,
            keyCollisionsByVersion: snapshots.map { $0.keyCollisions() },
            imageGroups: nil
        )
    }

    /// Track the ObjC API several images make up together across ordered
    /// versions (oldest first), so a declaration moving from one image to
    /// another is a move, not a removal and an addition.
    ///
    /// - Parameters:
    ///   - imageGroups: Each version's images, the primary image first. A
    ///     version holds only the images present in it, so an image can join
    ///     the group partway along the axis; an empty group is a version
    ///     holding nothing.
    ///   - versions: The axis. Each version's `imageNames` is set from its
    ///     group.
    ///
    /// Each version's images merge into one snapshot as
    /// ``ObjCAPIImageGroupMerge`` describes, and the evolution of those is
    /// what the lineages' events state. A class or category, or a member of
    /// one, present on both sides of a transition in different images gets
    /// an ``ObjCImageMove`` there — a member only where it moved differently
    /// from its container. Moves never make a transition breaking.
    public func evolution(ofImageGroups imageGroups: [[ObjCAPIImageSnapshot]], versions: [ObjCAPIVersionDescriptor]) throws -> ObjCAPIEvolution {
        try validate(versionCount: imageGroups.count, versions: versions)
        return try evolution(ofImageGroupMerges: imageGroups.map(ObjCAPIImageGroupMerge.init), versions: versions)
    }

    /// ``evolution(ofImageGroups:versions:)`` over groups a caller merged
    /// already, as `ObjCEvolutionInterfaceBuilder` keeps them.
    package func evolution(ofImageGroupMerges imageGroups: [ObjCAPIImageGroupMerge], versions: [ObjCAPIVersionDescriptor]) throws -> ObjCAPIEvolution {
        try validate(versionCount: imageGroups.count, versions: versions)
        let groupVersions = zip(versions, imageGroups).map { version, imageGroup in
            ObjCAPIVersionDescriptor(label: version.label, provenance: version.provenance, imageNames: imageGroup.imageNames)
        }
        return evolution(
            snapshots: imageGroups.map(\.snapshot),
            versions: groupVersions,
            keyCollisionsByVersion: imageGroups.map(\.keyCollisions),
            imageGroups: imageGroups
        )
    }

    private func validate(versionCount: Int, versions: [ObjCAPIVersionDescriptor]) throws {
        guard versionCount >= 2 else {
            throw ObjCAPIEvolutionError.fewerThanTwoVersions(versionCount: versionCount)
        }
        guard versionCount == versions.count else {
            throw ObjCAPIEvolutionError.labelCountMismatch(labelCount: versions.count, versionCount: versionCount)
        }
    }

    /// The evolution of validated inputs. `imageGroups`, when given, holds
    /// each version's merged group, whose images the moves are computed from.
    private func evolution(
        snapshots: [ObjCAPISnapshot],
        versions: [ObjCAPIVersionDescriptor],
        keyCollisionsByVersion: [[ObjCAPIKeyCollision]],
        imageGroups: [ObjCAPIImageGroupMerge]?
    ) -> ObjCAPIEvolution {
        let requirementsByVersion = snapshots.map { ObjCProtocolRequirements(protocols: $0.protocols) }
        let propertyDeclarationsByVersion = snapshots.map { ObjCProtocolPropertyDeclarations(protocols: $0.protocols) }
        return ObjCAPIEvolution(
            versions: versions,
            classes: containerLineages(snapshots.map(\.classes), propertyDeclarationsByVersion: propertyDeclarationsByVersion, imageGroups: imageGroups),
            // No image owns a protocol, so protocols never move.
            protocols: containerLineages(snapshots.map(\.protocols), propertyDeclarationsByVersion: propertyDeclarationsByVersion, imageGroups: nil) { adoption, protocolName, versionIndex in
                ObjCMemberRecord.adoptionCompatibilityOverride(
                    adding: adoption,
                    toProtocolNamed: protocolName,
                    oldRequirements: requirementsByVersion[versionIndex - 1],
                    newRequirements: requirementsByVersion[versionIndex]
                )
            },
            categories: containerLineages(snapshots.map(\.categories), propertyDeclarationsByVersion: propertyDeclarationsByVersion, imageGroups: imageGroups),
            keyCollisionsByVersion: keyCollisionsByVersion.allSatisfy(\.isEmpty) ? nil : keyCollisionsByVersion
        )
    }

    // MARK: - Container axis

    /// One container bucket (classes, protocols, or categories) across all
    /// versions: `perVersionContainers[i]` is that bucket in version `i`,
    /// whose members' protocol copies `propertyDeclarationsByVersion[i]`
    /// tells apart. `imageGroups`, when given, holds each version's merged
    /// group, which the bucket's moves are computed from.
    /// `addedAdoptionOverride` judges an adoption a container gains, given the
    /// container's name and the version it appears in; only the protocol
    /// bucket passes one.
    private func containerLineages(
        _ perVersionContainers: [[ObjCContainerSnapshot]],
        propertyDeclarationsByVersion: [ObjCProtocolPropertyDeclarations],
        imageGroups: [ObjCAPIImageGroupMerge]?,
        addedAdoptionOverride: ((_ adoption: ObjCMemberRecord, _ containerName: String, _ versionIndex: Int) -> ObjCCompatibility?)? = nil
    ) -> [ObjCContainerLineage] {
        let keyedPerVersion = perVersionContainers.map { keyedFirstWins($0, by: \.key) }
        let orderedKeys = unionOfKeys(keyedPerVersion)

        var lineages: [ObjCContainerLineage] = []
        for containerKey in orderedKeys {
            let perVersion = keyedPerVersion.map { $0[containerKey] }
            let presence = perVersion.map { $0 != nil }
            let containerEvents = presenceTransitionEvents(presence)
            // Name/kind from the latest appearance, so a report shows the
            // most recent spelling of the container.
            let latest = perVersion.reversed().compactMap { $0 }.first!
            let containerMoves = imageGroups.map { imageGroups in
                imageMoves(presence: presence) { versionIndex in
                    imageGroups[versionIndex].imageNames(ofContainer: containerKey) ?? []
                }
            } ?? []
            let members = memberLineages(
                perVersionSelections: perVersion.enumerated().map { versionIndex, container in
                    container.map { container in
                        ObjCMemberSelection(
                            members: container.members,
                            protocolPropertyDeclarations: propertyDeclarationsByVersion[versionIndex]
                        )
                    }
                },
                containerKey: containerKey,
                imageGroups: imageGroups,
                addedAdoptionOverride: addedAdoptionOverride.map { override in
                    { adoption, versionIndex in override(adoption, latest.name, versionIndex) }
                }
            )
            guard !containerEvents.isEmpty || !members.isEmpty || !containerMoves.isEmpty else { continue }
            lineages.append(ObjCContainerLineage(
                key: containerKey,
                name: latest.name,
                containerKind: latest.kind,
                presence: presence,
                events: containerEvents,
                memberLineages: members,
                imageMoves: containerMoves.isEmpty ? nil : containerMoves
            ))
        }
        return lineages.sorted { $0.key.rawValue < $1.key.rawValue }
    }

    // MARK: - Member axis

    /// Member lifelines across versions. `perVersionSelections[i]` is the
    /// record the container takes for each identity in version `i`, and the
    /// protocol each property came with, `nil` when the owning container is
    /// absent there. Member events are
    /// computed only for transitions where both adjacent versions have the
    /// container — a container-level appearance/disappearance is the
    /// container's own event, and enumerating members across the gap would
    /// diverge from the two-sided differ (which leaves an added/removed
    /// container's `memberChanges` empty). With `imageGroups`, a member
    /// present on both sides of a transition moves there when its images
    /// change otherwise than those of `containerKey`, its container.
    private func memberLineages(
        perVersionSelections: [ObjCMemberSelection?],
        containerKey: ObjCAPIKey,
        imageGroups: [ObjCAPIImageGroupMerge]?,
        addedAdoptionOverride: ((_ adoption: ObjCMemberRecord, _ versionIndex: Int) -> ObjCCompatibility?)?
    ) -> [ObjCMemberLineage] {
        let keyedPerVersion = perVersionSelections.map { $0?.keptMembersByKey }
        let orderedKeys = unionOfKeys(keyedPerVersion.map { $0 ?? [:] })

        var lineages: [ObjCMemberLineage] = []
        for memberKey in orderedKeys {
            let perVersion = keyedPerVersion.map { $0?[memberKey] }
            let presence = perVersion.map { $0 != nil }

            var events: [ObjCLineageEvent] = []
            for versionIndex in 1 ..< perVersion.count {
                guard keyedPerVersion[versionIndex - 1] != nil, keyedPerVersion[versionIndex] != nil else {
                    continue
                }
                let oldRecord = perVersion[versionIndex - 1]
                let newRecord = perVersion[versionIndex]
                let oldProtocolName = perVersionSelections[versionIndex - 1]?.keptProtocolNameByKey[memberKey]
                let newProtocolName = perVersionSelections[versionIndex]?.keptProtocolNameByKey[memberKey]
                switch (oldRecord, newRecord) {
                case (nil, let newRecord?):
                    let compatibilityOverride: ObjCCompatibility? = if newRecord.kind == .protocolAdoption, let addedAdoptionOverride {
                        addedAdoptionOverride(newRecord, versionIndex)
                    } else {
                        ObjCMemberRecord.compatibilityOverride(old: nil, new: newRecord)
                    }
                    events.append(ObjCLineageEvent(
                        versionIndex: versionIndex,
                        status: .added,
                        newSignature: newRecord.signature,
                        compatibilityOverride: compatibilityOverride,
                        viaProtocolName: newProtocolName
                    ))
                case (let oldRecord?, nil):
                    events.append(ObjCLineageEvent(
                        versionIndex: versionIndex,
                        status: .removed,
                        oldSignature: oldRecord.signature,
                        compatibilityOverride: ObjCMemberRecord.compatibilityOverride(old: oldRecord, new: nil),
                        viaProtocolName: oldProtocolName
                    ))
                case (let oldRecord?, let newRecord?) where oldRecord.payloadKey != newRecord.payloadKey:
                    events.append(ObjCLineageEvent(
                        versionIndex: versionIndex,
                        status: .modified,
                        oldSignature: oldRecord.signature,
                        newSignature: newRecord.signature,
                        compatibilityOverride: ObjCMemberRecord.compatibilityOverride(old: oldRecord, new: newRecord),
                        viaProtocolName: newProtocolName
                    ))
                default:
                    break
                }
            }
            let moves = imageGroups.map { imageGroups in
                memberImageMoves(memberKey, perVersion: perVersion, containerKey: containerKey, imageGroups: imageGroups)
            } ?? []
            guard !events.isEmpty || !moves.isEmpty else { continue }
            // The record must exist somewhere on the axis for an event or a
            // move to have been produced, so the latest appearance always
            // resolves a kind and a signature.
            let latest = perVersion.reversed().compactMap { $0 }.first!
            lineages.append(ObjCMemberLineage(
                key: memberKey,
                kind: latest.kind,
                presence: presence,
                events: events,
                imageMoves: moves.isEmpty ? nil : moves,
                latestSignature: events.isEmpty ? latest.signature : nil
            ))
        }
        return lineages.sorted { $0.key.rawValue < $1.key.rawValue }
    }

    // MARK: - Image moves

    /// A move at every transition where the declaration is present on both
    /// sides and `imageNamesAt` names other images on each.
    private func imageMoves(presence: [Bool], imageNamesAt: (_ versionIndex: Int) -> [String]) -> [ObjCImageMove] {
        var moves: [ObjCImageMove] = []
        for versionIndex in 1 ..< presence.count where presence[versionIndex - 1] && presence[versionIndex] {
            let oldImageNames = imageNamesAt(versionIndex - 1)
            let newImageNames = imageNamesAt(versionIndex)
            if Self.nameDifferentImages(oldImageNames, newImageNames) {
                moves.append(ObjCImageMove(versionIndex: versionIndex, oldImageNames: oldImageNames, newImageNames: newImageNames))
            }
        }
        return moves
    }

    /// A member's moves: transitions where it is present on both sides and
    /// its images change, unless they change exactly as its container's do —
    /// every member of a class that moved as a whole would otherwise repeat
    /// the class's move. `perVersion[i]` is the member's record in version
    /// `i`.
    private func memberImageMoves(
        _ memberKey: ObjCAPIKey,
        perVersion: [ObjCMemberRecord?],
        containerKey: ObjCAPIKey,
        imageGroups: [ObjCAPIImageGroupMerge]
    ) -> [ObjCImageMove] {
        var moves: [ObjCImageMove] = []
        for versionIndex in 1 ..< perVersion.count {
            guard perVersion[versionIndex - 1] != nil, perVersion[versionIndex] != nil else { continue }
            let oldGroup = imageGroups[versionIndex - 1]
            let newGroup = imageGroups[versionIndex]
            let oldImageNames = oldGroup.imageNames(ofMember: memberKey, inContainer: containerKey) ?? []
            let newImageNames = newGroup.imageNames(ofMember: memberKey, inContainer: containerKey) ?? []
            guard Self.nameDifferentImages(oldImageNames, newImageNames) else { continue }
            let oldContainerImageNames = oldGroup.imageNames(ofContainer: containerKey) ?? []
            let newContainerImageNames = newGroup.imageNames(ofContainer: containerKey) ?? []
            guard Self.nameDifferentImages(oldImageNames, oldContainerImageNames)
                || Self.nameDifferentImages(newImageNames, newContainerImageNames)
            else { continue }
            moves.append(ObjCImageMove(versionIndex: versionIndex, oldImageNames: oldImageNames, newImageNames: newImageNames))
        }
        return moves
    }

    /// Whether two image lists name different images. Each list is in its
    /// own version's group order, which does not count.
    private static func nameDifferentImages(_ lhs: [String], _ rhs: [String]) -> Bool {
        lhs != rhs && Set(lhs) != Set(rhs)
    }

    // MARK: - Primitives

    /// `.added` / `.removed` events at every adjacent presence flip.
    private func presenceTransitionEvents(_ presence: [Bool]) -> [ObjCLineageEvent] {
        var events: [ObjCLineageEvent] = []
        for versionIndex in 1 ..< presence.count {
            switch (presence[versionIndex - 1], presence[versionIndex]) {
            case (false, true):
                events.append(ObjCLineageEvent(versionIndex: versionIndex, status: .added))
            case (true, false):
                events.append(ObjCLineageEvent(versionIndex: versionIndex, status: .removed))
            default:
                break
            }
        }
        return events
    }

    /// The union of every version's keys, in stable sorted order.
    private func unionOfKeys<Value>(_ keyedPerVersion: [[ObjCAPIKey: Value]]) -> [ObjCAPIKey] {
        var seen: Set<ObjCAPIKey> = []
        var union: [ObjCAPIKey] = []
        for keyed in keyedPerVersion {
            for key in keyed.keys where !seen.contains(key) {
                seen.insert(key)
                union.append(key)
            }
        }
        return union.sorted { $0.rawValue < $1.rawValue }
    }
}

/// Input-shape failures of `ObjCAPIEvolutionBuilder`.
public enum ObjCAPIEvolutionError: Error, Equatable, CustomStringConvertible {
    case fewerThanTwoVersions(versionCount: Int)
    case labelCountMismatch(labelCount: Int, versionCount: Int)

    public var description: String {
        switch self {
        case .fewerThanTwoVersions(let versionCount):
            return "ObjC API evolution needs at least 2 versions, got \(versionCount)."
        case .labelCountMismatch(let labelCount, let versionCount):
            return "Got \(labelCount) labels for \(versionCount) versions; the counts must match."
        }
    }
}
