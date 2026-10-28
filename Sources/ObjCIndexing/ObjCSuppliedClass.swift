import ObjCDump

/// A class the image keeps no class object for, described by a host that
/// reads Swift metadata, so that ``ObjCInterfaceIndexer`` can index it.
///
/// Three kinds of Swift class with an Objective-C ancestor are missing from
/// `__objc_classlist`, so the indexer's walk of the class lists never meets
/// them. What the image does keep of each — its `class_ro_t` — is only found
/// through its Swift type descriptor and metadata, which this library does not
/// read. A host that does passes the classes in through
/// ``ObjCInterfaceIndexer/init(machO:imagePath:suppliedClasses:eventHandler:)``.
public struct ObjCSuppliedClass: Sendable, Hashable {
    /// Why the image keeps no class object for the class.
    public enum Kind: Sendable, Hashable {
        /// A generic class. The runtime makes a class object for each
        /// specialization; the image keeps a `class_ro_t` template in the
        /// class's generic metadata pattern, without a name and without the
        /// offsets of the ivars.
        case genericSwiftClass

        /// A class with a superclass in another module built for library
        /// evolution, registered with the runtime through `__objc_stublist`.
        /// The class stub carries no pointer to the `class_ro_t`; the class's
        /// resilient metadata pattern does.
        case swiftClassWithResilientAncestry

        /// A class with a generic superclass, registered with the runtime
        /// through `__objc_stublist`; its `class_ro_t` is reached through its
        /// metadata.
        case swiftClassWithGenericAncestry
    }

    /// The name the class is indexed and rendered under, as the host chooses
    /// to spell it.
    ///
    /// The categories of a class with generic ancestry go under the name its
    /// `class_ro_t` carries, so supply such a class under that name to keep
    /// them on it.
    public var name: String

    /// The Objective-C name of the superclass.
    public var superClassName: String?

    /// The offset of the class's `class_ro_t`.
    ///
    /// Offsets follow the convention of `ObjCClassRODataProtocol.offset`: a
    /// file offset within the slice for a standalone binary, the unslid
    /// address less `sharedRegionStart` for an image in a dyld shared cache,
    /// and the distance from the image's header for a `MachOImage`.
    public var readOnlyDataOffset: Int

    /// The offset of the metaclass's `class_ro_t`. Without it the class has no
    /// class methods or class properties.
    public var metaclassReadOnlyDataOffset: Int?

    /// The offset of the class stub, the address the class's `__objc_stublist`
    /// entry holds. A category whose class pointer holds that address is
    /// attributed to this class: Swift points the `@objc` extensions of a
    /// class with resilient ancestry at its stub.
    ///
    /// The other kinds need none. A generic class has no stub, and Swift
    /// points the `@objc` extensions of a class with generic ancestry at the
    /// class's own metadata, which names it.
    public var classStubOffset: Int?

    public var kind: Kind

    public init(
        name: String,
        superClassName: String?,
        readOnlyDataOffset: Int,
        metaclassReadOnlyDataOffset: Int? = nil,
        classStubOffset: Int? = nil,
        kind: Kind
    ) {
        self.name = name
        self.superClassName = superClassName
        self.readOnlyDataOffset = readOnlyDataOffset
        self.metaclassReadOnlyDataOffset = metaclassReadOnlyDataOffset
        self.classStubOffset = classStubOffset
        self.kind = kind
    }
}

/// A supplied class as ``ObjCInterfaceIndexer`` indexed it.
public struct ObjCSuppliedClassGroup: Sendable {
    /// The class as the host described it.
    public let suppliedClass: ObjCSuppliedClass

    /// The class's own `ObjCClassInfo`, then those of its superclasses found
    /// by name in the same indexer. A superclass with a class object brings
    /// its whole chain and ends the walk; a supplied superclass brings its own
    /// information and the walk goes on to its superclass. The walk stops at
    /// a name the indexer does not know.
    public let info: [ObjCClassInfo]

    /// The ivars whose offset the image does not record: a generic class's
    /// template leaves every ivar offset for the runtime to fill. Their
    /// `offset` in `info.first` is 0.
    public let ivarNamesWithUnknownOffset: Set<String>
}
