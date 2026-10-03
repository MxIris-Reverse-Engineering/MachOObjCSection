import Testing
import Foundation
import MachOKit
import MachOKitExtensions
import MachOObjCSection
import ObjCDeclarationRendering
import ObjCIndexing
import ObjCInterface

/// An archived macOS arm64e dyld shared cache, addressed by OS version.
///
/// The archive volume holds one directory per release. The caches are several
/// gigabytes each, far too large to vendor, so every test reading one skips
/// when its cache is absent.
private enum ArchivedMacOSCache {
    static func path(version: String) -> String {
        "/Volumes/DyldSharedCaches/macOS/\(version)/dyld_shared_cache_arm64e"
    }

    static func isPresent(version: String) -> Bool {
        FileManager.default.fileExists(atPath: path(version: version))
    }

    /// The image the way the command line tools open it: the cache file, then
    /// the image looked up by name.
    static func image(named imageName: String, version: String) throws -> MachOFile {
        let cache = try DyldCache(url: URL(fileURLWithPath: path(version: version)))
        return try #require(
            cache.machOFile(by: .name(imageName)),
            "no \(imageName) image in the macOS \(version) cache"
        )
    }
}

/// One image of one archived cache whose protocols carry pointer-format
/// method lists.
struct ArchivedCacheImage: Sendable, CustomTestStringConvertible {
    let version: String
    let imageName: String

    var testDescription: String { "\(imageName) in macOS \(version)" }
}

/// Every method list a protocol record declares, in the order the runtime
/// keeps them.
private func methodLists(of protocolRecord: ObjCProtocol64, in machO: MachOFile) -> [ObjCMethodList] {
    [
        protocolRecord.instanceMethodList(in: machO),
        protocolRecord.classMethodList(in: machO),
        protocolRecord.optionalInstanceMethodList(in: machO),
        protocolRecord.optionalClassMethodList(in: machO),
    ]
    .compactMap { $0 }
}

private func allMethods(of protocolRecord: ObjCProtocol64, in machO: MachOFile) -> [ObjCMethod] {
    methodLists(of: protocolRecord, in: machO).flatMap { $0.methods(in: machO) ?? [] }
}

private func protocolRecord(named protocolName: String, in machO: MachOFile) throws -> ObjCProtocol64 {
    let protocolRecords = try #require(machO.objc.protocols64, "the image has no protocol list")
    return try #require(
        protocolRecords.first { $0.mangledName(in: machO) == protocolName },
        "the image defines no protocol \(protocolName)"
    )
}

/// Pointer-format method lists (`method_t { SEL name; const char *types; IMP imp; }`)
/// read out of a dyld shared cache.
///
/// In a cache, a pointer slot does not hold an address: it holds the encoding
/// of its mapping's slide info. Slide info v3 (arm64e caches through macOS
/// 14.3) keeps the target address in the low 51 bits and the distance to the
/// next fixup above them; slide info v5 (macOS 14.4 on) keeps an offset from
/// the cache start instead of an address. The reader used to take the raw slot
/// for an address. On a v3 cache that lost every name; on a v5 cache a slot
/// that ends its page's fixup chain is a bare offset below the shared region
/// start, so subtracting the region start overflowed and trapped, taking the
/// whole process down with no message.
///
/// Protocol method lists are the pointer-format lists these caches still ship:
/// nearly every protocol's through macOS 15.3, only a few from 15.4 on
/// (CoreFoundation's `NSCopying`). No cache a CI runner carries reaches this
/// path — the macOS 26 and 27 caches hold no pointer-format protocol method
/// lists, and a standalone Mach-O file is never read through slide info — so
/// these tests guard the fix only where the archive volume is mounted.
@Suite("Pointer-format method lists in a dyld shared cache")
struct DyldCachePointerMethodListTests {
    /// The images whose protocols carry pointer-format method lists, one per
    /// cache layout: slide info v3, slide info v5 before most protocol lists
    /// turned relative, and slide info v5 after.
    static let pointerListImages: [ArchivedCacheImage] = [
        .init(version: "14.3.1", imageName: "Foundation"),
        .init(version: "15.0", imageName: "Foundation"),
        .init(version: "15.4.1", imageName: "CoreFoundation"),
    ]

    static var presentPointerListImages: [ArchivedCacheImage] {
        pointerListImages.filter { ArchivedMacOSCache.isPresent(version: $0.version) }
    }

    /// The trap the report came with. The types slot of this method is the
    /// last fixup of its page, stored as the bare cache offset `0x24B0EDE`.
    @Test(
        "A slide info v5 slot ending its fixup chain resolves instead of trapping",
        .enabled(if: ArchivedMacOSCache.isPresent(version: "15.0"))
    )
    func slideInfoV5ChainEndSlotResolves() throws {
        let foundation = try ArchivedMacOSCache.image(named: "Foundation", version: "15.0")
        let listenerDelegate = try protocolRecord(named: "NSXPCListenerDelegate", in: foundation)

        let methods = allMethods(of: listenerDelegate, in: foundation)
        #expect(methods.map { "\($0.name) \($0.types)" } == ["listener:shouldAcceptNewConnection: B32@0:8@16@24"])
    }

    /// A slide info v3 slot carries the distance to the next fixup in its high
    /// bits, which made every lookup of the raw value miss.
    @Test(
        "Slide info v3 slots resolve to their names and type encodings",
        .enabled(if: ArchivedMacOSCache.isPresent(version: "14.3.1"))
    )
    func slideInfoV3SlotsResolve() throws {
        let foundation = try ArchivedMacOSCache.image(named: "Foundation", version: "14.3.1")
        let coding = try protocolRecord(named: "NSCoding", in: foundation)

        let methods = allMethods(of: coding, in: foundation)
        #expect(methods.map { "\($0.name) \($0.types)" }.sorted() == [
            "encodeWithCoder: v24@0:8@16",
            "initWithCoder: @24@0:8@16",
        ])
    }

    @Test(
        "Every protocol method of the image resolves a name and a type encoding",
        .enabled(if: !presentPointerListImages.isEmpty),
        arguments: presentPointerListImages
    )
    func everyProtocolMethodResolves(_ archivedImage: ArchivedCacheImage) throws {
        let machO = try ArchivedMacOSCache.image(named: archivedImage.imageName, version: archivedImage.version)
        let protocolRecords = try #require(machO.objc.protocols64, "the image has no protocol list")

        var pointerListCount = 0
        var unresolvedMethods: [String] = []
        for protocolRecord in protocolRecords {
            let protocolName = protocolRecord.mangledName(in: machO)
            for methodList in methodLists(of: protocolRecord, in: machO) {
                if methodList.listKind == .pointer {
                    pointerListCount += 1
                }
                for method in methodList.methods(in: machO) ?? [] where method.name.isEmpty || method.types.isEmpty {
                    unresolvedMethods.append("\(protocolName): name \"\(method.name)\", types \"\(method.types)\"")
                }
            }
        }

        // The premise: the image still exercises the pointer-format reader.
        try #require(pointerListCount > 0, "no pointer-format protocol method list left in \(archivedImage.testDescription)")
        #expect(unresolvedMethods.isEmpty, "\(unresolvedMethods.count) methods did not resolve:\n\(unresolvedMethods.joined(separator: "\n"))")
    }

    /// From macOS 15.4 on nothing traps, but the few pointer-format lists left
    /// are those of protocols nearly every class adopts. With their names
    /// unread, `stripProtocolConformance` kept every member they declare.
    @Test(
        "stripProtocolConformance drops what a pointer-format protocol declares",
        .enabled(if: ArchivedMacOSCache.isPresent(version: "15.4.1"))
    )
    func stripProtocolConformanceDropsPointerListProtocolMembers() async throws {
        let foundation = try ArchivedMacOSCache.image(named: "Foundation", version: "15.4.1")
        let indexer = ObjCInterfaceIndexer(machO: foundation, imagePath: foundation.imagePath)
        try await indexer.prepare()
        let builder = ObjCInterfaceBuilder(indexer: indexer, machO: foundation)

        var strippingOptions = ObjCGenerationOptions.default
        strippingOptions.stripProtocolConformance = true
        let plain = try #require(builder.classInterface(named: "NSString")).string
        let stripped = try #require(builder.classInterface(named: "NSString", options: strippingOptions)).string

        for selector in ["copyWithZone:", "mutableCopyWithZone:"] {
            // The premise: NSString implements the member, so there is something to strip.
            try #require(plain.contains("\(selector)("), "NSString does not declare \(selector)\n\(plain)")
            #expect(!stripped.contains("\(selector)("), "\(selector) survived stripping\n\(stripped)")
        }
    }
}
