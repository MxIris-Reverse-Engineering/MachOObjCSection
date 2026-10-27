/// What a conformer of each protocol in one snapshot must implement: the
/// protocol's required members and, through its adoptions, those of every
/// protocol it adopts, however deep.
///
/// A snapshot keeps only a protocol's direct adoptions (the `adopts:`
/// records), so the deeper levels are found by name in the snapshot's own
/// protocol table.
struct ObjCProtocolRequirements: Sendable {
    private let protocolsByName: [String: ObjCContainerSnapshot]

    init(protocols: [ObjCContainerSnapshot]) {
        protocolsByName = Dictionary(
            protocols.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The identity keys of every required member a conformer of
    /// `protocolName` must implement, or `nil` when that protocol, or one it
    /// adopts, is not in the snapshot and the answer cannot be known.
    func requiredMemberKeys(ofProtocolNamed protocolName: String) -> Set<ObjCAPIKey>? {
        var requiredMemberKeys: Set<ObjCAPIKey> = []
        var visitedProtocolNames: Set<String> = []
        var pendingProtocolNames = [protocolName]
        while let pendingProtocolName = pendingProtocolNames.popLast() {
            guard visitedProtocolNames.insert(pendingProtocolName).inserted else { continue }
            guard let protocolSnapshot = protocolsByName[pendingProtocolName] else { return nil }
            for member in protocolSnapshot.members {
                if member.isOptionalRequirement == false {
                    requiredMemberKeys.insert(member.identityKey)
                }
                if let adoptedProtocolName = member.adoptedProtocolName {
                    pendingProtocolNames.append(adoptedProtocolName)
                }
            }
        }
        return requiredMemberKeys
    }
}
