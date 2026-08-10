import Foundation

/// Everything ``ObjCInterfaceIndexer`` reports while it builds an index.
///
/// This is one channel where the RuntimeViewer original had two: a progress
/// stream continuation and a separate relationship-event handler. They were
/// always driven from the same walk over the image, so callers that wanted
/// both had to wire up two things and keep them in step; merging them means a
/// single handler sees the whole story in order.
///
/// ## The relationship cases are the only channel for relationship data
///
/// The indexer parses; it does not remember how classes relate to each other.
/// The three relationship cases below are the only way inheritance and
/// protocol adoption leave this library — an indexer constructed without an
/// `eventHandler` keeps no record of them whatsoever. Callers that need the
/// relationships accumulate them from this stream into whatever shape suits
/// them. See ``ObjCInterfaceIndexer/init(machO:imagePath:eventHandler:)``.
///
/// ## Emission order is guaranteed; the execution context is not
///
/// For one image and one version of this library, two `prepare()` runs emit
/// exactly the same sequence of events. The order is: every class-phase event
/// precedes every category-phase event; within the class phase classes follow
/// the `__objc_classlist` walk, each class emitting its `subclassIndexed`
/// before its `conformanceIndexed` events in declaration order; the category
/// phase walks the category list the same way.
///
/// Callers may rely on that — accumulating this stream into an ordered
/// collection reproduces the binary's declaration order, which is what the
/// reverse tables this library used to keep did. Changing the order is a
/// breaking change.
///
/// What is deliberately *not* promised is which thread or queue the handler
/// runs on; see ``ObjCInterfaceIndexer/prepare()``.
public enum ObjCIndexingEvent: Sendable {
    /// Progress through one phase of the walk.
    ///
    /// `currentCount` counts items finished so far, `totalCount` the items in
    /// this phase. `itemDescription` names the item just handled, and is empty
    /// for the event announcing a phase's start.
    case progress(phase: Phase, itemDescription: String, currentCount: Int, totalCount: Int)

    /// A class was found to subclass `superclass`.
    ///
    /// `isSwiftStable` is read off the subclassing class' own `class_t`
    /// record. `__objc_classlist` carries a record for every Swift class with
    /// an Objective-C ancestor, so a consumer can present the class as Swift
    /// without doing any string-name bridging of its own.
    case subclassIndexed(
        className: String,
        superclass: String,
        imagePath: String,
        isSwiftStable: Bool
    )

    /// A class was found to adopt `protocolName` inline, i.e. through its own
    /// `@interface … <Protocol>` list. Adoptions contributed by a category are
    /// reported as ``categoryConformanceIndexed`` instead.
    case conformanceIndexed(
        className: String,
        protocolName: String,
        imagePath: String,
        isSwiftStable: Bool
    )

    /// A category made its target class adopt `protocolName`.
    ///
    /// `imagePath` is the image declaring the *category*, which for a category
    /// on another framework's class is not the image declaring
    /// `targetClassName`. Consumers keying off `imagePath` to locate the class
    /// will not find it there; that asymmetry is deliberate and predates this
    /// event carrying the path at all.
    ///
    /// `targetIsSwiftStable` is resolved by following the category's target
    /// class pointer across image boundaries. A category whose target cannot
    /// be resolved reports `false`, which is indistinguishable from a
    /// successfully resolved non-Swift class.
    case categoryConformanceIndexed(
        targetClassName: String,
        protocolName: String,
        imagePath: String,
        targetIsSwiftStable: Bool
    )

    /// The stages of an index build, in the order they run.
    public enum Phase: String, Sendable, Codable, CaseIterable {
        case indexingSubclasses
        case loadingClasses
        case loadingProtocols
        case indexingConformances
        case loadingCategories
    }
}
