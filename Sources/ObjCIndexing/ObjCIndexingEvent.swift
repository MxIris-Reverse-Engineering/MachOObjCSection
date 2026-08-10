import Foundation

/// Everything ``ObjCInterfaceIndexer`` reports while it builds an index.
///
/// This is one channel where the RuntimeViewer original had two: a progress
/// stream continuation and a separate relationship-event handler. They were
/// always driven from the same walk over the image, so callers that wanted
/// both had to wire up two things and keep them in step; merging them means a
/// single handler sees the whole story in order.
public enum ObjCIndexingEvent: Sendable {
    /// Progress through one phase of the walk.
    ///
    /// `currentCount` counts items finished so far, `totalCount` the items in
    /// this phase. `itemDescription` names the item just handled, and is empty
    /// for the event announcing a phase's start.
    case progress(phase: Phase, itemDescription: String, currentCount: Int, totalCount: Int)

    /// A class was found to subclass `superclass`.
    case subclassIndexed(className: String, superclass: String, imagePath: String)

    /// A class was found to adopt `protocolName`.
    case conformanceIndexed(className: String, protocolName: String, imagePath: String)

    /// A category made its target class adopt `protocolName`.
    case categoryConformanceIndexed(targetClassName: String, protocolName: String, imagePath: String)

    /// The stages of an index build, in the order they run.
    public enum Phase: String, Sendable, Codable, CaseIterable {
        case indexingSubclasses
        case loadingClasses
        case loadingProtocols
        case indexingConformances
        case loadingCategories
    }
}
