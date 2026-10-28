import ObjCDeclarationRendering
import ObjCDiffing
import ObjCIndexing
import Semantic

// MARK: - Renderings

/// A member's rendering, and the version it was first rendered this way in.
struct ObjCEvolutionRenderedGeneration: Sendable {
    let firstVersionIndex: Int
    let rendering: SemanticString
}

/// What the merged header needs of one container from the versions that had
/// it: the facts of its first line in the newest of them, and its members'
/// renderings — the newest, and every one that differs from the version
/// before, for the two sides of a `modified` annotation.
struct ObjCEvolutionContainerRenderings: Sendable {
    /// The class or protocol name; for a category, the class it extends.
    var name = ""
    var categoryName: String?
    var superclassName: String?
    /// Set when the newest version's class is one the host supplied.
    var suppliedClassKind: ObjCSuppliedClass.Kind?
    private var generationsByMember: [ObjCAPIKey: [ObjCEvolutionRenderedGeneration]] = [:]

    /// Records `rendering` for the member `memberKey` in `versionIndex`,
    /// unless the version already rendered a member with that key — the
    /// snapshot keeps the first record of a key, and so does the rendering.
    mutating func record(
        _ rendering: SemanticString,
        for memberKey: ObjCAPIKey,
        at versionIndex: Int,
        renderedKeys: inout Set<ObjCAPIKey>
    ) {
        guard renderedKeys.insert(memberKey).inserted else { return }
        if let newestGeneration = generationsByMember[memberKey]?.last,
           newestGeneration.rendering.string == rendering.string {
            return
        }
        generationsByMember[memberKey, default: []].append(
            ObjCEvolutionRenderedGeneration(firstVersionIndex: versionIndex, rendering: rendering)
        )
    }

    /// The rendering from the newest version that had the member.
    func newestRendering(of memberKey: ObjCAPIKey) -> SemanticString? {
        generationsByMember[memberKey]?.last?.rendering
    }

    /// The member's rendering in `versionIndex`, where the member is present.
    func rendering(of memberKey: ObjCAPIKey, atVersion versionIndex: Int) -> SemanticString? {
        generationsByMember[memberKey]?.last { $0.firstVersionIndex <= versionIndex }?.rendering
    }
}

// MARK: - Merged member order

/// The lists a container renders its members in, as `objc dump` groups them.
enum ObjCEvolutionMemberGroup: Hashable, Sendable {
    case ivars
    case classProperties
    case properties
    case classMethods
    case methods
    case optionalClassProperties
    case optionalProperties
    case optionalClassMethods
    case optionalMethods
    case adoptions
    case superclass

    init(_ record: ObjCMemberRecord) {
        let isOptional = record.isOptionalRequirement == true
        switch record.kind {
        case .ivar:
            self = .ivars
        case .classProperty:
            self = isOptional ? .optionalClassProperties : .classProperties
        case .instanceProperty:
            self = isOptional ? .optionalProperties : .properties
        case .classMethod:
            self = isOptional ? .optionalClassMethods : .classMethods
        case .instanceMethod:
            self = isOptional ? .optionalMethods : .methods
        case .protocolAdoption:
            self = .adoptions
        case .superclass:
            self = .superclass
        }
    }
}

/// The members of one container across the versions, in merged order: each
/// group in the newest version's order, and a member the newest version no
/// longer has placed where it last appeared — right after the member that
/// preceded it in the newest version that still had it.
///
/// A member belongs to the group the newest version that has it puts it in,
/// so a protocol requirement that became optional is listed under
/// `@optional` only.
struct ObjCEvolutionMemberLayout {
    /// Each version's records of the container, the first record of each
    /// identity kept as the snapshot keeps it; `nil` where the container is
    /// absent.
    let recordsByVersion: [[ObjCAPIKey: ObjCMemberRecord]?]
    private let mergedKeysByGroup: [ObjCEvolutionMemberGroup: [ObjCAPIKey]]

    init(perVersion containers: [ObjCContainerSnapshot?]) {
        var recordsByVersion: [[ObjCAPIKey: ObjCMemberRecord]?] = []
        var ordersByVersion: [[ObjCEvolutionMemberGroup: [ObjCAPIKey]]] = []
        for container in containers {
            guard let container else {
                recordsByVersion.append(nil)
                ordersByVersion.append([:])
                continue
            }
            var records: [ObjCAPIKey: ObjCMemberRecord] = [:]
            var orders: [ObjCEvolutionMemberGroup: [ObjCAPIKey]] = [:]
            for record in container.members where records[record.identityKey] == nil {
                records[record.identityKey] = record
                orders[ObjCEvolutionMemberGroup(record), default: []].append(record.identityKey)
            }
            recordsByVersion.append(records)
            ordersByVersion.append(orders)
        }

        var finalGroupByKey: [ObjCAPIKey: ObjCEvolutionMemberGroup] = [:]
        for records in recordsByVersion.reversed() {
            for (key, record) in records ?? [:] where finalGroupByKey[key] == nil {
                finalGroupByKey[key] = ObjCEvolutionMemberGroup(record)
            }
        }

        var mergedKeysByGroup: [ObjCEvolutionMemberGroup: [ObjCAPIKey]] = [:]
        for orders in ordersByVersion.reversed() {
            for (group, keys) in orders {
                let keysStayingInGroup = keys.filter { finalGroupByKey[$0] == group }
                mergedKeysByGroup[group] = Self.interleaving(keysStayingInGroup, into: mergedKeysByGroup[group] ?? [])
            }
        }

        self.recordsByVersion = recordsByVersion
        self.mergedKeysByGroup = mergedKeysByGroup
    }

    func mergedKeys(of group: ObjCEvolutionMemberGroup) -> [ObjCAPIKey] {
        mergedKeysByGroup[group] ?? []
    }

    /// Whether the member is an optional protocol requirement in
    /// `versionIndex`; `nil` where it is absent or not a protocol member.
    func isOptionalRequirement(_ memberKey: ObjCAPIKey, atVersion versionIndex: Int) -> Bool? {
        guard recordsByVersion.indices.contains(versionIndex) else { return nil }
        return recordsByVersion[versionIndex]?[memberKey]?.isOptionalRequirement
    }

    /// `merged` with the keys of `versionOrder` it lacks inserted: each right
    /// after the nearest key before it in `versionOrder` that `merged` has
    /// (keys inserted on the way count), else right before the nearest one
    /// after it, else at the end. Keys `merged` already has keep their place.
    static func interleaving(_ versionOrder: [ObjCAPIKey], into merged: [ObjCAPIKey]) -> [ObjCAPIKey] {
        var result = merged
        var placedKeys = Set(merged)
        for (position, key) in versionOrder.enumerated() where !placedKeys.contains(key) {
            let insertionIndex: Int
            if let predecessor = versionOrder[..<position].last(where: placedKeys.contains),
               let predecessorIndex = result.firstIndex(of: predecessor) {
                insertionIndex = predecessorIndex + 1
            } else if let successor = versionOrder[(position + 1)...].first(where: placedKeys.contains),
                      let successorIndex = result.firstIndex(of: successor) {
                insertionIndex = successorIndex
            } else {
                insertionIndex = result.endIndex
            }
            result.insert(key, at: insertionIndex)
            placedKeys.insert(key)
        }
        return result
    }
}

// MARK: - Container lines

/// Lays out one container of the merged header line by line, exactly as the
/// declaration renderers lay out a single version's — the same first line,
/// ivar block, groups and blank lines — with the annotations of the
/// container's lineages attached:
///
/// - the container's own on its first line;
/// - each member's on the member's first line;
/// - the superclass's and each adopted protocol's on a comment line of its
///   own above the first line, since they share it.
///
/// With an availability platform, a container whose lineage one macro can
/// state gets the macro on a line above its first line, and so does a method
/// or a property before its `;`. Ivars, adoptions and the superclass get
/// none: the SDK never marks an ivar, and the other two are not declarations.
struct ObjCEvolutionContainerAssembler {
    private let versions: [ObjCAPIVersionDescriptor]
    private let availabilityPlatform: String?
    private let containerLineages: [ObjCAPIKey: ObjCContainerLineage]
    private let memberLineages: [ObjCAPIKey: [ObjCAPIKey: ObjCMemberLineage]]

    private static let superclassKey = ObjCAPIKey(rawValue: "superclass")
    private static let adoptionKeyPrefix = "adopts:"
    private static let superclassSignaturePrefix = "superclass: "

    init(evolution: ObjCAPIEvolution, availabilityPlatform: String?) {
        self.versions = evolution.versions
        self.availabilityPlatform = availabilityPlatform
        var containerLineages: [ObjCAPIKey: ObjCContainerLineage] = [:]
        var memberLineages: [ObjCAPIKey: [ObjCAPIKey: ObjCMemberLineage]] = [:]
        for containerLineage in evolution.allContainerLineages {
            containerLineages[containerLineage.key] = containerLineage
            memberLineages[containerLineage.key] = Dictionary(
                containerLineage.memberLineages.map { ($0.key, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        self.containerLineages = containerLineages
        self.memberLineages = memberLineages
    }

    func lines(
        forContainer containerKey: ObjCAPIKey,
        kind: ObjCContainerKind,
        perVersion containers: [ObjCContainerSnapshot?],
        renderings: ObjCEvolutionContainerRenderings
    ) -> [ObjCEvolutionLine] {
        let layout = ObjCEvolutionMemberLayout(perVersion: containers)
        let lineagesOfMembers = memberLineages[containerKey] ?? [:]
        let containerLineage = containerLineages[containerKey]
        let adoptionKeys = layout.mergedKeys(of: .adoptions)

        var lines: [ObjCEvolutionLine] = []
        if let suppliedClassKind = renderings.suppliedClassKind {
            lines.append(Self.commentLine("// " + suppliedClassKind.declarationComment))
        }
        if let superclassLineage = lineagesOfMembers[Self.superclassKey],
           let annotation = superclassAnnotation(superclassLineage) {
            lines.append(Self.commentLine(ObjCEvolutionMarking.annotationText(for: annotation, versions: versions)))
        }
        for adoptionKey in adoptionKeys {
            guard let adoptionLineage = lineagesOfMembers[adoptionKey],
                  let annotation = annotation(of: adoptionLineage, subject: "adopts <\(Self.protocolName(ofAdoptionKey: adoptionKey))>", renderings: renderings, layout: layout)
            else { continue }
            lines.append(Self.commentLine(ObjCEvolutionMarking.annotationText(for: annotation, versions: versions)))
        }
        if let availabilityPlatform, let containerLineage,
           let macro = ObjCEvolutionMarking.availabilityMacro(presence: containerLineage.presence, versions: versions, platform: availabilityPlatform) {
            lines.append(Self.keywordLine(macro))
        }

        let protocolNames = adoptionKeys.map(Self.protocolName(ofAdoptionKey:))
        var firstLine: SemanticString = switch kind {
        case .class:
            ObjCDeclarationHeader.classInterface(name: renderings.name, superclassName: renderings.superclassName, protocolNames: protocolNames)
        case .protocol:
            ObjCDeclarationHeader.protocolDeclaration(name: renderings.name, protocolNames: protocolNames)
        case .category:
            ObjCDeclarationHeader.categoryInterface(className: renderings.name, categoryName: renderings.categoryName ?? "", protocolNames: protocolNames)
        }
        let ivarKeys = layout.mergedKeys(of: .ivars)
        if !ivarKeys.isEmpty {
            firstLine.append(" {", type: .standard)
        }
        let containerAnnotation = containerLineage.flatMap { lineage in
            lineage.events.isEmpty ? nil : ObjCEvolutionAnnotation(subject: nil, presence: lineage.presence, events: lineage.events.map(Self.presenceEvent))
        }
        lines.append(ObjCEvolutionLine(content: firstLine, annotation: containerAnnotation))

        func linesOfMembers(_ memberKeys: [ObjCAPIKey], indentLevel: Int, writesAvailability: Bool) -> [ObjCEvolutionLine] {
            memberKeys.flatMap { memberKey in
                self.memberLines(
                    memberKey,
                    lineage: lineagesOfMembers[memberKey],
                    renderings: renderings,
                    layout: layout,
                    indentLevel: indentLevel,
                    writesAvailability: writesAvailability
                )
            }
        }

        /// Non-empty groups, each after an empty line, and one more empty
        /// line after the last: what a block list of each group writes.
        func groupedLines(_ groups: [ObjCEvolutionMemberGroup]) -> [ObjCEvolutionLine] {
            let nonEmptyGroups = groups.map(layout.mergedKeys(of:)).filter { !$0.isEmpty }
            guard !nonEmptyGroups.isEmpty else { return [] }
            var groupLines: [ObjCEvolutionLine] = []
            for memberKeys in nonEmptyGroups {
                groupLines.append(.blank)
                groupLines += linesOfMembers(memberKeys, indentLevel: 0, writesAvailability: true)
            }
            groupLines.append(.blank)
            return groupLines
        }

        switch kind {
        case .class:
            if !ivarKeys.isEmpty {
                lines += linesOfMembers(ivarKeys, indentLevel: 1, writesAvailability: false)
                lines.append(ObjCEvolutionLine(content: SemanticString(stringLiteral: "}")))
            }
            lines += groupedLines([.classProperties, .properties, .classMethods, .methods])
        case .category:
            lines += groupedLines([.classProperties, .properties, .classMethods, .methods])
        case .protocol:
            let sections: [(keyword: String, groups: [ObjCEvolutionMemberGroup])] = [
                ("@required", [.classProperties, .properties, .classMethods, .methods]),
                ("@optional", [.optionalClassProperties, .optionalProperties, .optionalClassMethods, .optionalMethods]),
            ]
            let nonEmptySections = sections.filter { section in
                section.groups.contains { !layout.mergedKeys(of: $0).isEmpty }
            }
            if !nonEmptySections.isEmpty {
                for section in nonEmptySections {
                    lines.append(.blank)
                    lines.append(Self.keywordLine(section.keyword))
                    for memberKeys in section.groups.map(layout.mergedKeys(of:)) where !memberKeys.isEmpty {
                        lines.append(.blank)
                        lines += linesOfMembers(memberKeys, indentLevel: 0, writesAvailability: true)
                    }
                }
                lines.append(.blank)
            }
        }
        lines.append(Self.keywordLine("@end"))
        return lines
    }

    // MARK: - Members

    private func memberLines(
        _ memberKey: ObjCAPIKey,
        lineage: ObjCMemberLineage?,
        renderings: ObjCEvolutionContainerRenderings,
        layout: ObjCEvolutionMemberLayout,
        indentLevel: Int,
        writesAvailability: Bool
    ) -> [ObjCEvolutionLine] {
        guard var declaration = renderings.newestRendering(of: memberKey) else { return [] }
        if writesAvailability, let availabilityPlatform, let lineage {
            let macro = ObjCEvolutionMarking.availabilityMacro(presence: lineage.presence, versions: versions, platform: availabilityPlatform)
            declaration = ObjCEvolutionMarking.declaration(declaration, withAvailabilityMacro: macro)
        }
        let annotation = lineage.flatMap { annotation(of: $0, subject: nil, renderings: renderings, layout: layout) }
        return ObjCEvolutionMarking.lines(of: declaration).enumerated().map { lineIndex, line in
            ObjCEvolutionLine(
                content: line,
                indentLevel: lineIndex == 0 ? indentLevel : 0,
                annotation: lineIndex == 0 ? annotation : nil
            )
        }
    }

    /// A member's annotation. The two sides of a `modified` event are the
    /// member as each version rendered it; when those read the same and the
    /// member is a protocol requirement that changed sides, the sides are
    /// `@required` and `@optional`.
    private func annotation(
        of lineage: ObjCMemberLineage,
        subject: String?,
        renderings: ObjCEvolutionContainerRenderings,
        layout: ObjCEvolutionMemberLayout
    ) -> ObjCEvolutionAnnotation? {
        guard !lineage.events.isEmpty else { return nil }
        let events = lineage.events.map { event -> ObjCEvolutionAnnotation.Event in
            guard event.status == .modified else { return Self.presenceEvent(event) }
            let previousVersionIndex = event.versionIndex - 1
            var oldSide = renderings.rendering(of: lineage.key, atVersion: previousVersionIndex).map(ObjCEvolutionMarking.singleLine)
            var newSide = renderings.rendering(of: lineage.key, atVersion: event.versionIndex).map(ObjCEvolutionMarking.singleLine)
            if oldSide == newSide,
               let wasOptional = layout.isOptionalRequirement(lineage.key, atVersion: previousVersionIndex),
               let isOptional = layout.isOptionalRequirement(lineage.key, atVersion: event.versionIndex),
               wasOptional != isOptional {
                oldSide = Self.requirementKeyword(isOptional: wasOptional)
                newSide = Self.requirementKeyword(isOptional: isOptional)
            }
            return ObjCEvolutionAnnotation.Event(versionIndex: event.versionIndex, change: .modified(old: oldSide, new: newSide))
        }
        return ObjCEvolutionAnnotation(subject: subject, presence: lineage.presence, events: events)
    }

    /// The superclass's annotation: each change names the old and the new
    /// superclass, as the lineage's signatures do.
    private func superclassAnnotation(_ lineage: ObjCMemberLineage) -> ObjCEvolutionAnnotation? {
        guard !lineage.events.isEmpty else { return nil }
        let events = lineage.events.map { event -> ObjCEvolutionAnnotation.Event in
            guard event.status == .modified else { return Self.presenceEvent(event) }
            return ObjCEvolutionAnnotation.Event(
                versionIndex: event.versionIndex,
                change: .modified(
                    old: event.oldSignature.map(Self.superclassName(fromSignature:)),
                    new: event.newSignature.map(Self.superclassName(fromSignature:))
                )
            )
        }
        return ObjCEvolutionAnnotation(subject: "superclass", presence: lineage.presence, events: events)
    }

    /// An `added` or `removed` event, as is.
    private static func presenceEvent(_ event: ObjCLineageEvent) -> ObjCEvolutionAnnotation.Event {
        switch event.status {
        case .added:
            ObjCEvolutionAnnotation.Event(versionIndex: event.versionIndex, change: .added)
        case .removed:
            ObjCEvolutionAnnotation.Event(versionIndex: event.versionIndex, change: .removed)
        case .modified:
            ObjCEvolutionAnnotation.Event(versionIndex: event.versionIndex, change: .modified(old: nil, new: nil))
        }
    }

    // MARK: - Text

    private static func requirementKeyword(isOptional: Bool) -> String {
        isOptional ? "@optional" : "@required"
    }

    /// `adopts:NSCoding` → `NSCoding`. The key is the snapshot's persisted
    /// format, so it is safe to read back.
    private static func protocolName(ofAdoptionKey key: ObjCAPIKey) -> String {
        String(key.rawValue.dropFirst(adoptionKeyPrefix.count))
    }

    /// `superclass: NSResponder` → `NSResponder`; a root class reads `(root)`.
    private static func superclassName(fromSignature signature: String) -> String {
        signature.hasPrefix(superclassSignaturePrefix) ? String(signature.dropFirst(superclassSignaturePrefix.count)) : signature
    }

    private static func commentLine(_ text: String) -> ObjCEvolutionLine {
        var content = SemanticString()
        content.append(text, type: .comment)
        return ObjCEvolutionLine(content: content)
    }

    private static func keywordLine(_ text: String) -> ObjCEvolutionLine {
        var content = SemanticString()
        content.append(text, type: .keyword)
        return ObjCEvolutionLine(content: content)
    }
}
