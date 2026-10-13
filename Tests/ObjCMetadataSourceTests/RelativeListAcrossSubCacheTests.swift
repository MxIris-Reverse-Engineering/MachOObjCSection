import Testing
import Foundation
import MachOKit
import MachOKitExtensions
@testable import MachOObjCSection
import ObjCDump
import ObjCMetadataSource

/// Foundation classes of the running system's dyld cache whose own list of one
/// kind — the entry carrying Foundation's image index in the class's relative
/// list of lists — lies in another file of the cache than Foundation's header.
/// `nil` when the cache keeps every such list in the file of the header, which
/// gates the suite off: dyld caches up to macOS 26.2 were laid out that way.
private struct CrossFileRelativeListProbe: Sendable {
    let cacheURL: URL
    /// A class whose own property list is in another file.
    let propertyListClassName: String
    /// A class whose own protocol list is in another file.
    let protocolListClassName: String

    static let system: CrossFileRelativeListProbe? = try? make()

    private static func make() throws -> CrossFileRelativeListProbe? {
        guard let cacheURL = DyldCache.host?.url else { return nil }
        let cache = try DyldCache(url: cacheURL)
        guard let foundation = cache.machOFile(by: .name("Foundation")),
              let imageIndex = foundation.objcImageIndex
        else { return nil }

        func ownListIsInAnotherFile(_ entries: [RelativeListListEntry]?) -> Bool {
            guard let ownEntry = entries?.first(where: { $0.imageIndex == imageIndex }) else { return false }
            let address = cache.mainCacheHeader.sharedRegionStart + UInt64(ownEntry.offset + ownEntry.listOffset)
            guard let (listCache, _) = foundation.cacheAndFileOffset(for: address) else { return false }
            return listCache.url != foundation.url
        }

        var propertyListClassName: String?
        var protocolListClassName: String?
        for objcClass in foundation.objc.classes64 ?? [] {
            guard let readOnlyData = objcClass.classROData(in: foundation),
                  let className = foundation.objcClassName(of: objcClass)
            else { continue }
            if propertyListClassName == nil,
               ownListIsInAnotherFile(readOnlyData.propertyRelativeListList(in: foundation)?.entries(in: foundation)) {
                propertyListClassName = className
            }
            if protocolListClassName == nil,
               ownListIsInAnotherFile(readOnlyData.protocolRelativeListList(in: foundation)?.entries(in: foundation)) {
                protocolListClassName = className
            }
            if let propertyListClassName, let protocolListClassName {
                return CrossFileRelativeListProbe(
                    cacheURL: cacheURL,
                    propertyListClassName: propertyListClassName,
                    protocolListClassName: protocolListClassName
                )
            }
        }
        return nil
    }
}

/// A class that other images of the cache extend with categories has its
/// lists attached in advance: each of its method, property and protocol
/// pointers leads to a list of lists, one entry per image. Read from the cache
/// files, an entry's list was looked for only in the file holding the header
/// of the entry's image. Since macOS 26.4 the cache keeps each group of
/// images' data in files of its own (`.dylddata`): a property or protocol list
/// lies in one of those while the header and the method list stay in the text
/// file, so file mode lost every instance property and every adopted protocol
/// of such a class — NSView, NSWindow, NSString, NSBundle — without an error.
@Suite(
    "Relative lists in another file of the dyld cache",
    .enabled(if: CrossFileRelativeListProbe.system != nil)
)
struct RelativeListAcrossSubCacheTests {
    private static func classInfos(named className: String) throws -> (file: ObjCClassInfo, image: ObjCClassInfo) {
        let probe = try #require(CrossFileRelativeListProbe.system)
        let file = try #require(try DyldCache(url: probe.cacheURL).machOFile(by: .name("Foundation")))
        let image = try #require(MachOImage(name: "Foundation"))
        let fileClass = try #require(file.objc.classes64?.first { file.objcClassName(of: $0) == className })
        let imageClass = try #require(image.objc.classes64?.first { image.objcClassName(of: $0) == className })
        let fileInfo = try #require(file.objcClassInfo(of: fileClass))
        let imageInfo = try #require(image.objcClassInfo(of: imageClass))
        return (fileInfo, imageInfo)
    }

    @Test("File mode reads the properties a class keeps in another file")
    func readsPropertiesFromAnotherFile() throws {
        let probe = try #require(CrossFileRelativeListProbe.system)
        let (fileInfo, imageInfo) = try Self.classInfos(named: probe.propertyListClassName)

        #expect(!imageInfo.properties.isEmpty)
        #expect(fileInfo.properties.map(\.name) == imageInfo.properties.map(\.name))
    }

    @Test("File mode reads the protocols a class keeps in another file")
    func readsProtocolsFromAnotherFile() throws {
        let probe = try #require(CrossFileRelativeListProbe.system)
        let (fileInfo, imageInfo) = try Self.classInfos(named: probe.protocolListClassName)

        #expect(!imageInfo.protocols.isEmpty)
        #expect(fileInfo.protocols.map(\.name) == imageInfo.protocols.map(\.name))
    }
}
