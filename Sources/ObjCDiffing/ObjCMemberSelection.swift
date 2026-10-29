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

    /// The protocol that declares a property, and how many adoptions away
    /// from the protocol whose closure it is in: 0 for that protocol itself.
    private struct DeclaringProtocol: Sendable {
        let name: String
        let adoptionDistance: Int
    }

    /// For each protocol of the table, every property declaration of its
    /// closure with the protocol nearest it that declares the property.
    private let closuresByProtocolName: [String: [Declaration: DeclaringProtocol]]

    init(protocols: [ObjCContainerSnapshot]) {
        let protocolsByName = Dictionary(grouping: protocols, by: \.name)
        var closuresByProtocolName: [String: [Declaration: DeclaringProtocol]] = [:]
        var protocolNamesBeingClosed: Set<String> = []

        /// A protocol's closure, built from its adoptions' closures; an
        /// adoption cycle contributes nothing past the protocol it returns to.
        func closure(ofProtocolNamed protocolName: String) -> [Declaration: DeclaringProtocol] {
            if let knownClosure = closuresByProtocolName[protocolName] { return knownClosure }
            guard protocolNamesBeingClosed.insert(protocolName).inserted else { return [:] }
            defer { protocolNamesBeingClosed.remove(protocolName) }

            var declaringProtocols: [Declaration: DeclaringProtocol] = [:]
            for protocolSnapshot in protocolsByName[protocolName] ?? [] {
                for member in protocolSnapshot.members {
                    guard member.kind == .instanceProperty || member.kind == .classProperty else { continue }
                    let declaration = Declaration(identityKey: member.identityKey, payloadKey: member.payloadKeyWithoutOptionality)
                    declaringProtocols[declaration] = DeclaringProtocol(name: protocolName, adoptionDistance: 0)
                }
            }
            for protocolSnapshot in protocolsByName[protocolName] ?? [] {
                for adoptedProtocolName in protocolSnapshot.members.compactMap(\.adoptedProtocolName) {
                    for (declaration, declaringProtocol) in closure(ofProtocolNamed: adoptedProtocolName) {
                        let candidate = DeclaringProtocol(name: declaringProtocol.name, adoptionDistance: declaringProtocol.adoptionDistance + 1)
                        if let nearest = declaringProtocols[declaration], nearest.adoptionDistance <= candidate.adoptionDistance { continue }
                        declaringProtocols[declaration] = candidate
                    }
                }
            }
            closuresByProtocolName[protocolName] = declaringProtocols
            return declaringProtocols
        }

        for protocolName in protocolsByName.keys {
            _ = closure(ofProtocolNamed: protocolName)
        }
        self.closuresByProtocolName = closuresByProtocolName
    }

    /// The protocol whose declaration `record` copies — the one nearest the
    /// container among those declaring it, the first adopted on a tie — or
    /// `nil` when none of `adoptedProtocolNames`, followed through their own
    /// adoptions, declares it: the record is the container's own declaration.
    /// A protocol the table does not hold contributes nothing.
    func declaringProtocolName(of record: ObjCMemberRecord, adoptedProtocolNames: [String]) -> String? {
        guard record.kind == .instanceProperty || record.kind == .classProperty else { return nil }
        let declaration = Declaration(identityKey: record.identityKey, payloadKey: record.payloadKey)
        var nearestProtocol: DeclaringProtocol?
        for adoptedProtocolName in adoptedProtocolNames {
            guard let declaringProtocol = closuresByProtocolName[adoptedProtocolName]?[declaration] else { continue }
            if let nearest = nearestProtocol, nearest.adoptionDistance <= declaringProtocol.adoptionDistance { continue }
            nearestProtocol = declaringProtocol
        }
        return nearestProtocol?.name
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
///
/// When every record of an identity is a protocol copy, the property is in
/// the container only because a protocol it adopts declares it, and the
/// selection names that protocol (`keptProtocolNameByKey`). NSView's anchors
/// read so from macOS 13: its own declarations sit in a category of the SDK
/// header, which leaves no record, and `NSAKLayoutItem`'s copies are the only
/// ones.
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
    /// For each identity key whose record taken is a protocol copy, the
    /// protocol whose declaration it copies.
    let keptProtocolNameByKey: [ObjCAPIKey: String]

    init(members: [ObjCMemberRecord], protocolPropertyDeclarations: ObjCProtocolPropertyDeclarations) {
        var memberIndicesByKey: [ObjCAPIKey: [Int]] = [:]
        memberIndicesByKey.reserveCapacity(members.count)
        for (memberIndex, member) in members.enumerated() {
            memberIndicesByKey[member.identityKey, default: []].append(memberIndex)
        }
        let adoptedProtocolNames = members.compactMap(\.adoptedProtocolName)
        func declaringProtocolName(ofMemberAt memberIndex: Int) -> String? {
            guard !adoptedProtocolNames.isEmpty else { return nil }
            return protocolPropertyDeclarations.declaringProtocolName(of: members[memberIndex], adoptedProtocolNames: adoptedProtocolNames)
        }

        var keptMemberIndexByKey: [ObjCAPIKey: Int] = [:]
        keptMemberIndexByKey.reserveCapacity(memberIndicesByKey.count)
        var reportedDroppedMemberIndicesByKey: [ObjCAPIKey: [Int]] = [:]
        var keptOccurrenceByDuplicatedKey: [ObjCAPIKey: Int] = [:]
        var keptProtocolNameByKey: [ObjCAPIKey: String] = [:]
        for (memberKey, memberIndices) in memberIndicesByKey {
            let declaringProtocolNames = memberIndices.map(declaringProtocolName(ofMemberAt:))
            let keptOccurrence = declaringProtocolNames.firstIndex { $0 == nil } ?? 0
            let keptMemberIndex = memberIndices[keptOccurrence]
            keptMemberIndexByKey[memberKey] = keptMemberIndex
            if let keptProtocolName = declaringProtocolNames[keptOccurrence] {
                keptProtocolNameByKey[memberKey] = keptProtocolName
            }
            guard memberIndices.count > 1 else { continue }
            keptOccurrenceByDuplicatedKey[memberKey] = keptOccurrence
            let keptPayloadKey = members[keptMemberIndex].payloadKey
            let reportedMemberIndices = zip(memberIndices, declaringProtocolNames).compactMap { memberIndex, protocolName in
                memberIndex != keptMemberIndex && protocolName == nil && members[memberIndex].payloadKey != keptPayloadKey
                    ? memberIndex
                    : nil
            }
            if !reportedMemberIndices.isEmpty {
                reportedDroppedMemberIndicesByKey[memberKey] = reportedMemberIndices
            }
        }

        self.members = members
        self.keptMemberIndexByKey = keptMemberIndexByKey
        self.reportedDroppedMemberIndicesByKey = reportedDroppedMemberIndicesByKey
        self.keptOccurrenceByDuplicatedKey = keptOccurrenceByDuplicatedKey
        self.keptProtocolNameByKey = keptProtocolNameByKey
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
