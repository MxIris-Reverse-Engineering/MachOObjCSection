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
    /// each position of a presence bitmap stands for. Then come the
    /// declarations as `objc dump` writes them — classes, protocols,
    /// categories, each sorted by name — where a declaration that changed
    /// carries `// [●○●] added in 13.0`-style comments, and a declaration
    /// removed along the axis stays where it last appeared. C struct and
    /// union definitions follow, each from the newest version that has it,
    /// without annotations.
    public let interface: SemanticString
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
/// The order of the `addVersion(indexer:machO:version:)` calls is the version
/// axis, oldest first. Each call renders every declaration of its version and
/// takes the snapshot `ObjCAPISnapshotBuilder` takes; the builder keeps no
/// reference to the indexer or the Mach-O afterwards, so a host can index one
/// version at a time and let each go before loading the next. What it keeps
/// is every version's snapshot, the newest rendering of each declaration, and
/// each rendering that differs from the one before it.
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
    private let cTypeReplacements: [ObjCPrimitiveTypePattern: String]
    private var versions: [ObjCAPIVersionDescriptor] = []
    private var snapshots: [ObjCAPISnapshot] = []
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
        let versionIndex = versions.count
        let module = ObjCAPISnapshotBuilder(indexer: indexer).module()
        let snapshot = ObjCAPIDiffer().snapshot(of: module)
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
                context: context
            )
            containerRenderings[container.key] = renderings
        }
        for (protocolInfo, container) in zip(module.protocols, snapshot.protocols) {
            var renderings = containerRenderings[container.key] ?? ObjCEvolutionContainerRenderings()
            renderings.name = protocolInfo.name
            // Required before optional, as the snapshot lists them, so a
            // selector declared both ways keeps the record the snapshot keeps.
            Self.recordMembers(
                properties: protocolInfo.classProperties + protocolInfo.properties
                    + protocolInfo.optionalClassProperties + protocolInfo.optionalProperties,
                methods: protocolInfo.classMethods + protocolInfo.methods
                    + protocolInfo.optionalClassMethods + protocolInfo.optionalMethods,
                into: &renderings,
                at: versionIndex,
                context: context
            )
            containerRenderings[container.key] = renderings
        }
        for (categoryInfo, container) in zip(module.categories, snapshot.categories) {
            var renderings = containerRenderings[container.key] ?? ObjCEvolutionContainerRenderings()
            renderings.name = categoryInfo.className
            renderings.categoryName = categoryInfo.name
            Self.recordMembers(
                properties: categoryInfo.classProperties + categoryInfo.properties,
                methods: categoryInfo.classMethods + categoryInfo.methods,
                into: &renderings,
                at: versionIndex,
                context: context
            )
            containerRenderings[container.key] = renderings
        }

        for structName in indexer.structNames {
            if let definition = indexer.structSemanticString(forName: structName, context: context) {
                structDefinitions[structName] = definition
            }
        }
        for unionName in indexer.unionNames {
            if let definition = indexer.unionSemanticString(forName: unionName, context: context) {
                unionDefinitions[unionName] = definition
            }
        }

        snapshots.append(snapshot)
        versions.append(version)
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
    ///   two versions were added.
    public func build(availabilityPlatform: String? = nil) throws -> ObjCEvolutionInterface {
        let evolution = try ObjCAPIEvolutionBuilder().evolution(of: snapshots, versions: versions)
        let assembler = ObjCEvolutionContainerAssembler(evolution: evolution, availabilityPlatform: availabilityPlatform)

        var blocks: [[ObjCEvolutionLine]] = []
        let containerBuckets: [(kind: ObjCContainerKind, perVersion: [[ObjCContainerSnapshot]])] = [
            (.class, snapshots.map(\.classes)),
            (.protocol, snapshots.map(\.protocols)),
            (.category, snapshots.map(\.categories)),
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

    // MARK: - Rendering

    private static func recordMembers<MachO: ObjCMetadataSource>(
        ivars: [ObjCIvarInfo] = [],
        properties: [ObjCPropertyInfo],
        methods: [ObjCMethodInfo],
        into renderings: inout ObjCEvolutionContainerRenderings,
        at versionIndex: Int,
        context: ObjCRenderingContext<MachO>
    ) {
        var renderedKeys: Set<ObjCAPIKey> = []
        for ivarInfo in ivars {
            renderings.record(ivarInfo.semanticString(using: context), for: ObjCMemberRecord.identityKey(of: ivarInfo), at: versionIndex, renderedKeys: &renderedKeys)
        }
        for propertyInfo in properties {
            renderings.record(propertyInfo.semanticString(using: context), for: ObjCMemberRecord.identityKey(of: propertyInfo), at: versionIndex, renderedKeys: &renderedKeys)
        }
        for methodInfo in methods {
            renderings.record(methodInfo.semanticString(using: context), for: ObjCMemberRecord.identityKey(of: methodInfo), at: versionIndex, renderedKeys: &renderedKeys)
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
