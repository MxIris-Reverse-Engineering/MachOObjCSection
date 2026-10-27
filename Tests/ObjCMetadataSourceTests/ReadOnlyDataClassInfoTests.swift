import Testing
import Foundation
import MachOKit
import MachOKitExtensions
@testable import MachOObjCSection
import ObjCDump
import ObjCMetadataSource
import ObjectiveC

/// A class without a class object in the image — a generic Swift class, or
/// one registered through `__objc_stublist` — is read from its `class_ro_t`
/// alone, at an offset the host supplies (proposal "host-supplied classes").
/// The reader assembles the information the way `ObjCClassProtocol.info(in:options:)`
/// does, in code appended to the upstream file rather than shared with it, so
/// these tests hold the two equal over every class and category of real
/// images: if upstream changes how a class is read, they fail first.
@Suite("Classes and categories read without a class object")
struct ReadOnlyDataClassInfoTests {
    // MARK: - Classes

    @Test("A class reads the same from its class_ro_t alone in file mode", arguments: ReadOnlyDataFixture.FileImage.allCases)
    func classReadsTheSameInFileMode(image: ReadOnlyDataFixture.FileImage) throws {
        let machO = try image.machOFile()
        var comparedCount = 0
        for objcClass in machO.objc.classes64 ?? [] {
            guard let expected = objcClass.info(in: machO, options: .headerDump) else { continue }
            let readOnlyData = try #require(objcClass.classROData(in: machO))
            let (metaclassImage, metaclass) = try #require(objcClass.metaClass(in: machO))
            #expect(metaclassImage.imagePath == machO.imagePath)
            let metaclassReadOnlyData = try #require(metaclass.classROData(in: metaclassImage))

            let actual = try #require(
                machO.objcClassInfo(
                    readOnlyDataOffset: readOnlyData.offset,
                    metaclassReadOnlyDataOffset: metaclassReadOnlyData.offset,
                    name: expected.name,
                    superClassName: expected.superClassName,
                    options: .headerDump
                )
            )
            #expect(actual.info.droppingIvars(named: actual.ivarNamesWithUnknownOffset) == expected, "\(expected.name)")
            comparedCount += 1
        }
        #expect(comparedCount > 0)
    }

    /// Image mode reads the version a realized class's runtime data records,
    /// which `class_setVersion` writes; the `class_ro_t` holds none, so the
    /// version is left out of the comparison.
    @Test("A class reads the same from its class_ro_t alone in image mode", arguments: ReadOnlyDataFixture.LoadedImage.allCases)
    func classReadsTheSameInImageMode(image: ReadOnlyDataFixture.LoadedImage) throws {
        let machO = try image.machOImage()
        var comparedCount = 0
        for objcClass in machO.objc.classes64 ?? [] {
            guard let expected = objcClass.info(in: machO, options: .headerDump),
                  let (metaclassImage, metaclass) = objcClass.metaClass(in: machO),
                  metaclassImage.ptr == machO.ptr
            else { continue }
            let readOnlyData = try #require(ReadOnlyDataFixture.readOnlyData(of: objcClass, in: machO))
            let metaclassReadOnlyData = try #require(ReadOnlyDataFixture.readOnlyData(of: metaclass, in: machO))

            let actual = try #require(
                machO.objcClassInfo(
                    readOnlyDataOffset: readOnlyData.offset,
                    metaclassReadOnlyDataOffset: metaclassReadOnlyData.offset,
                    name: expected.name,
                    superClassName: expected.superClassName,
                    options: .headerDump
                )
            )
            #expect(
                actual.info.droppingIvars(named: actual.ivarNamesWithUnknownOffset)
                    == expected.replacingVersion(with: actual.info.version),
                "\(expected.name)"
            )
            comparedCount += 1
        }
        #expect(comparedCount > 0)
    }

    /// The sweeps above read only the names of the adopted protocols.
    @Test("Referenced protocols expand the same way")
    func referencedProtocolsExpandTheSameWay() throws {
        let machO = try ReadOnlyDataFixture.FileImage.foundationInDyldCache.machOFile()
        let classesWithProtocols = (machO.objc.classes64 ?? []).lazy.compactMap { objcClass -> (ObjCClass64, ObjCClassInfo)? in
            guard let expected = objcClass.info(in: machO), !expected.protocols.isEmpty else { return nil }
            return (objcClass, expected)
        }
        var comparedCount = 0
        for (objcClass, expected) in classesWithProtocols.prefix(20) {
            let readOnlyData = try #require(objcClass.classROData(in: machO))
            let (metaclassImage, metaclass) = try #require(objcClass.metaClass(in: machO))
            let metaclassReadOnlyData = try #require(metaclass.classROData(in: metaclassImage))
            let actual = try #require(
                machO.objcClassInfo(
                    readOnlyDataOffset: readOnlyData.offset,
                    metaclassReadOnlyDataOffset: metaclassReadOnlyData.offset,
                    name: expected.name,
                    superClassName: expected.superClassName
                )
            )
            #expect(actual.info.protocols == expected.protocols, "\(expected.name)")
            comparedCount += 1
        }
        #expect(comparedCount > 0)
    }

    @Test("Without the metaclass's class_ro_t a class reads no class members")
    func noMetaclassMeansNoClassMembers() throws {
        let machO = try ReadOnlyDataFixture.FileImage.testBundle.machOFile()
        let objcClass = try #require(
            machO.objc.classes64?.first { machO.objcClassName(of: $0) == "ObjCMetadataSourceFixtureHost" }
        )
        let expected = try #require(objcClass.info(in: machO))
        let readOnlyData = try #require(objcClass.classROData(in: machO))

        let actual = try #require(
            machO.objcClassInfo(
                readOnlyDataOffset: readOnlyData.offset,
                metaclassReadOnlyDataOffset: nil,
                name: "Supplied",
                superClassName: "SuppliedSuperclass"
            )
        )
        #expect(actual.info.name == "Supplied")
        #expect(actual.info.superClassName == "SuppliedSuperclass")
        #expect(actual.info.methods == expected.methods)
        #expect(actual.info.properties == expected.properties)
        #expect(actual.info.ivars == expected.ivars)
        #expect(actual.info.classMethods.isEmpty)
        #expect(actual.info.classProperties.isEmpty)
    }

    @Test("Nothing is read where no class_ro_t fits")
    func nothingIsReadOutsideTheImage() throws {
        let file = try ReadOnlyDataFixture.FileImage.testBundle.machOFile()
        let fileSize = try #require(
            try FileManager.default.attributesOfItem(atPath: file.url.path)[.size] as? Int
        )
        #expect(ObjCClassROData64(offset: -8, in: file) == nil)
        #expect(ObjCClassROData64(offset: fileSize, in: file) == nil)
        #expect(file.objcClassInfo(readOnlyDataOffset: fileSize, metaclassReadOnlyDataOffset: nil, name: "Unreadable", superClassName: nil) == nil)

        let image = try ReadOnlyDataFixture.LoadedImage.testBundle.machOImage()
        let offsetOfAddressZero = -Int(bitPattern: image.ptr)
        #expect(ObjCClassROData64(offset: offsetOfAddressZero, in: image) == nil)
        #expect(image.objcClassInfo(readOnlyDataOffset: offsetOfAddressZero, metaclassReadOnlyDataOffset: nil, name: "Unreadable", superClassName: nil) == nil)
    }

    // MARK: - Categories

    @Test("A category reads the same under its own class's name in file mode", arguments: ReadOnlyDataFixture.FileImage.allCases)
    func categoryReadsTheSameInFileMode(image: ReadOnlyDataFixture.FileImage) throws {
        let machO = try image.machOFile()
        let categories: [ObjCCategory64] = (machO.objc.categories64 ?? []) + (machO.objc.categories2_64 ?? [])
        var comparedCount = 0
        for category in categories {
            guard let expected = category.info(in: machO, options: .headerDump) else { continue }
            let actual = category.info(in: machO, className: expected.className, options: .headerDump)
            #expect(actual == expected, "\(expected.className)(\(expected.name))")
            comparedCount += 1
        }
        #expect(comparedCount > 0 || image == .testBundle)
    }

    @Test("A category reads the same under its own class's name in image mode", arguments: ReadOnlyDataFixture.LoadedImage.allCases)
    func categoryReadsTheSameInImageMode(image: ReadOnlyDataFixture.LoadedImage) throws {
        let machO = try image.machOImage()
        let categories: [ObjCCategory64] = (machO.objc.categories64 ?? []) + (machO.objc.categories2_64 ?? [])
        var comparedCount = 0
        for category in categories {
            guard let expected = category.info(in: machO, options: .headerDump) else { continue }
            let actual = category.info(in: machO, className: expected.className, options: .headerDump)
            #expect(actual == expected, "\(expected.className)(\(expected.name))")
            comparedCount += 1
        }
        #expect(comparedCount > 0 || image == .testBundle)
    }
}

/// The images the comparisons run over: Foundation, from the running
/// system's dyld cache and loaded in this process, and this test bundle,
/// a standalone file that is loaded too.
enum ReadOnlyDataFixture {
    enum FixtureError: Swift.Error {
        case imageUnavailable(String)
    }

    enum FileImage: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case foundationInDyldCache
        case testBundle

        var testDescription: String {
            switch self {
            case .foundationInDyldCache: "Foundation in the dyld cache"
            case .testBundle: "the test bundle"
            }
        }

        func machOFile() throws -> MachOFile {
            switch self {
            case .foundationInDyldCache:
                guard let cacheURL = DyldCache.host?.url,
                      let machO = try DyldCache(url: cacheURL).machOFile(by: .name("Foundation")) else {
                    throw FixtureError.imageUnavailable("Foundation in the host's dyld cache")
                }
                return machO
            case .testBundle:
                let image = try LoadedImage.testBundle.machOImage()
                switch try MachOKit.loadFromFile(url: URL(fileURLWithPath: try ReadOnlyDataFixture.testBundlePath())) {
                case .machO(let machO):
                    return machO
                case .fat(let fatFile):
                    guard let machO = try fatFile.machOFiles().first(where: { $0.header.cpu == image.header.cpu }) else {
                        throw FixtureError.imageUnavailable("the test bundle's \(image.header.cpu) slice")
                    }
                    return machO
                }
            }
        }
    }

    enum LoadedImage: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case foundation
        case testBundle

        var testDescription: String {
            switch self {
            case .foundation: "Foundation"
            case .testBundle: "the test bundle"
            }
        }

        func machOImage() throws -> MachOImage {
            switch self {
            case .foundation:
                guard let image = MachOImage(name: "Foundation") else {
                    throw FixtureError.imageUnavailable("Foundation loaded in this process")
                }
                return image
            case .testBundle:
                let imagePath = try ReadOnlyDataFixture.testBundlePath()
                let imageName = (imagePath as NSString).lastPathComponent
                guard let image = MachOImage(name: imageName) ?? MachOImage.images.first(where: { $0.path == imagePath }) else {
                    throw FixtureError.imageUnavailable("the test bundle loaded in this process")
                }
                return image
            }
        }
    }

    /// The path the test bundle's binary was loaded from. `MachOImage.path`
    /// has none to give for it.
    static func testBundlePath() throws -> String {
        guard let imageNamePointer = class_getImageName(ObjCMetadataSourceFixtureHost.self) else {
            throw FixtureError.imageUnavailable("the test bundle's path")
        }
        return String(cString: imageNamePointer)
    }

    /// The `class_ro_t` of `objcClass`, wherever image mode keeps it: a
    /// realized class reaches it through its runtime data.
    static func readOnlyData(of objcClass: ObjCClass64, in image: MachOImage) -> ObjCClassROData64? {
        if let readOnlyData = objcClass.classROData(in: image) {
            return readOnlyData
        }
        guard let readWriteData = objcClass.classRWData(in: image) else { return nil }
        return readWriteData.classROData(in: image) ?? readWriteData.ext(in: image)?.classROData(in: image)
    }
}

extension ObjCClassInfo {
    /// This information without the ivars named in `ivarNames`, which
    /// `ObjCClassProtocol.info(in:options:)` drops for want of an offset.
    func droppingIvars(named ivarNames: Set<String>) -> ObjCClassInfo {
        guard !ivarNames.isEmpty else { return self }
        return ObjCClassInfo(
            name: name,
            version: version,
            imageName: imageName,
            instanceSize: instanceSize,
            superClassName: superClassName,
            protocols: protocols,
            ivars: ivars.filter { !ivarNames.contains($0.name) },
            classProperties: classProperties,
            properties: properties,
            classMethods: classMethods,
            methods: methods
        )
    }

    func replacingVersion(with version: Int32) -> ObjCClassInfo {
        ObjCClassInfo(
            name: name,
            version: version,
            imageName: imageName,
            instanceSize: instanceSize,
            superClassName: superClassName,
            protocols: protocols,
            ivars: ivars,
            classProperties: classProperties,
            properties: properties,
            classMethods: classMethods,
            methods: methods
        )
    }
}
