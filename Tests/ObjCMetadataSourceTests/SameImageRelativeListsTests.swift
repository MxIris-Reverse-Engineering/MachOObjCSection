import Testing
import Foundation
import MachOKit
import MachOKitExtensions
@testable import MachOObjCSection
import ObjCDump
import ObjCMetadataSource

/// A class of the running system's dyld cache whose relative list of method
/// lists carries more than one entry for the class's own image, with the names
/// of every method those entries hold, list after list. `nil` when no class of
/// UniformTypeIdentifiers has that shape, which gates the suite off: on macOS
/// 26.7 `_UTCoreType` is the only class of the whole cache that has it.
private struct SameImageRelativeMethodListsProbe: Sendable {
    static let imageName = "UniformTypeIdentifiers"
    static let imagePath = "/System/Library/Frameworks/UniformTypeIdentifiers.framework/UniformTypeIdentifiers"

    let cacheURL: URL
    let className: String
    let expectedMethodNames: [String]

    static let system: SameImageRelativeMethodListsProbe? = try? make()

    private static func make() throws -> SameImageRelativeMethodListsProbe? {
        guard let cacheURL = DyldCache.host?.url else { return nil }
        let cache = try DyldCache(url: cacheURL)
        guard let machO = cache.machOFile(by: .name(imageName)),
              let imageIndex = machO.objcImageIndex
        else { return nil }

        for objcClass in machO.objc.classes64 ?? [] {
            guard let readOnlyData = objcClass.classROData(in: machO),
                  let relativeListList = readOnlyData.methodRelativeListList(in: machO)
            else { continue }
            let ownEntries = relativeListList.entries(in: machO).filter { $0.imageIndex == imageIndex }
            guard ownEntries.count > 1,
                  let className = machO.objcClassName(of: objcClass)
            else { continue }
            let expectedMethodNames = ownEntries.flatMap { entry in
                guard let (listMachO, list) = relativeListList.list(in: machO, for: entry) else { return [String]() }
                return list.methods(in: listMachO)?.map(\.name) ?? []
            }
            return SameImageRelativeMethodListsProbe(
                cacheURL: cacheURL,
                className: className,
                expectedMethodNames: expectedMethodNames
            )
        }
        return nil
    }
}

/// A class's relative list of lists can hold more than one entry for the same
/// image — two categories that `ld` did not merge into the class, for one.
/// The reader took only the first entry carrying the image's index, so such a
/// class lost every method of the lists after it, in file mode and image mode
/// alike. Upstream p-x9/MachOObjCSection fixed it in `ff936fa` (0.8.2).
@Suite(
    "Relative lists an image attaches more than once",
    .enabled(if: SameImageRelativeMethodListsProbe.system != nil)
)
struct SameImageRelativeListsTests {
    @Test("File mode reads every method list the class's own image attaches")
    func fileModeReadsEveryOwnList() throws {
        let probe = try #require(SameImageRelativeMethodListsProbe.system)
        let file = try #require(
            try DyldCache(url: probe.cacheURL).machOFile(by: .name(SameImageRelativeMethodListsProbe.imageName))
        )
        let fileClass = try #require(file.objc.classes64?.first { file.objcClassName(of: $0) == probe.className })
        let fileInfo = try #require(file.objcClassInfo(of: fileClass))

        #expect(fileInfo.methods.map(\.name) == probe.expectedMethodNames)
    }

    @Test("Image mode reads every method list the class's own image attaches")
    func imageModeReadsEveryOwnList() throws {
        let probe = try #require(SameImageRelativeMethodListsProbe.system)
        let handle = try #require(dlopen(SameImageRelativeMethodListsProbe.imagePath, RTLD_LAZY))
        defer { dlclose(handle) }
        let image = try #require(MachOImage(name: SameImageRelativeMethodListsProbe.imageName))
        let imageClass = try #require(image.objc.classes64?.first { image.objcClassName(of: $0) == probe.className })
        let imageInfo = try #require(image.objcClassInfo(of: imageClass))

        #expect(imageInfo.methods.map(\.name) == probe.expectedMethodNames)
    }
}
