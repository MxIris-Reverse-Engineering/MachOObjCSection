#if os(macOS)

import ObjCIndexing
import ObjCMetadataSource
import TypeIndexing

/// The types an image's Objective-C metadata declares, as swift-type-indexing's
/// `TypeDatabase` reads them: the classes, protocols, and C structs and unions
/// the image's `__objc_*` sections name.
///
/// `TypeDatabase` consults these only for names neither the SDK's API notes nor
/// its module interfaces attribute — private classes such as
/// `_UINavigationBarVisualProvider` — and reads an image only on such a miss.
/// Reading one prepares an `ObjCInterfaceIndexer` over it, which walks every
/// class of the image.
///
/// ```swift
/// let typeDatabase = TypeDatabase(platform: .macOS)
/// try await typeDatabase.index(
///     dependencies: dependencyImages.map { ObjCDeclaredTypeNames(machO: $0, imagePath: $0.imagePath) },
///     moduleFilter: { dependencyModuleNames.contains($0) }
/// )
/// ```
public struct ObjCDeclaredTypeNames<MachO: ObjCMetadataSource & Sendable>: DeclaredTypeNameSource {
    public let imagePath: String

    private let machO: MachO

    /// - Parameters:
    ///   - machO: The image, in this process or in a file.
    ///   - imagePath: Its install path, which names the module its types are
    ///     attributed to (`…/Foundation.framework/Foundation` → `Foundation`).
    public init(machO: MachO, imagePath: String) {
        self.machO = machO
        self.imagePath = imagePath
    }

    public func declaredTypeNames() async throws -> [String] {
        let interfaceIndexer = ObjCInterfaceIndexer(machO: machO, imagePath: imagePath)
        try await interfaceIndexer.prepare()
        return interfaceIndexer.classNames
            + interfaceIndexer.protocolNames
            + interfaceIndexer.structNames
            + interfaceIndexer.unionNames
    }
}

#endif
