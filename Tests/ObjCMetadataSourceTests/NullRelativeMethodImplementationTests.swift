import Testing
import Foundation
import MachOKit
import MachOKitExtensions
import MachOObjCSection

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

private func methodLists(of protocolRecord: ObjCProtocol64, in machO: MachOImage) -> [ObjCMethodList] {
    [
        protocolRecord.instanceMethodList(in: machO),
        protocolRecord.classMethodList(in: machO),
        protocolRecord.optionalInstanceMethodList(in: machO),
        protocolRecord.optionalClassMethodList(in: machO),
    ]
    .compactMap { $0 }
}

/// A protocol of Foundation, in the running system's dyld cache, that declares
/// methods and keeps every one of its method lists in a relative format. `nil`
/// when there is none, which gates the suite off: in a pointer-format list a
/// method without an implementation already holds a null `IMP`.
private struct RelativeProtocolMethodListProbe: Sendable {
    static let imageName = "Foundation"

    let cacheURL: URL
    let protocolName: String

    static let system: RelativeProtocolMethodListProbe? = try? make()

    private static func make() throws -> RelativeProtocolMethodListProbe? {
        guard let cacheURL = DyldCache.host?.url else { return nil }
        let cache = try DyldCache(url: cacheURL)
        guard let machO = cache.machOFile(by: .name(imageName)) else { return nil }

        for protocolRecord in machO.objc.protocols64 ?? [] {
            let lists = methodLists(of: protocolRecord, in: machO)
            guard !lists.isEmpty,
                  lists.allSatisfy({ $0.listKind != .pointer && $0.count > 0 })
            else { continue }
            return RelativeProtocolMethodListProbe(
                cacheURL: cacheURL,
                protocolName: protocolRecord.mangledName(in: machO)
            )
        }
        return nil
    }
}

/// A relative method entry stores its implementation as an offset from its own
/// `imp` field, and a method without one — every method a protocol declares —
/// stores 0 there. The reader added that 0 to the field's position, so such a
/// method read as implemented at its own `imp` field: the entry's position plus
/// 8 in file mode, the field's address in image mode. The IMP comments printed
/// those addresses for protocol methods, and the cross-reference layer mapped
/// them to method names. Upstream p-x9/MachOObjCSection fixed it in `322c86b`
/// and `9a18d38` (0.9.0).
@Suite(
    "A relative method without an implementation has a null IMP",
    .enabled(if: RelativeProtocolMethodListProbe.system != nil)
)
struct NullRelativeMethodImplementationTests {
    @Test("File mode reads a protocol's methods with IMP 0")
    func fileModeReadsNullImplementation() throws {
        let probe = try #require(RelativeProtocolMethodListProbe.system)
        let file = try #require(
            try DyldCache(url: probe.cacheURL).machOFile(by: .name(RelativeProtocolMethodListProbe.imageName))
        )
        let protocolRecord = try #require(file.objc.protocols64?.first { $0.mangledName(in: file) == probe.protocolName })
        let methods = methodLists(of: protocolRecord, in: file).flatMap { $0.methods(in: file) ?? [] }

        try #require(!methods.isEmpty)
        #expect(methods.allSatisfy { $0.imp == 0 }, "\(probe.protocolName): \(methods.filter { $0.imp != 0 }.map(\.name))")
    }

    @Test("Image mode reads a protocol's methods with IMP 0")
    func imageModeReadsNullImplementation() throws {
        let probe = try #require(RelativeProtocolMethodListProbe.system)
        let image = try #require(
            MachOImage(name: RelativeProtocolMethodListProbe.imageName),
            "Foundation is not loaded in the test process"
        )
        let protocolRecord = try #require(image.objc.protocols64?.first { $0.mangledName(in: image) == probe.protocolName })
        let methods = methodLists(of: protocolRecord, in: image).flatMap { $0.methods(in: image) }

        try #require(!methods.isEmpty)
        #expect(methods.allSatisfy { $0.imp == 0 }, "\(probe.protocolName): \(methods.filter { $0.imp != 0 }.map(\.name))")
    }
}
