import Semantic

/// The kinds of comment an Objective-C declaration rendering marks when
/// ``ObjCRenderingContext/marksCommentStructure`` is set. Explanatory text
/// is swift-semantic-string's own `note`, shared with MachOSwiftSection.
///
/// | Kind | Comment | Segments |
/// |---|---|---|
/// | `impAddress` | `// IMP: 0x1A2B`, `// getter IMP: …`, `// setter IMP: …` | marker, label, separator, value |
/// | `ivarOffset` | `// offset: 8` | marker, label, separator, value |
/// | `ivarOffsetUnknown` | `// offset: unknown` | marker, label, separator, value |
/// | `propertySynthesis` | `// @synthesize name = _name`, `// @synthesize name` | marker, label, separator, name, then separator and value |
/// | `propertyDynamic` | `// @dynamic name` | marker, label, separator, name |
/// | `typeNote` | `/* block */`, `/* function pointer */` | marker, text, marker |
/// | `note` | the line above a host-supplied class | marker, text |
///
/// An IMP that resolves to nothing has its raw value, `<invalid 0x…>`, as the
/// value, in an `.error` atom. An ivar offset comment the host worded is
/// split at its first `: ` into label and value, and is all value without one.
extension AnnotationRegion.Kind {
    /// The address of a method's, or a property accessor's, implementation.
    public static let impAddress = Self("impAddress")

    /// An ivar's offset.
    public static let ivarOffset = Self("ivarOffset")

    /// An ivar whose offset the image does not record, such as one of a
    /// generic Swift class the host supplied.
    public static let ivarOffsetUnknown = Self("ivarOffsetUnknown")

    /// The ivar a property is synthesized into.
    public static let propertySynthesis = Self("propertySynthesis")

    /// A property declared `@dynamic`.
    public static let propertyDynamic = Self("propertyDynamic")

    /// What a type the encoding gives no signature for really is: a block
    /// written as `id`, a function pointer as `void *`.
    public static let typeNote = Self("typeNote")
}
