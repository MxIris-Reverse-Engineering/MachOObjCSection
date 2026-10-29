import ObjCDeclarationRendering
import ObjCDiffing
import ObjCDump
import ObjCIndexing
import ObjCMetadataSource
import Semantic

/// The merged Objective-C header of N ≥ 2 versions of one binary, and the
/// evolution its annotations state. Built by ``ObjCEvolutionInterfaceBuilder``.
public struct ObjCEvolutionInterface: Sendable {
    /// The lineages the annotations state: what `ObjCAPIEvolutionBuilder`
    /// computes over the same snapshots, so what `objc evolution` reports for
    /// these versions. `hasBreakingChange` answers a breaking-change gate.
    public let evolution: ObjCAPIEvolution

    /// The merged header. Comment lines first name the version axis and what
    /// each position of a presence bitmap stands for, and for image groups
    /// which versions hold each image. Then come the declarations as
    /// `objc dump` writes them — classes, protocols, categories, each sorted
    /// by name — where a declaration that changed carries
    /// `// [●○●] added in 13.0`-style comments, and a declaration removed
    /// along the axis stays where it last appeared. C struct and union
    /// definitions follow, each from the newest version that has it, without
    /// annotations.
    public let interface: SemanticString
}

/// One image of a version, for
/// ``ObjCEvolutionInterfaceBuilder/addVersion(images:version:)``.
public struct ObjCEvolutionInterfaceImage<MachO: ObjCMetadataSource> {
    /// The name the annotations call the image by (`AppKit`).
    public let imageName: String
    /// The image's indexer, already prepared.
    public let indexer: ObjCInterfaceIndexer<MachO>
    /// The Mach-O the indexer read.
    public let machO: MachO

    public init(imageName: String, indexer: ObjCInterfaceIndexer<MachO>, machO: MachO) {
        self.imageName = imageName
        self.indexer = indexer
        self.machO = machO
    }
}

/// Merges the Objective-C headers of N ≥ 2 versions of one binary into one,
/// and annotates every declaration that changed along the way: the
/// `objc evolution` lineages, laid over the header `objc dump` writes.
///
/// ```swift
/// var builder = ObjCEvolutionInterfaceBuilder()
/// for (label, image) in imagesOldestFirst {
///     let indexer = ObjCInterfaceIndexer(machO: image, imagePath: image.imagePath)
///     try await indexer.prepare()
///     builder.addVersion(indexer: indexer, machO: image, version: ObjCAPIVersionDescriptor(label: label))
/// }
/// let merged = try builder.build(availabilityPlatform: "macos")
/// ```
///
/// The order of the `addVersion` calls is the version axis, oldest first.
/// Each call renders every declaration of its version and takes the snapshot
/// `ObjCAPISnapshotBuilder` takes; the builder keeps no reference to the
/// indexer or the Mach-O afterwards, so a host can index one version at a
/// time and let each go before loading the next. What it keeps is every
/// version's snapshot, the newest rendering of each declaration, and each
/// rendering that differs from the one before it.
///
/// A version can also be an image group, for a binary whose declarations
/// move to other images along the axis — AppKit's into UIFoundation and
/// CollectionViewCore, say. ``addVersion(images:version:)`` takes the
/// version's images, and the evolution is
/// `ObjCAPIEvolutionBuilder.evolution(ofImageGroups:versions:)`'s: a
/// declaration that moved reads `// [●●●] moved in 14.0: AppKit →
/// UIFoundation`, not removed from one image and added to the other. A
/// builder takes either every version as one image or every version as an
/// image group.
///
/// Every annotation states one lineage of the evolution `build` computes from
/// those snapshots: a container's own on its `@interface` or `@protocol`
/// line, a member's on the member, and the superclass's and each adopted
/// protocol's on a comment line above the `@interface`. A declaration with no
/// annotation was present on the whole axis and never changed. The two sides
/// of a `modified` annotation are the declaration as each version renders
/// it.
///
/// Declarations render with `ObjCGenerationOptions.default` — no member
/// stripped, no comment added — since a stripped member would have no line to
/// carry its annotation, and addresses and offsets differ in every version.
/// Given the same image twice, the declarations read exactly as `objc dump`
/// writes them.
public struct ObjCEvolutionInterfaceBuilder: Sendable {
    /// One version's snapshot as the evolution takes it.
    private enum VersionSnapshot: Sendable {
        case singleImage(ObjCAPISnapshot)
        case imageGroup(ObjCAPIImageGroupMerge)

        /// The snapshot the evolution compares: an image group's merged one.
        var comparedSnapshot: ObjCAPISnapshot {
            switch self {
            case .singleImage(let snapshot): snapshot
            case .imageGroup(let imageGroup): imageGroup.snapshot
            }
        }
    }

    /// What one version has rendered so far, so that each image of its group
    /// renders only what the evolution takes from it: a class or protocol no
    /// earlier image holds, of each member the record the comparison takes,
    /// a C struct or union no earlier image defines.
    private struct VersionRenderingState {
        /// Which record of each identity a container holds more than once the
        /// comparison takes, counted across the group's images in group order
        /// (`ObjCAPISnapshot.keptMemberOccurrences()`).
        let keptMemberOccurrences: [ObjCAPIKey: [ObjCAPIKey: Int]]
        var renderedContainerKeys: Set<ObjCAPIKey> = []
        /// How many records of each identity each container has met so far.
        var memberOccurrenceCountsByContainer: [ObjCAPIKey: [ObjCAPIKey: Int]] = [:]
        var definedStructNames: Set<String> = []
        var definedUnionNames: Set<String> = []

        init(keptMemberOccurrences: [ObjCAPIKey: [ObjCAPIKey: Int]]) {
            self.keptMemberOccurrences = keptMemberOccurrences
        }
    }

    private let cTypeReplacements: [ObjCPrimitiveTypePattern: String]
    private var versions: [ObjCAPIVersionDescriptor] = []
    private var versionSnapshots: [VersionSnapshot] = []
    /// Each version's `VersionRenderingState.keptMemberOccurrences`, which the
    /// member layout needs too.
    private var keptMemberOccurrencesByVersion: [[ObjCAPIKey: [ObjCAPIKey: Int]]] = []
    private var containerRenderings: [ObjCAPIKey: ObjCEvolutionContainerRenderings] = [:]
    private var structDefinitions: [String: SemanticString] = [:]
    private var unionDefinitions: [String: SemanticString] = [:]

    /// - Parameter cTypeReplacements: Other spellings for C primitive types
    ///   (`double` → `CGFloat`), applied to every version as `objc dump`
    ///   applies them.
    public init(cTypeReplacements: [ObjCPrimitiveTypePattern: String] = [:]) {
        self.cTypeReplacements = cTypeReplacements
    }

    /// Renders the next version on the axis.
    ///
    /// - Parameters:
    ///   - indexer: The version's indexer, already prepared. A host that
    ///     supplies classes the image keeps no class object for
    ///     (``ObjCIndexing/ObjCSuppliedClass``) passes them when it creates
    ///     the indexer, as it does for a snapshot.
    ///   - machO: The Mach-O the indexer read.
    ///   - version: The version's place on the axis. Its label names the
    ///     version in the annotations and availability macros.
    public mutating func addVersion<MachO: ObjCMetadataSource>(
        indexer: ObjCInterfaceIndexer<MachO>,
        machO: MachO,
        version: ObjCAPIVersionDescriptor
    ) {
        let snapshot = Self.snapshotForComparison(of: indexer)
        var renderingState = VersionRenderingState(keptMemberOccurrences: snapshot.keptMemberOccurrences())
        render(indexer: indexer, machO: machO, snapshot: snapshot, atVersion: versions.count, state: &renderingState)
        keptMemberOccurrencesByVersion.append(renderingState.keptMemberOccurrences)
        versionSnapshots.append(.singleImage(snapshot))
        versions.append(version)
    }

    /// Renders the next version on the axis from the images of its image
    /// group, which the evolution tracks as one API surface.
    ///
    /// - Parameters:
    ///   - images: The version's images, each indexer already prepared, in
    ///     group order with the primary image first. Only the images present
    ///     in the version: an image can join the group partway along the axis,
    ///     and an empty group is a version holding nothing.
    ///   - version: The version's place on the axis. Its label names the
    ///     version in the annotations and availability macros; the evolution
    ///     sets its `imageNames` from `images`.
    ///
    /// The images render as the evolution merges them: a class or protocol
    /// from the first image holding it, a category member from the image
    /// whose declaration the comparison takes, a C struct or union from the
    /// first image defining it. The builder keeps no reference to any of the
    /// indexers or Mach-Os once this returns.
    public mutating func addVersion<MachO: ObjCMetadataSource>(
        images: [ObjCEvolutionInterfaceImage<MachO>],
        version: ObjCAPIVersionDescriptor
    ) {
        // Which record of a category member the comparison takes rests on the
        // whole group, so every image's snapshot comes before any rendering.
        let imageSnapshots = images.map { image in
            ObjCAPIImageSnapshot(imageName: image.imageName, snapshot: Self.snapshotForComparison(of: image.indexer))
        }
        let imageGroup = ObjCAPIImageGroupMerge(imageSnapshots)
        var renderingState = VersionRenderingState(keptMemberOccurrences: imageGroup.snapshot.keptMemberOccurrences())
        for (image, imageSnapshot) in zip(images, imageSnapshots) {
            render(indexer: image.indexer, machO: image.machO, snapshot: imageSnapshot.snapshot, atVersion: versions.count, state: &renderingState)
        }
        keptMemberOccurrencesByVersion.append(renderingState.keptMemberOccurrences)
        versionSnapshots.append(.imageGroup(imageGroup))
        versions.append(version)
    }

    /// The snapshot of one image, as `ObjCAPISnapshotBuilder` takes it.
    private static func snapshotForComparison<MachO: ObjCMetadataSource>(of indexer: ObjCInterfaceIndexer<MachO>) -> ObjCAPISnapshot {
        ObjCAPIDiffer().snapshot(of: ObjCAPISnapshotBuilder(indexer: indexer).module())
    }

    /// Computes the evolution of the versions added so far and renders the
    /// merged header.
    ///
    /// - Parameter availabilityPlatform: The platform to write availability
    ///   macros for, as the SDK macros spell it (`macos`, `ios`, …); `nil`
    ///   writes none. A declaration gets `API_AVAILABLE` when it appears
    ///   along the axis and stays, and `API_OBSOLETED` when it appears and is
    ///   later removed. Lifecycles one macro cannot state — present from the
    ///   start of the axis, removed and added back, only modified — and
    ///   versions whose labels are not dotted numbers get none.
    /// - Throws: `ObjCAPIEvolutionError.fewerThanTwoVersions` when fewer than
    ///   two versions were added, and
    ///   ``ObjCEvolutionInterfaceError/singleImageVersionsMixedWithImageGroups``
    ///   when some were added as one image and others as image groups.
    public func build(availabilityPlatform: String? = nil) throws -> ObjCEvolutionInterface {
        let evolution = try trackedEvolution()
        let assembler = ObjCEvolutionContainerAssembler(evolution: evolution, availabilityPlatform: availabilityPlatform)
        let comparedSnapshots = versionSnapshots.map(\.comparedSnapshot)

        var blocks: [[ObjCEvolutionLine]] = []
        let containerBuckets: [(kind: ObjCContainerKind, perVersion: [[ObjCContainerSnapshot]])] = [
            (.class, comparedSnapshots.map(\.classes)),
            (.protocol, comparedSnapshots.map(\.protocols)),
            (.category, comparedSnapshots.map(\.categories)),
        ]
        for bucket in containerBuckets {
            let keyedPerVersion = bucket.perVersion.map(Self.keyedFirstWins)
            var containerKeys: Set<ObjCAPIKey> = []
            for keyedContainers in keyedPerVersion {
                containerKeys.formUnion(keyedContainers.keys)
            }
            for containerKey in containerKeys.sorted() {
                guard let renderings = containerRenderings[containerKey] else { continue }
                blocks.append(assembler.lines(
                    forContainer: containerKey,
                    kind: bucket.kind,
                    perVersion: keyedPerVersion.map { $0[containerKey] },
                    keptOccurrencesByVersion: keptMemberOccurrencesByVersion.map { $0[containerKey] ?? [:] },
                    renderings: renderings
                ))
            }
        }
        blocks += cDefinitionBlocks()

        let interface = ObjCEvolutionMarking.renderInterface(
            blocks: blocks,
            evolution: evolution,
            availabilityPlatform: availabilityPlatform
        )
        return ObjCEvolutionInterface(evolution: evolution, interface: interface)
    }

    /// The evolution of the versions added so far, of image groups when they
    /// were added as image groups.
    private func trackedEvolution() throws -> ObjCAPIEvolution {
        var singleImageSnapshots: [ObjCAPISnapshot] = []
        var imageGroups: [ObjCAPIImageGroupMerge] = []
        for versionSnapshot in versionSnapshots {
            switch versionSnapshot {
            case .singleImage(let snapshot): singleImageSnapshots.append(snapshot)
            case .imageGroup(let imageGroup): imageGroups.append(imageGroup)
            }
        }
        if imageGroups.isEmpty {
            return try ObjCAPIEvolutionBuilder().evolution(of: singleImageSnapshots, versions: versions)
        }
        guard singleImageSnapshots.isEmpty else {
            throw ObjCEvolutionInterfaceError.singleImageVersionsMixedWithImageGroups
        }
        return try ObjCAPIEvolutionBuilder().evolution(ofImageGroupMerges: imageGroups, versions: versions)
    }

    // MARK: - Rendering

    /// Renders what `indexer` adds to the version at `versionIndex` beyond
    /// what `state` says earlier images of its group rendered. `snapshot` is
    /// the image's snapshot, as ``snapshotForComparison(of:)`` takes it.
    private mutating func render<MachO: ObjCMetadataSource>(
        indexer: ObjCInterfaceIndexer<MachO>,
        machO: MachO,
        snapshot: ObjCAPISnapshot,
        atVersion versionIndex: Int,
        state: inout VersionRenderingState
    ) {
        let module = ObjCAPISnapshotBuilder(indexer: indexer).module()
        let context = ObjCInterfaceBuilder<MachO>.makeContext(
            indexer: indexer,
            machO: machO,
            options: .default,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetCommentBuilder: nil
        )

        // The snapshot projects the module's containers one for one, in
        // order, so each pair is one container and its identity key.
        for (classInfo, container) in zip(module.classes, snapshot.classes) {
            // A class an earlier image holds too is compared as that image's.
            guard state.renderedContainerKeys.insert(container.key).inserted else { continue }
            var renderings = containerRenderings[container.key] ?? ObjCEvolutionContainerRenderings()
            renderings.name = classInfo.name
            renderings.superclassName = classInfo.superClassName
            renderings.suppliedClassKind = indexer.classGroup(forName: classInfo.name) == nil
                ? indexer.suppliedClassGroup(forName: classInfo.name)?.suppliedClass.kind
                : nil
            Self.recordMembers(
                ivars: classInfo.ivars,
                properties: classInfo.classProperties + classInfo.properties,
                methods: classInfo.classMethods + classInfo.methods,
                into: &renderings,
                at: versionIndex,
                keptOccurrences: state.keptMemberOccurrences[container.key] ?? [:],
                occurrenceCounts: &state.memberOccurrenceCountsByContainer[container.key, default: [:]],
                context: context
            )
            containerRenderings[container.key] = renderings
        }
        for (protocolInfo, container) in zip(module.protocols, snapshot.protocols) {
            // Every image referencing a protocol carries a copy of it; the
            // first image's is the one compared.
            guard state.renderedContainerKeys.insert(container.key).inserted else { continue }
            var renderings = containerRenderings[container.key] ?? ObjCEvolutionContainerRenderings()
            renderings.name = protocolInfo.name
            // Required before optional, as the snapshot lists them, so the
            // records of an identity are counted in the snapshot's order.
            Self.recordMembers(
                properties: protocolInfo.classProperties + protocolInfo.properties
                    + protocolInfo.optionalClassProperties + protocolInfo.optionalProperties,
                methods: protocolInfo.classMethods + protocolInfo.methods
                    + protocolInfo.optionalClassMethods + protocolInfo.optionalMethods,
                into: &renderings,
                at: versionIndex,
                keptOccurrences: state.keptMemberOccurrences[container.key] ?? [:],
                occurrenceCounts: &state.memberOccurrenceCountsByContainer[container.key, default: [:]],
                context: context
            )
            containerRenderings[container.key] = renderings
        }
        for (categoryInfo, container) in zip(module.categories, snapshot.categories) {
            // The categories of one name in several images are one category,
            // whose members are counted across the images in group order.
            var renderings = containerRenderings[container.key] ?? ObjCEvolutionContainerRenderings()
            if state.renderedContainerKeys.insert(container.key).inserted {
                renderings.name = categoryInfo.className
                renderings.categoryName = categoryInfo.name
            }
            Self.recordMembers(
                properties: categoryInfo.classProperties + categoryInfo.properties,
                methods: categoryInfo.classMethods + categoryInfo.methods,
                into: &renderings,
                at: versionIndex,
                keptOccurrences: state.keptMemberOccurrences[container.key] ?? [:],
                occurrenceCounts: &state.memberOccurrenceCountsByContainer[container.key, default: [:]],
                context: context
            )
            containerRenderings[container.key] = renderings
        }

        for structName in indexer.structNames where !state.definedStructNames.contains(structName) {
            if let definition = indexer.structSemanticString(forName: structName, context: context) {
                structDefinitions[structName] = definition
                state.definedStructNames.insert(structName)
            }
        }
        for unionName in indexer.unionNames where !state.definedUnionNames.contains(unionName) {
            if let definition = indexer.unionSemanticString(forName: unionName, context: context) {
                unionDefinitions[unionName] = definition
                state.definedUnionNames.insert(unionName)
            }
        }
    }

    /// Records the renderings of a container's members in `versionIndex`: of
    /// each identity, only the record the comparison takes. `occurrenceCounts`
    /// counts the records of each identity met so far in the version, earlier
    /// images of its group included; the record taken is the one whose count
    /// `keptOccurrences` names, the first where it names none.
    private static func recordMembers<MachO: ObjCMetadataSource>(
        ivars: [ObjCIvarInfo] = [],
        properties: [ObjCPropertyInfo],
        methods: [ObjCMethodInfo],
        into renderings: inout ObjCEvolutionContainerRenderings,
        at versionIndex: Int,
        keptOccurrences: [ObjCAPIKey: Int],
        occurrenceCounts: inout [ObjCAPIKey: Int],
        context: ObjCRenderingContext<MachO>
    ) {
        func isKept(_ memberKey: ObjCAPIKey) -> Bool {
            let occurrence = occurrenceCounts[memberKey, default: 0]
            occurrenceCounts[memberKey] = occurrence + 1
            return occurrence == keptOccurrences[memberKey, default: 0]
        }
        for ivarInfo in ivars {
            let memberKey = ObjCMemberRecord.identityKey(of: ivarInfo)
            guard isKept(memberKey) else { continue }
            renderings.record(ivarInfo.semanticString(using: context), for: memberKey, at: versionIndex)
        }
        for propertyInfo in properties {
            let memberKey = ObjCMemberRecord.identityKey(of: propertyInfo)
            guard isKept(memberKey) else { continue }
            renderings.record(propertyInfo.semanticString(using: context), for: memberKey, at: versionIndex)
        }
        for methodInfo in methods {
            let memberKey = ObjCMemberRecord.identityKey(of: methodInfo)
            guard isKept(memberKey) else { continue }
            renderings.record(methodInfo.semanticString(using: context), for: memberKey, at: versionIndex)
        }
    }

    /// The C struct and union definitions after a comment saying they are
    /// not tracked, each from the newest version that has it, sorted by name
    /// as `objc dump` sorts them.
    private func cDefinitionBlocks() -> [[ObjCEvolutionLine]] {
        let definitions = structDefinitions.sorted { $0.key < $1.key }.map(\.value)
            + unionDefinitions.sorted { $0.key < $1.key }.map(\.value)
        guard !definitions.isEmpty else { return [] }
        var comment = SemanticString()
        comment.append(Self.cDefinitionsComment, type: .comment)
        let definitionBlocks = definitions.map { definition in
            ObjCEvolutionMarking.lines(of: definition).map { ObjCEvolutionLine(content: $0) }
        }
        return [[ObjCEvolutionLine(content: comment)]] + definitionBlocks
    }

    static let cDefinitionsComment = "// C structs and unions, each as the newest version that has it defines it. They are not tracked across versions."

    /// One version's containers by key, the first of a duplicated key kept,
    /// as the evolution keeps it.
    private static func keyedFirstWins(_ containers: [ObjCContainerSnapshot]) -> [ObjCAPIKey: ObjCContainerSnapshot] {
        var keyedContainers: [ObjCAPIKey: ObjCContainerSnapshot] = [:]
        for container in containers where keyedContainers[container.key] == nil {
            keyedContainers[container.key] = container
        }
        return keyedContainers
    }
}

/// Why ``ObjCEvolutionInterfaceBuilder/build(availabilityPlatform:)`` cannot
/// build, besides the `ObjCAPIEvolutionError` the evolution throws.
public enum ObjCEvolutionInterfaceError: Swift.Error, Equatable, CustomStringConvertible {
    /// Some versions were added with `addVersion(indexer:machO:version:)` and
    /// others with `addVersion(images:version:)`. An image group names its
    /// images and a single image does not, so the two cannot share an axis.
    case singleImageVersionsMixedWithImageGroups

    public var description: String {
        switch self {
        case .singleImageVersionsMixedWithImageGroups:
            return "An ObjC evolution interface takes every version as one image or every version as an image group; this builder was given both."
        }
    }
}
