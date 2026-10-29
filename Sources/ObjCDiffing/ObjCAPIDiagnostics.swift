/// One identity-key collision a comparison resolved silently: records in the
/// same keying scope (one container's members, or one container axis)
/// carried the same identity, one of them was kept and compared, and the
/// others were dropped although they differ from it.
///
/// A dropped record can hide a change — most realistically a removal
/// classified as compatible. Two sources are real. Among members, a class of
/// a system framework holds the same identity several times once the linker
/// has merged its categories into it; only the copies that differ from the
/// kept one and repeat no adopted protocol's declaration are listed (see
/// `ObjCMemberSelection`). Among containers, the images of an image group
/// can each hold a class or protocol of one name, and the first image's is
/// kept.
public struct ObjCAPIKeyCollision: Sendable, Codable, Equatable {
    /// The identity that collided.
    public let key: ObjCAPIKey
    /// The owning container's reporting name; `nil` for a container-level
    /// collision.
    public let containerName: String?
    /// Human-readable renderings of the records that were dropped.
    public let droppedSignatures: [String]
    /// The image each dropped record came from, one per `droppedSignatures`
    /// entry, when the evolution compares image groups; `nil` otherwise.
    public let droppedImageNames: [String]?
    /// The rendering of the record that was kept and compared — for a
    /// container-level collision, the container's name. `nil` in a diff or
    /// evolution encoded before it was recorded.
    public let keptSignature: String?
    /// The image the kept record came from, when the evolution compares image
    /// groups; `nil` otherwise.
    public let keptImageName: String?

    public init(
        key: ObjCAPIKey,
        containerName: String?,
        droppedSignatures: [String],
        droppedImageNames: [String]? = nil,
        keptSignature: String? = nil,
        keptImageName: String? = nil
    ) {
        self.key = key
        self.containerName = containerName
        self.droppedSignatures = droppedSignatures
        self.droppedImageNames = droppedImageNames
        self.keptSignature = keptSignature
        self.keptImageName = keptImageName
    }
}

extension ObjCAPIKeyCollision {
    /// The dropped records as the warnings list them: each signature, then
    /// its image in parentheses where known — `NSFoo (UIFoundation)`.
    package var droppedRecordsDescription: String {
        guard let droppedImageNames, droppedImageNames.count == droppedSignatures.count else {
            return droppedSignatures.joined(separator: ", ")
        }
        return zip(droppedSignatures, droppedImageNames)
            .map { droppedSignature, droppedImageName in "\(droppedSignature) (\(droppedImageName))" }
            .joined(separator: ", ")
    }
}

/// The diagnostics side-channel of an `ObjCAPIDiff`: everything the
/// comparison had to resolve silently, surfaced so a verdict is never
/// quietly weaker than it looks. `nil` on the diff when there is nothing to
/// report. (SwiftDiffing's second diagnostics dimension — remangle
/// fallbacks — has no ObjC counterpart: there is no remangle step.)
public struct ObjCAPIDiffDiagnostics: Sendable, Codable, Equatable {
    /// Collisions found while keying the old side's snapshot.
    public let oldSideKeyCollisions: [ObjCAPIKeyCollision]
    /// Collisions found while keying the new side's snapshot.
    public let newSideKeyCollisions: [ObjCAPIKeyCollision]

    public init(
        oldSideKeyCollisions: [ObjCAPIKeyCollision],
        newSideKeyCollisions: [ObjCAPIKeyCollision]
    ) {
        self.oldSideKeyCollisions = oldSideKeyCollisions
        self.newSideKeyCollisions = newSideKeyCollisions
    }

    public var isEmpty: Bool {
        oldSideKeyCollisions.isEmpty && newSideKeyCollisions.isEmpty
    }
}

extension ObjCAPISnapshot {
    /// Every identity-key collision diffing this snapshot resolves silently:
    /// a container key held twice on one axis, whose first container is
    /// compared, and an identity held more than once in one container whose
    /// dropped records could hide a change (see `ObjCMemberSelection`).
    /// Deterministically ordered (container name, then key).
    public func keyCollisions() -> [ObjCAPIKeyCollision] {
        keyCollisions(containerImageName: nil, memberImageName: nil)
    }

    /// ``keyCollisions()``, naming the image of every kept and dropped record
    /// when the snapshot merges an image group: `containerImageName(kind,
    /// index)` is the image of the container at `index` on the axis of
    /// `kind`, and `memberImageName(kind, containerIndex, memberIndex)` that
    /// of one of its members.
    func keyCollisions(
        containerImageName: ((_ kind: ObjCContainerKind, _ containerIndex: Int) -> String)?,
        memberImageName: ((_ kind: ObjCContainerKind, _ containerIndex: Int, _ memberIndex: Int) -> String)?
    ) -> [ObjCAPIKeyCollision] {
        var collisions: [ObjCAPIKeyCollision] = []
        let propertyDeclarations = ObjCProtocolPropertyDeclarations(protocols: protocols)
        let axes: [(kind: ObjCContainerKind, containers: [ObjCContainerSnapshot])] = [
            (.class, classes),
            (.protocol, protocols),
            (.category, categories),
        ]
        for axis in axes {
            collectContainerKeyCollisions(
                axis.containers,
                imageName: containerImageName.map { containerImageName in { containerImageName(axis.kind, $0) } },
                into: &collisions
            )
            for (containerIndex, container) in axis.containers.enumerated() {
                collectMemberKeyCollisions(
                    ObjCMemberSelection(members: container.members, protocolPropertyDeclarations: propertyDeclarations),
                    containerName: container.name,
                    imageName: memberImageName.map { memberImageName in { memberImageName(axis.kind, containerIndex, $0) } },
                    into: &collisions
                )
            }
        }
        return collisions.sorted {
            ($0.containerName ?? "", $0.key.rawValue) < ($1.containerName ?? "", $1.key.rawValue)
        }
    }

    /// Two containers with the same key on one axis; the first is kept.
    /// Containers surface by name, having no signature. `imageName` names the
    /// image of the container at an index.
    private func collectContainerKeyCollisions(
        _ containers: [ObjCContainerSnapshot],
        imageName: ((_ containerIndex: Int) -> String)?,
        into collisions: inout [ObjCAPIKeyCollision]
    ) {
        var keptContainerIndexByKey: [ObjCAPIKey: Int] = [:]
        var droppedContainerIndicesByKey: [ObjCAPIKey: [Int]] = [:]
        for (containerIndex, container) in containers.enumerated() {
            if keptContainerIndexByKey[container.key] == nil {
                keptContainerIndexByKey[container.key] = containerIndex
            } else {
                droppedContainerIndicesByKey[container.key, default: []].append(containerIndex)
            }
        }
        for (key, droppedContainerIndices) in droppedContainerIndicesByKey {
            guard let keptContainerIndex = keptContainerIndexByKey[key] else { continue }
            collisions.append(ObjCAPIKeyCollision(
                key: key,
                containerName: nil,
                droppedSignatures: droppedContainerIndices.map { containers[$0].name },
                droppedImageNames: imageName.map { imageName in droppedContainerIndices.map(imageName) },
                keptSignature: containers[keptContainerIndex].name,
                keptImageName: imageName?(keptContainerIndex)
            ))
        }
    }

    /// The identities of one container whose dropped records could hide a
    /// change. `imageName` names the image of the member at an index.
    private func collectMemberKeyCollisions(
        _ selection: ObjCMemberSelection,
        containerName: String,
        imageName: ((_ memberIndex: Int) -> String)?,
        into collisions: inout [ObjCAPIKeyCollision]
    ) {
        for (key, droppedMemberIndices) in selection.reportedDroppedMemberIndicesByKey {
            guard let keptMemberIndex = selection.keptMemberIndexByKey[key] else { continue }
            collisions.append(ObjCAPIKeyCollision(
                key: key,
                containerName: containerName,
                droppedSignatures: droppedMemberIndices.map { selection.members[$0].signature },
                droppedImageNames: imageName.map { imageName in droppedMemberIndices.map(imageName) },
                keptSignature: selection.members[keptMemberIndex].signature,
                keptImageName: imageName?(keptMemberIndex)
            ))
        }
    }
}
