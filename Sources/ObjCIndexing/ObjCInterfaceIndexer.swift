import Foundation
import MachOKit
import MachOObjCSection
import ObjCDeclarationRendering
import ObjCDump
import ObjCTypeDecodeKit
import OrderedCollections
import Semantic

/// A reference to an Objective-C class (or a Swift class that surfaces a
/// `class_t` record through `__objc_classlist`) that was found to subclass
/// another class or to adopt a protocol.
///
/// `isSwiftStable` carries the structural signal that lets a caller decide
/// whether to present the reference as a Swift class or an Objective-C one —
/// a Swift class compiled with stable ABI still shows up in the Objective-C
/// class list, and usually wants to be labelled as Swift.
public struct ObjCClassReference: Hashable, Sendable, Codable {
    public let className: String
    public let imagePath: String
    public let isSwiftStable: Bool

    public init(className: String, imagePath: String, isSwiftStable: Bool) {
        self.className = className
        self.imagePath = imagePath
        self.isSwiftStable = isSwiftStable
    }
}

/// Per-image Objective-C interface index: the parsed data store for one
/// Mach-O image's classes, protocols, categories and C struct/union
/// definitions, plus the class-inheritance and protocol-adoption reverse
/// tables.
///
/// Construct it with an image, call ``prepare()`` once, then query. All the
/// raw `MachOObjCSection` / `ObjCDump` extraction happens inside `prepare()`,
/// so callers deal only in names and the grouped info types.
///
/// Aggregation: keep one empty aggregate instance and register every
/// per-image indexer on it via ``addSubIndexer(_:)``, so relationship queries
/// (``subclasses(of:)``, ``conformingClasses(toProtocol:)``) fan out across
/// every indexed image rather than stopping at one.
///
/// `@unchecked Sendable`: the `MachOImage` supplied at `init` and the stored
/// `ObjCDump` / `MachOObjCSection` values are not themselves `Sendable`, but
/// `machO` is an immutable `let` and every dictionary is mutex-guarded and
/// immutable once `prepare()` returns.
public final class ObjCInterfaceIndexer: @unchecked Sendable {

    // MARK: - Group Types

    /// A class paired with its own `ObjCClassInfo` plus the `ObjCClassInfo`
    /// of every superclass (resolved across images), `info.first` being the
    /// class itself.
    public typealias ObjCClassGroup = (objcClass: any ObjCClassProtocol, info: [ObjCClassInfo])

    public typealias ObjCProtocolGroup = (objcProtocol: any ObjCProtocolProtocol, info: ObjCProtocolInfo)

    public typealias ObjCCategoryGroup = (objcCategory: any ObjCCategoryProtocol, info: ObjCCategoryInfo)

    // MARK: - C Struct / Union

    /// A C `struct` / `union` definition harvested from the ivar / method /
    /// property type encodings of the image's ObjC metadata.
    private struct CStructOrUnion: Hashable {
        let name: String

        let fields: [ObjCField]

        var hasBitFieldOnly: Bool {
            fields.allSatisfy { $0.bitWidth != nil }
        }

        var numberOfHasNameFields: Int {
            fields.count { $0.name != nil }
        }

        @SemanticStringBuilder
        func semanticString(isStruct: Bool, context: ObjCRenderingContext) -> SemanticString {
            Keyword(isStruct ? "struct" : "union")
            Space()
            TypeName(kind: .other, name)
            Joined {
                MemberList(level: 1) {
                    for (index, field) in fields.enumerated() {
                        field.semanticString(fallbackName: "x\(index)", level: 1, context: context)
                    }
                }
            } prefix: {
                " {"
            } suffix: {
                Indent(level: 0)
                "}"
            }
        }
    }

    // MARK: - Indexed Image

    /// The Mach-O image this indexer parses. Bound at `init` and never
    /// reassigned; `prepare()` reads it to populate the data store below.
    private let machO: MachOImage

    /// The image path recorded into every `ObjCClassReference`. Passed
    /// explicitly rather than derived from `machO.imagePath`: an indexer may
    /// be constructed from a path that differs from the resolved image own
    /// path — e.g. in Debug builds a main-executable stub path resolves to a
    /// sibling `.debug.dylib` image whose `imagePath` is not the stub one.
    private let imagePath: String

    // MARK: - Interface Data Store

    // Each store below is spelled out as a `Mutex` box plus a computed
    // property, which is exactly what FrameworkToolbox's `@Mutex` macro used
    // to generate. The macro is Apple-platform only, and this package supports
    // Linux — see `Internal/Mutex.swift`.

    private let _classes = Mutex<[String: ObjCClassGroup]>([:])
    private var classes: [String: ObjCClassGroup] {
        get { _classes.withLock { $0 } }
        set { _classes.withLock { $0 = newValue } }
    }

    private let _protocols = Mutex<[String: ObjCProtocolGroup]>([:])
    private var protocols: [String: ObjCProtocolGroup] {
        get { _protocols.withLock { $0 } }
        set { _protocols.withLock { $0 = newValue } }
    }

    private let _categories = Mutex<[String: ObjCCategoryGroup]>([:])
    private var categories: [String: ObjCCategoryGroup] {
        get { _categories.withLock { $0 } }
        set { _categories.withLock { $0 = newValue } }
    }

    private let _structs = Mutex<[String: CStructOrUnion]>([:])
    private var structs: [String: CStructOrUnion] {
        get { _structs.withLock { $0 } }
        set { _structs.withLock { $0 = newValue } }
    }

    private let _unions = Mutex<[String: CStructOrUnion]>([:])
    private var unions: [String: CStructOrUnion] {
        get { _unions.withLock { $0 } }
        set { _unions.withLock { $0 = newValue } }
    }

    // MARK: - Relationship Reverse Tables

    private let _subclassesByClassName = Mutex<[String: OrderedSet<ObjCClassReference>]>([:])
    private var subclassesByClassName: [String: OrderedSet<ObjCClassReference>] {
        get { _subclassesByClassName.withLock { $0 } }
        set { _subclassesByClassName.withLock { $0 = newValue } }
    }

    private let _conformingClassesByProtocolName = Mutex<[String: OrderedSet<ObjCClassReference>]>([:])
    private var conformingClassesByProtocolName: [String: OrderedSet<ObjCClassReference>] {
        get { _conformingClassesByProtocolName.withLock { $0 } }
        set { _conformingClassesByProtocolName.withLock { $0 = newValue } }
    }

    private let _subIndexers = Mutex<[ObjCInterfaceIndexer]>([])
    private var subIndexers: [ObjCInterfaceIndexer] {
        get { _subIndexers.withLock { $0 } }
        set { _subIndexers.withLock { $0 = newValue } }
    }

    private let eventHandler: (@Sendable (ObjCIndexingEvent) -> Void)?

    public init(
        machO: MachOImage,
        imagePath: String,
        eventHandler: (@Sendable (ObjCIndexingEvent) -> Void)? = nil
    ) {
        self.machO = machO
        self.imagePath = imagePath
        self.eventHandler = eventHandler
    }

    // MARK: - Preparation

    /// Parse this indexer's Mach-O image (`machO`, bound at `init`) into the
    /// data store: every class / protocol / category, the C struct / union
    /// definitions harvested from their type encodings, and — inline as the
    /// `__objc_classlist` walk proceeds — the class-inheritance and
    /// protocol-adoption reverse tables.
    ///
    /// Call once after construction, after which the store is immutable. An
    /// aggregate indexer — one that only collects sub-indexers via
    /// ``addSubIndexer(_:)`` — never needs this.
    ///
    /// Progress and relationship events are delivered to the `eventHandler`
    /// supplied at `init`.
    public func prepare() async throws {
        var classByName: [String: ObjCClassGroup] = [:]
        var protocolByName: [String: ObjCProtocolGroup] = [:]
        var categoryByName: [String: ObjCCategoryGroup] = [:]
        var structsByName: [String: CStructOrUnion] = [:]
        var unionsByName: [String: CStructOrUnion] = [:]
        var classInfoCache: [String: ObjCClassInfo] = [:]

        func setObjCType(_ type: ObjCType) {
            switch type {
            case .struct(let name, let fields):
                if let name {
                    let newStruct = CStructOrUnion(name: name, fields: fields ?? [])
                    guard !newStruct.hasBitFieldOnly else { return }
                    if let existStruct = structsByName[name] {
                        if existStruct.numberOfHasNameFields < newStruct.numberOfHasNameFields {
                            structsByName[name] = newStruct
                        }
                    } else {
                        structsByName[name] = newStruct
                    }
                }
            case .union(let name, let fields):
                if let name {
                    let newUnion = CStructOrUnion(name: name, fields: fields ?? [])
                    guard !newUnion.hasBitFieldOnly else { return }
                    if let existUnion = unionsByName[name] {
                        if existUnion.numberOfHasNameFields < newUnion.numberOfHasNameFields {
                            unionsByName[name] = newUnion
                        }
                    } else {
                        unionsByName[name] = newUnion
                    }
                }
            default:
                break
            }
        }

        func setObjCTypeFromMethods(_ methods: [ObjCMethodInfo]) {
            for method in methods {
                if let returnType = method.returnType {
                    setObjCType(returnType)
                }

                if let argumentInfos = method.argumentInfos {
                    for argumentInfo in argumentInfos {
                        setObjCType(argumentInfo.type)
                    }
                }
            }
        }

        func setObjCTypeFromProperties(_ properties: [ObjCPropertyInfo]) {
            for property in properties {
                for attribute in property.attributes {
                    if let type = attribute.type {
                        setObjCType(type)
                    }
                }
            }
        }

        let objcClasses: [any ObjCClassProtocol] = machO.objc.classes64.orEmpty + machO.objc.classes32.orEmpty + machO.objc.nonLazyClasses64.orEmpty + machO.objc.nonLazyClasses32.orEmpty

        // One-shot progress marker so the loading indicator can surface
        // "Indexing Objective-C subclasses…" before the per-class loop
        // starts pushing `.loadingObjCClasses` updates. Inheritance and
        // protocol-adoption indexing happens inline below — every class in
        // `__objc_classlist` (including Swift-derived ones via the same
        // record format) is fed to the reverse tables as we walk the list.
        eventHandler?(ObjCIndexingEvent.progress(
            phase: .indexingSubclasses,
            itemDescription: "",
            currentCount: 0,
            totalCount: objcClasses.count
        ))

        for objcClass in objcClasses {
            let objcClassGroup: ObjCClassGroup = (objcClass, infoWithSuperclasses(class: objcClass, in: machO, cache: &classInfoCache))
            guard let objcClassInfo = objcClassGroup.info.first else { continue }
            classByName[objcClassInfo.name] = objcClassGroup
            eventHandler?(ObjCIndexingEvent.progress(
                phase: .loadingClasses,
                itemDescription: objcClassInfo.name,
                currentCount: classByName.count,
                totalCount: objcClasses.count
            ))

            // Feed the reverse tables. We pass the already-extracted class
            // info — `superClassName` is resolved through MachO's bind/rebase
            // walking by `infoWithSuperclasses`, so we don't redo that work
            // here. `isSwiftStable` comes off the raw class_t record itself,
            // so callers can label bridged classes as Swift.
            indexClass(
                className: objcClassInfo.name,
                superClassName: objcClassInfo.superClassName,
                adoptedProtocolNames: objcClassInfo.protocols.map(\.name),
                imagePath: imagePath,
                isSwiftStable: objcClass.isSwiftStable
            )

            for ivar in objcClassInfo.ivars {
                if let type = ivar.type {
                    setObjCType(type)
                }
            }

            setObjCTypeFromProperties(objcClassInfo.properties + objcClassInfo.classProperties)
            setObjCTypeFromMethods(objcClassInfo.methods + objcClassInfo.classMethods)
        }

        // `__objc_protolist` carries a full `protocol_t` record for *every*
        // protocol whose `@protocol` declaration was in scope at compile
        // time — including ones merely imported from dependencies (`NSObject`,
        // `NSCopying`, …), not just this image's own. We list all of them:
        // there is no authoritative "defining image" recorded for a protocol
        // (unlike classes, which are emitted exactly once in their own image's
        // `__objc_classlist`), so every attempt at attributing ownership is a
        // heuristic that can silently *drop* an image's real protocols. A
        // previous dependency-closure heuristic did exactly that — see
        // `Documentations/ResolvedIssues/2026-08-05-objc-protocol-ownership-filter.md`.
        let objcProtocols: [any ObjCProtocolProtocol] = machO.objc.protocols64.orEmpty + machO.objc.protocols32.orEmpty

        for objcProtocol in objcProtocols {
            guard let objcProtocolInfo = objcProtocol.info(in: machO) else { continue }
            protocolByName[objcProtocolInfo.name] = (objcProtocol, objcProtocolInfo)
            eventHandler?(ObjCIndexingEvent.progress(
                phase: .loadingProtocols,
                itemDescription: objcProtocolInfo.name,
                currentCount: protocolByName.count,
                totalCount: objcProtocols.count
            ))
            setObjCTypeFromProperties(objcProtocolInfo.properties + objcProtocolInfo.classProperties)
            setObjCTypeFromMethods(objcProtocolInfo.methods + objcProtocolInfo.classMethods)
        }

        var objcCategories: [any ObjCCategoryProtocol] = []

        objcCategories.append(contentsOf: machO.objc.categories64.orEmpty)
        objcCategories.append(contentsOf: machO.objc.categories32.orEmpty)
        objcCategories.append(contentsOf: machO.objc.nonLazyCategories64.orEmpty)
        objcCategories.append(contentsOf: machO.objc.nonLazyCategories32.orEmpty)
        objcCategories.append(contentsOf: machO.objc.categories2_64.orEmpty)
        objcCategories.append(contentsOf: machO.objc.categories2_32.orEmpty)

        // One-shot marker that conformance indexing starts; each category
        // extends the conformer set of its target class for every protocol
        // the category adopts.
        eventHandler?(ObjCIndexingEvent.progress(
            phase: .indexingConformances,
            itemDescription: "",
            currentCount: 0,
            totalCount: objcCategories.count
        ))

        for objcCategory in objcCategories {
            guard let objcCategoryInfo = objcCategory.info(in: machO) else { continue }
            categoryByName[objcCategoryInfo.uniqueName] = (objcCategory, objcCategoryInfo)
            eventHandler?(ObjCIndexingEvent.progress(
                phase: .loadingCategories,
                itemDescription: objcCategoryInfo.uniqueName,
                currentCount: categoryByName.count,
                totalCount: objcCategories.count
            ))
            setObjCTypeFromProperties(objcCategoryInfo.properties + objcCategoryInfo.classProperties)
            setObjCTypeFromMethods(objcCategoryInfo.methods + objcCategoryInfo.classMethods)

            // Feed category data to the reverse tables. The target class'
            // Swift stable flag is read from the already-resolved class
            // record so category adoptions on bridged classes (e.g. NSError
            // extending Swift error protocols) carry `isSwiftStable == true`
            // and can be surfaced as Swift at query time.
            let targetClassName = objcCategoryInfo.className
            let targetIsSwiftStable: Bool
            if let (_, targetClass) = objcCategory.class(in: machO) {
                targetIsSwiftStable = targetClass.isSwiftStable
            } else {
                targetIsSwiftStable = false
            }
            indexCategory(
                targetClassName: targetClassName,
                targetIsSwiftStable: targetIsSwiftStable,
                adoptedProtocolNames: objcCategoryInfo.protocols.map(\.name),
                imagePath: imagePath
            )
        }

        classes = classByName
        protocols = protocolByName
        categories = categoryByName
        structs = structsByName
        unions = unionsByName
    }

    /// Resolve `cls` to its own `ObjCClassInfo` followed by the
    /// `ObjCClassInfo` of every superclass, walking `superClass(in:)` across
    /// image boundaries. `cache` memoizes `info(in:)` extraction so a deep
    /// inheritance chain shared by many classes is decoded only once.
    private func infoWithSuperclasses<Class: ObjCClassProtocol>(class cls: Class, in machO: MachOImage, cache: inout [String: ObjCClassInfo]) -> [ObjCClassInfo] {
        guard let className = cls.name(in: machO) else { return [] }

        var currentInfo: ObjCClassInfo?

        if let cacheInfo = cache[className] {
            currentInfo = cacheInfo
        } else {
            let info = cls.info(in: machO)
            currentInfo = info
            cache[className] = info
        }

        guard let currentInfo else { return [] }

        var resultInfos: [ObjCClassInfo] = [currentInfo]

        var machOAndSuperclass = cls.superClass(in: machO)

        while let currentMachOAndSuperclass = machOAndSuperclass {
            let currentMachO = currentMachOAndSuperclass.0
            let currentSuperclass = currentMachOAndSuperclass.1

            machOAndSuperclass = currentSuperclass.superClass(in: currentMachO)

            guard let superClassName = currentSuperclass.name(in: currentMachO) else { continue }

            var superclassInfo: ObjCClassInfo?
            if let cacheInfo = cache[superClassName] {
                superclassInfo = cacheInfo
            } else {
                let info = currentSuperclass.info(in: currentMachO)
                superclassInfo = info
                cache[superClassName] = info
            }
            if let superclassInfo {
                resultInfos.append(superclassInfo)
            }
        }

        return resultInfos
    }

    // MARK: - Reverse-table Feed

    /// Records one Objective-C class record from `__objc_classlist`:
    ///   - its superclass name -> add this class as a subclass entry
    ///   - each protocol it adopts inline -> add this class as a conformer
    ///
    /// `__objc_classlist` automatically contains a `class_t` record for every
    /// Swift class with an Objective-C ancestor (`class Foo: NSObject`,
    /// whether or not annotated `@objc`). Pass `isSwiftStable: true` for those
    /// so callers can materialize the reference as a Swift class at query
    /// time without doing any string-name bridging.
    private func indexClass(
        className: String,
        superClassName: String?,
        adoptedProtocolNames: [String],
        imagePath: String,
        isSwiftStable: Bool
    ) {
        let reference = ObjCClassReference(
            className: className,
            imagePath: imagePath,
            isSwiftStable: isSwiftStable
        )

        if let superClassName, !superClassName.isEmpty {
            // `_ =` drops `OrderedSet.append`'s `(inserted:index:)` tuple so
            // the `withLock` closure stays `Void`-returning; a repeated
            // reference being deduped by `OrderedSet` is the intended behavior.
            _subclassesByClassName.withLock { dictionary in
                _ = dictionary[superClassName, default: []].append(reference)
            }
            eventHandler?(
                ObjCIndexingEvent.subclassIndexed(
                    className: className,
                    superclass: superClassName,
                    imagePath: imagePath
                )
            )
        }

        for protocolName in adoptedProtocolNames {
            _conformingClassesByProtocolName.withLock { dictionary in
                _ = dictionary[protocolName, default: []].append(reference)
            }
            eventHandler?(
                ObjCIndexingEvent.conformanceIndexed(
                    className: className,
                    protocolName: protocolName,
                    imagePath: imagePath
                )
            )
        }
    }

    /// Records one Objective-C category. Categories extend the conformance
    /// set of the target class: every protocol the category adopts gets the
    /// target class added as a conformer (with the target's `isSwiftStable`
    /// flag carried through, so a category on a bridged class still surfaces
    /// the class as Swift).
    private func indexCategory(
        targetClassName: String,
        targetIsSwiftStable: Bool,
        adoptedProtocolNames: [String],
        imagePath: String
    ) {
        let reference = ObjCClassReference(
            className: targetClassName,
            imagePath: imagePath,
            isSwiftStable: targetIsSwiftStable
        )

        for protocolName in adoptedProtocolNames {
            _conformingClassesByProtocolName.withLock { dictionary in
                _ = dictionary[protocolName, default: []].append(reference)
            }
            eventHandler?(
                ObjCIndexingEvent.categoryConformanceIndexed(
                    targetClassName: targetClassName,
                    protocolName: protocolName,
                    imagePath: imagePath
                )
            )
        }
    }

    // MARK: - Interface Query

    /// The class plus its superclass chain for `name`, or `nil` if `name` is
    /// not a class in this image. `info.first` is the class itself.
    public func classGroup(forName name: String) -> ObjCClassGroup? {
        classes[name]
    }

    /// The protocol record for `name`, or `nil` if `name` is not a protocol
    /// in this image.
    public func protocolGroup(forName name: String) -> ObjCProtocolGroup? {
        protocols[name]
    }

    /// The category record for `uniqueName`, or `nil` if absent.
    public func categoryGroup(forName uniqueName: String) -> ObjCCategoryGroup? {
        categories[uniqueName]
    }

    /// Names of every class in this image (`__objc_classlist` order is not
    /// preserved — dictionary iteration order).
    public var classNames: [String] {
        Array(classes.keys)
    }

    public var protocolNames: [String] {
        Array(protocols.keys)
    }

    public var categoryNames: [String] {
        Array(categories.keys)
    }

    public var structNames: [String] {
        Array(structs.keys)
    }

    public var unionNames: [String] {
        Array(unions.keys)
    }

    /// Whether a C `struct` named `name` was harvested from this image —
    /// used by `ObjCRenderingContext` to decide whether a referenced struct
    /// should be emitted inline or left as a forward declaration.
    public func containsStruct(named name: String) -> Bool {
        structs[name] != nil
    }

    public func containsUnion(named name: String) -> Bool {
        unions[name] != nil
    }

    /// The rendered interface of the C `struct` named `name`, or `nil` if
    /// absent. The `context` is supplied by the caller because it depends on
    /// per-request generation options.
    public func structSemanticString(forName name: String, context: ObjCRenderingContext) -> SemanticString? {
        structs[name]?.semanticString(isStruct: true, context: context)
    }

    public func unionSemanticString(forName name: String, context: ObjCRenderingContext) -> SemanticString? {
        unions[name]?.semanticString(isStruct: false, context: context)
    }

    // MARK: - Relationship Query

    /// All directly subclassing references for the given Objective-C class
    /// name, gathered from this indexer's own per-image data plus every
    /// sub-indexer registered via `addSubIndexer`. Insertion order is
    /// preserved across a single image; cross-image order follows
    /// `subIndexers` registration order.
    public func subclasses(of className: String) -> [ObjCClassReference] {
        var result: OrderedSet<ObjCClassReference> = subclassesByClassName[className] ?? []
        for subIndexer in subIndexers {
            for reference in subIndexer.subclasses(of: className) {
                result.append(reference)
            }
        }
        return Array(result)
    }

    /// All classes (across all sub-indexers) that adopt the given protocol
    /// either inline (`@interface … <P>`) or via a category that adopts the
    /// protocol on the class.
    public func conformingClasses(toProtocol protocolName: String) -> [ObjCClassReference] {
        var result: OrderedSet<ObjCClassReference> = conformingClassesByProtocolName[protocolName] ?? []
        for subIndexer in subIndexers {
            for reference in subIndexer.conformingClasses(toProtocol: protocolName) {
                result.append(reference)
            }
        }
        return Array(result)
    }

    // MARK: - Aggregation

    /// Registers a per-image indexer with this aggregate, so that relationship
    /// queries on the aggregate also search that image.
    public func addSubIndexer(_ subIndexer: ObjCInterfaceIndexer) {
        _subIndexers.withLock { $0.append(subIndexer) }
    }
}
