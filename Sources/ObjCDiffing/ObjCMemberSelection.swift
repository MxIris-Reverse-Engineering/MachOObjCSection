/// The property declarations the protocols of one snapshot make: each
/// protocol's own and, through its adoptions, those of every protocol it
/// adopts, however deep. clang copies these into the property list of every
/// class and category adopting the protocol, so a record matching one is a
/// copy of the protocol's declaration rather than the container's own.
///
/// A snapshot keeps only a protocol's direct adoptions (the `adopts:`
/// records), so the deeper levels are found by name in the snapshot's own
/// protocol table, as `ObjCProtocolRequirements` finds them. Every copy of a
/// protocol the table holds counts, since an image group keeps each image's
/// copy that differs from the others.
struct ObjCProtocolPropertyDeclarations: Sendable {
    /// A property's identity and its payload as a class or category record
    /// carries it.
    struct Declaration: Hashable, Sendable {
        let identityKey: ObjCAPIKey
        let payloadKey: ObjCAPIKey
    }

    private let protocolsByName: [String: [ObjCContainerSnapshot]]

    init(protocols: [ObjCContainerSnapshot]) {
        protocolsByName = Dictionary(grouping: protocols, by: \.name)
    }

    /// The property declarations the protocols `members` adopt copy into
    /// their container. A protocol the table does not hold contributes
    /// nothing, so a copy of its declarations reads as the container's own.
    func declarations(adoptedBy members: [ObjCMemberRecord]) -> Set<Declaration> {
        var adoptedDeclarations: Set<Declaration> = []
        var visitedProtocolNames: Set<String> = []
        var pendingProtocolNames = members.compactMap(\.adoptedProtocolName)
        while let protocolName = pendingProtocolNames.popLast() {
            guard visitedProtocolNames.insert(protocolName).inserted else { continue }
            for protocolSnapshot in protocolsByName[protocolName] ?? [] {
                for member in protocolSnapshot.members {
                    switch member.kind {
                    case .instanceProperty, .classProperty:
                        adoptedDeclarations.insert(Declaration(identityKey: member.identityKey, payloadKey: member.payloadKeyWithoutOptionality))
                    case .protocolAdoption:
                        if let adoptedProtocolName = member.adoptedProtocolName {
                            pendingProtocolNames.append(adoptedProtocolName)
                        }
                    case .instanceMethod, .classMethod, .ivar, .superclass:
                        break
                    }
                }
            }
        }
        return adoptedDeclarations
    }
}

/// Which of a container's records a comparison takes for each identity key,
/// and which of the others a warning names. The two-sided differ, the
/// evolution builder, `ObjCAPISnapshot.keyCollisions()` and the merged
/// header all take the record this names, so what is compared, what is
/// warned about and what is printed always agree.
///
/// A container can hold an identity several times, and a class of a system
/// framework often does. The linker merges the categories an image adds to
/// its own classes into those classes, the categories' lists ahead of the
/// class's own and nothing deduplicated (`PropertyListAtom` in ld64's
/// `src/ld/passes/objc.cpp`), and clang copies into a category's property
/// list every property the protocols it adopts declare
/// (`PushProtocolProperties` in `CGObjCMac.cpp`). So a class carries
/// `NSObject`'s `hash` once for each such category, and `NSView` carries
/// `NSLayoutItem`'s read-only `frame` ahead of its own read-write one.
///
/// The record taken is the first that is not a copy of an adopted protocol's
/// declaration, or the first of all when every one is. Methods are never
/// copied, so a selector held twice takes its first record, the one the
/// runtime dispatches to: a merged category's methods come before the
/// class's own. A record left out is worth a warning only when it is no
/// protocol copy and its payload differs from the taken one's. An identical
/// record hides nothing, and the protocol's own container reports the
/// changes of what a protocol copy repeats.
struct ObjCMemberSelection: Sendable {
    /// The container's records, in order.
    let members: [ObjCMemberRecord]
    /// For each identity key, the position in `members` of the record taken.
    let keptMemberIndexByKey: [ObjCAPIKey: Int]
    /// For each identity key whose records left out could hide a change, the
    /// positions in `members` of those records, in order.
    let reportedDroppedMemberIndicesByKey: [ObjCAPIKey: [Int]]
    /// For each identity key held more than once, which of its records is
    /// taken: 0 for the first record with the key, 1 for the second, and so on.
    let keptOccurrenceByDuplicatedKey: [ObjCAPIKey: Int]

    init(members: [ObjCMemberRecord], protocolPropertyDeclarations: ObjCProtocolPropertyDeclarations) {
        var memberIndicesByKey: [ObjCAPIKey: [Int]] = [:]
        memberIndicesByKey.reserveCapacity(members.count)
        for (memberIndex, member) in members.enumerated() {
            memberIndicesByKey[member.identityKey, default: []].append(memberIndex)
        }

        var keptMemberIndexByKey: [ObjCAPIKey: Int] = [:]
        keptMemberIndexByKey.reserveCapacity(memberIndicesByKey.count)
        var reportedDroppedMemberIndicesByKey: [ObjCAPIKey: [Int]] = [:]
        var keptOccurrenceByDuplicatedKey: [ObjCAPIKey: Int] = [:]
        // Most containers hold each identity once, so the adopted protocols
        // are walked only for one that does not.
        var adoptedDeclarationsOfContainer: Set<ObjCProtocolPropertyDeclarations.Declaration>?
        for (memberKey, memberIndices) in memberIndicesByKey {
            guard memberIndices.count > 1 else {
                keptMemberIndexByKey[memberKey] = memberIndices[0]
                continue
            }
            let protocolCopies = adoptedDeclarationsOfContainer ?? protocolPropertyDeclarations.declarations(adoptedBy: members)
            adoptedDeclarationsOfContainer = protocolCopies
            let isProtocolCopy = { (memberIndex: Int) in
                protocolCopies.contains(ObjCProtocolPropertyDeclarations.Declaration(
                    identityKey: members[memberIndex].identityKey,
                    payloadKey: members[memberIndex].payloadKey
                ))
            }
            let keptOccurrence = memberIndices.firstIndex { !isProtocolCopy($0) } ?? 0
            let keptMemberIndex = memberIndices[keptOccurrence]
            keptMemberIndexByKey[memberKey] = keptMemberIndex
            keptOccurrenceByDuplicatedKey[memberKey] = keptOccurrence
            let keptPayloadKey = members[keptMemberIndex].payloadKey
            let reportedMemberIndices = memberIndices.filter { memberIndex in
                memberIndex != keptMemberIndex
                    && !isProtocolCopy(memberIndex)
                    && members[memberIndex].payloadKey != keptPayloadKey
            }
            if !reportedMemberIndices.isEmpty {
                reportedDroppedMemberIndicesByKey[memberKey] = reportedMemberIndices
            }
        }

        self.members = members
        self.keptMemberIndexByKey = keptMemberIndexByKey
        self.reportedDroppedMemberIndicesByKey = reportedDroppedMemberIndicesByKey
        self.keptOccurrenceByDuplicatedKey = keptOccurrenceByDuplicatedKey
    }

    /// The record taken for each identity key.
    var keptMembersByKey: [ObjCAPIKey: ObjCMemberRecord] {
        keptMemberIndexByKey.mapValues { members[$0] }
    }
}

extension ObjCAPISnapshot {
    /// For each container that holds an identity more than once, which of
    /// the records with that identity a comparison takes: 0 for the first,
    /// 1 for the second, and so on, in member order. Containers holding each
    /// identity once are left out. A container key held twice on one axis
    /// counts its first container, the one compared.
    ///
    /// The merged header takes the record a comparison takes by counting the
    /// records of each identity as it renders them.
    package func keptMemberOccurrences() -> [ObjCAPIKey: [ObjCAPIKey: Int]] {
        let propertyDeclarations = ObjCProtocolPropertyDeclarations(protocols: protocols)
        var visitedContainerKeys: Set<ObjCAPIKey> = []
        var keptOccurrencesByContainer: [ObjCAPIKey: [ObjCAPIKey: Int]] = [:]
        for container in classes + protocols + categories where visitedContainerKeys.insert(container.key).inserted {
            let keptOccurrences = ObjCMemberSelection(members: container.members, protocolPropertyDeclarations: propertyDeclarations)
                .keptOccurrenceByDuplicatedKey
            if !keptOccurrences.isEmpty {
                keptOccurrencesByContainer[container.key] = keptOccurrences
            }
        }
        return keptOccurrencesByContainer
    }
}
