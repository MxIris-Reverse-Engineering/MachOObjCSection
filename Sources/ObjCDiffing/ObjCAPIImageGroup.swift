/// One image of a version's image group: its snapshot, and the name the
/// reports call the image by.
///
/// The caller names the image (`AppKit`); nothing derives the name from the
/// snapshot's provenance, whose `binaryPath` for a dyld-shared-cache image is
/// the cache path with the image name appended.
public struct ObjCAPIImageSnapshot: Sendable, Codable, Equatable {
    public let imageName: String
    public let snapshot: ObjCAPISnapshot

    public init(imageName: String, snapshot: ObjCAPISnapshot) {
        self.imageName = imageName
        self.snapshot = snapshot
    }
}

/// One version's image group merged into the snapshot the evolution compares,
/// with the images each class, category and member came from.
///
/// - Classes: every image's, in group order. A class two images hold keeps
///   both containers, so first-wins keying compares the first image's copy
///   and the key collision names the other.
/// - Categories: one container per unique name, with the members of every
///   image's category of that name in group order — the runtime attaches them
///   all to the same class. A selector two images both declare collides as a
///   member.
/// - Protocols: every image referencing a protocol carries its own copy of
///   the `protocol_t` — the dyld shared cache builder points references at a
///   canonical copy but leaves each image's `__objc_protolist` on its own. A
///   copy equal to one already kept is dropped silently; a differing one is
///   kept, so it collides and the first image's copy is compared. No image
///   owns a protocol, so a protocol has no images and never moves.
package struct ObjCAPIImageGroupMerge: Sendable {
    /// The group's image names, in group order, each once.
    package let imageNames: [String]
    package let snapshot: ObjCAPISnapshot
    /// The merged snapshot's identity-key collisions, each dropped record's
    /// image named.
    package let keyCollisions: [ObjCAPIKeyCollision]
    /// The images holding each class and category, in group order.
    private let containerImageNames: [ObjCAPIKey: [String]]
    /// For each class or category several images hold: the images holding
    /// each of its members, in group order. The members of a container one
    /// image holds are in that image.
    private let memberImageNamesByContainer: [ObjCAPIKey: [ObjCAPIKey: [String]]]

    package init(_ imageGroup: [ObjCAPIImageSnapshot]) {
        var imageNames: [String] = []
        var classes: [ObjCContainerSnapshot] = []
        var classImageNames: [String] = []
        var protocols: [ObjCContainerSnapshot] = []
        var protocolImageNames: [String] = []
        var keptProtocolCopiesByKey: [ObjCAPIKey: [ObjCContainerSnapshot]] = [:]
        var categoryKeys: [ObjCAPIKey] = []
        var firstCategoryCopiesByKey: [ObjCAPIKey: ObjCContainerSnapshot] = [:]
        var categoryMembersByKey: [ObjCAPIKey: [(record: ObjCMemberRecord, imageName: String)]] = [:]
        var containerImageNames: [ObjCAPIKey: [String]] = [:]
        var copiesByContainer: [ObjCAPIKey: [(imageName: String, members: [ObjCMemberRecord])]] = [:]

        for image in imageGroup {
            imageNames.appendIfAbsent(image.imageName)
            for container in image.snapshot.classes {
                classes.append(container)
                classImageNames.append(image.imageName)
                containerImageNames[container.key, default: []].appendIfAbsent(image.imageName)
                copiesByContainer[container.key, default: []].append((image.imageName, container.members))
            }
            for container in image.snapshot.protocols {
                guard keptProtocolCopiesByKey[container.key]?.contains(container) != true else { continue }
                keptProtocolCopiesByKey[container.key, default: []].append(container)
                protocols.append(container)
                protocolImageNames.append(image.imageName)
            }
            for container in image.snapshot.categories {
                if firstCategoryCopiesByKey[container.key] == nil {
                    firstCategoryCopiesByKey[container.key] = container
                    categoryKeys.append(container.key)
                }
                categoryMembersByKey[container.key, default: []].append(contentsOf: container.members.map { ($0, image.imageName) })
                containerImageNames[container.key, default: []].appendIfAbsent(image.imageName)
                copiesByContainer[container.key, default: []].append((image.imageName, container.members))
            }
        }

        var categories: [ObjCContainerSnapshot] = []
        var categoryMemberImageNames: [[String]] = []
        for categoryKey in categoryKeys {
            guard let firstCopy = firstCategoryCopiesByKey[categoryKey] else { continue }
            let members = categoryMembersByKey[categoryKey] ?? []
            categories.append(ObjCContainerSnapshot(
                key: categoryKey,
                name: firstCopy.name,
                kind: firstCopy.kind,
                targetClassName: firstCopy.targetClassName,
                members: members.map(\.record)
            ))
            categoryMemberImageNames.append(members.map(\.imageName))
        }

        var memberImageNamesByContainer: [ObjCAPIKey: [ObjCAPIKey: [String]]] = [:]
        for (containerKey, copies) in copiesByContainer where (containerImageNames[containerKey]?.count ?? 0) > 1 {
            var memberImageNames: [ObjCAPIKey: [String]] = [:]
            for copy in copies {
                for record in copy.members {
                    memberImageNames[record.identityKey, default: []].appendIfAbsent(copy.imageName)
                }
            }
            memberImageNamesByContainer[containerKey] = memberImageNames
        }

        let snapshot = ObjCAPISnapshot(classes: classes, protocols: protocols, categories: categories)
        self.imageNames = imageNames
        self.snapshot = snapshot
        self.keyCollisions = snapshot.keyCollisions(
            containerImageName: { kind, containerIndex in
                switch kind {
                case .class: classImageNames[containerIndex]
                case .protocol: protocolImageNames[containerIndex]
                // A category is one container per key, so it never collides
                // as a container; its first image stands for it.
                case .category: categoryMemberImageNames[containerIndex].first ?? ""
                }
            },
            memberImageName: { kind, containerIndex, memberIndex in
                switch kind {
                case .class: classImageNames[containerIndex]
                case .protocol: protocolImageNames[containerIndex]
                case .category: categoryMemberImageNames[containerIndex][memberIndex]
                }
            }
        )
        self.containerImageNames = containerImageNames
        self.memberImageNamesByContainer = memberImageNamesByContainer
    }

    /// The images holding the class or category, in group order; `nil` for a
    /// protocol and for a container the group does not hold.
    func imageNames(ofContainer containerKey: ObjCAPIKey) -> [String]? {
        containerImageNames[containerKey]
    }

    /// The images holding a member of the class or category, in group order;
    /// `nil` where `imageNames(ofContainer:)` is.
    func imageNames(ofMember memberKey: ObjCAPIKey, inContainer containerKey: ObjCAPIKey) -> [String]? {
        memberImageNamesByContainer[containerKey]?[memberKey] ?? containerImageNames[containerKey]
    }
}

extension Array where Element: Equatable {
    fileprivate mutating func appendIfAbsent(_ element: Element) {
        if !contains(element) {
            append(element)
        }
    }
}
