import Testing
import Foundation
import MachO
import MachOKit
import MachOObjCSection
import ObjectiveC

/// An ivar layout is a run of bytes, each a count of words to skip in the high
/// nibble and a count of strong words in the low one. A class with eight or
/// more non-pointer words before a strong ivar has a byte of 0x80 or more,
/// which is not valid UTF-8 on its own. `ObjCSection64BitIvarLayoutFixture`
/// in `Fixtures/ObjCSection64BitFixture.m` is such a class: eight `uint64_t`
/// ivars, then an `id`, so its layout is the single byte 0x81.
@Suite("Ivar layouts")
struct IvarLayoutTests {
    private static let fixtureClassName = "ObjCSection64BitIvarLayoutFixture"
    private static let expectedLayout: [UInt8] = [0x81]

    enum FixtureError: Swift.Error {
        case notASingleArchitectureFile
        case imageNotLoaded
    }

    private static func fixtureURL() throws -> URL {
        try #require(Bundle.module.url(forResource: "libObjCSection64BitFixture", withExtension: "dylib"))
    }

    @Test("A file's ivar layout keeps bytes of 0x80 and above")
    func fileLayoutKeepsHighBytes() throws {
        guard case .machO(let machO) = try MachOKit.loadFromFile(url: try Self.fixtureURL()) else {
            throw FixtureError.notASingleArchitectureFile
        }
        let fixtureClass = try #require(machO.objc.classes64?.first { $0.info(in: machO)?.name == Self.fixtureClassName })

        #expect(fixtureClass.classROData(in: machO)?.ivarLayout(in: machO) == Self.expectedLayout)
    }

    @Test("An image's ivar layout keeps bytes of 0x80 and above")
    func imageLayoutKeepsHighBytes() throws {
        let fixturePath = try Self.fixtureURL().resolvingSymlinksInPath().path
        try #require(dlopen(fixturePath, RTLD_NOW) != nil, "\(dlerror().map { String(cString: $0) } ?? "dlopen failed")")

        // The runtime's own reading confirms the fixture is what the test
        // takes it for.
        let runtimeClass = try #require(objc_getClass(Self.fixtureClassName) as? AnyClass)
        let runtimeLayout = try #require(class_getIvarLayout(runtimeClass))
        try #require(runtimeLayout.pointee == 0x81 && runtimeLayout.advanced(by: 1).pointee == 0)

        let image = try #require(Self.loadedImage(atPath: fixturePath))
        let fixtureClass = try #require(image.objc.classes64?.first { $0.info(in: image)?.name == Self.fixtureClassName })

        // Looking the class up above realized it: its data now points at the
        // runtime's read-write record, which leads on to the read-only one.
        let layout: [UInt8]? = if let readWriteData = fixtureClass.classRWData(in: image) {
            readWriteData.classROData(in: image)?.ivarLayout(in: image)
        } else {
            fixtureClass.classROData(in: image)?.ivarLayout(in: image)
        }
        #expect(layout == Self.expectedLayout)
    }

    private static func loadedImage(atPath path: String) -> MachOImage? {
        for index in 0 ..< _dyld_image_count() {
            guard let imageName = _dyld_get_image_name(index),
                  URL(fileURLWithPath: String(cString: imageName)).resolvingSymlinksInPath().path == path,
                  let header = _dyld_get_image_header(index) else {
                continue
            }
            return MachOImage(ptr: header)
        }
        return nil
    }
}
