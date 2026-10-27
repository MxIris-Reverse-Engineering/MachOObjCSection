import Testing
import Foundation
import MachOKit
import MachOObjCSection
import ObjCDump

/// Two images built from the same Objective-C source in `Fixtures/`, one for
/// arm64_32 (watchOS) and one for arm64 (macOS). Their linker emits every
/// method list in the relative format, each name an offset to a selector
/// reference, and encodes those references as chained fixups: a slot holds the
/// selector's address together with the distance to the next fixup.
@Suite("Selector references of relative method lists")
struct RelativeMethodListSelectorTests {
    enum Fixture: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case thirtyTwoBit = "ObjCSection32BitFixture"
        case sixtyFourBit = "ObjCSection64BitFixture"

        var testDescription: String {
            switch self {
            case .thirtyTwoBit: "arm64_32"
            case .sixtyFourBit: "arm64"
            }
        }
    }

    enum FixtureError: Swift.Error {
        case notASingleArchitectureFile
        case classNotFound
    }

    private static func classInfo(of fixture: Fixture) throws -> ObjCClassInfo {
        let url = try #require(Bundle.module.url(forResource: "lib\(fixture.rawValue)", withExtension: "dylib"))
        guard case .machO(let machO) = try MachOKit.loadFromFile(url: url) else {
            throw FixtureError.notASingleArchitectureFile
        }
        let classInfos = (machO.objc.classes64 ?? []).compactMap { $0.info(in: machO) }
            + (machO.objc.classes32 ?? []).compactMap { $0.info(in: machO) }
        guard let classInfo = classInfos.first(where: { $0.name == fixture.rawValue }) else {
            throw FixtureError.classNotFound
        }
        return classInfo
    }

    @Test("Instance method names are read", arguments: Fixture.allCases)
    func readsInstanceMethodNames(fixture: Fixture) throws {
        let classInfo = try Self.classInfo(of: fixture)
        #expect(
            Set(classInfo.methods.map(\.name))
                == ["fixtureValue", "setFixtureValue:", "fixtureDescriptionWithPrefix:suffix:"]
        )
    }

    @Test("Class method names are read", arguments: Fixture.allCases)
    func readsClassMethodNames(fixture: Fixture) throws {
        let classInfo = try Self.classInfo(of: fixture)
        #expect(classInfo.classMethods.map(\.name) == ["fixtureWithValue:"])
    }
}
