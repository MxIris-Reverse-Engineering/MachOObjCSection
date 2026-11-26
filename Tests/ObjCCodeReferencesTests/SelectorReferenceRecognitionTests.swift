import Foundation
import Testing
import MachOKit
import MachOFixtureSupport
@_spi(Internals) import MachOCodeReferences
@_spi(Internals) import ObjCCodeReferences

/// A selector code loads but sends nothing with is a selector reference: an
/// argument to `respondsToSelector:` or `performSelector:`, a return value.
/// A send's own selector is not (evolution proposal
/// `cross-reference-recall-gaps`, MachOSwiftSection).
@Suite(.enabled(if: SelectorProbe.isSupported, "the probe is compiled for arm64 macOS"))
struct SelectorReferenceRecognitionTests {
    @Test(arguments: SelectorProbe.SendForm.allCases)
    func respondsToSelectorArgumentIsASelectorReference(sendForm: SelectorProbe.SendForm) throws {
        let scan = try SelectorProbe.scan(sendForm: sendForm, findsSelectorReferences: true)
        #expect(try scan.selectorReferences(inFunctionNamed: "_probeRespondsToSelector") == ["coalescingNodeObserver:openSyncCompleted:"])
        // The entry point still stands for the send it is.
        #expect(try scan.sends(inFunctionNamed: "_probeRespondsToSelector") == ["respondsToSelector:"])
    }

    @Test(arguments: SelectorProbe.SendForm.allCases)
    func aReturnedSelectorIsASelectorReference(sendForm: SelectorProbe.SendForm) throws {
        let scan = try SelectorProbe.scan(sendForm: sendForm, findsSelectorReferences: true)
        #expect(try scan.selectorReferences(inFunctionNamed: "_probeReturnsSelector") == ["name"])
    }

    @Test(arguments: SelectorProbe.SendForm.allCases)
    func aSelectorHandedToPerformSelectorIsASelectorReference(sendForm: SelectorProbe.SendForm) throws {
        let scan = try SelectorProbe.scan(sendForm: sendForm, findsSelectorReferences: true)
        #expect(try scan.selectorReferences(inFunctionNamed: "_probePerformsSelector") == ["copy"])
        #expect(try scan.sends(inFunctionNamed: "_probePerformsSelector") == ["performSelector:"])
    }

    /// A classic send loads its selector reference into `x1`; a stub loads it
    /// in the stub. Neither leaves a selector reference behind.
    @Test(arguments: SelectorProbe.SendForm.allCases)
    func aSendLeavesNoSelectorReferenceBehind(sendForm: SelectorProbe.SendForm) throws {
        let scan = try SelectorProbe.scan(sendForm: sendForm, findsSelectorReferences: true)
        #expect(try scan.selectorReferences(inFunctionNamed: "_probeSendsDescription").isEmpty)
        #expect(try scan.sends(inFunctionNamed: "_probeSendsDescription") == ["description"])
    }

    @Test(arguments: SelectorProbe.SendForm.allCases)
    func selectorReferencesAreRecordedOnlyWhenAskedFor(sendForm: SelectorProbe.SendForm) throws {
        let scan = try SelectorProbe.scan(sendForm: sendForm, findsSelectorReferences: false)
        #expect(scan.recording.selectorReferences.isEmpty)
        #expect(try scan.sends(inFunctionNamed: "_probeSendsDescription") == ["description"])
    }
}

/// A small Objective-C library, compiled once per send form: with the
/// selector stubs clang emits by default (`objc_msgSend$description`), and
/// with classic sends that load the selector reference into `x1` before
/// calling `objc_msgSend`.
enum SelectorProbe {
    enum SendForm: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case selectorStubs
        case classic

        var testDescription: String { rawValue }

        fileprivate var arguments: [String] {
            switch self {
            case .selectorStubs: []
            case .classic: ["-fno-objc-msgsend-selector-stubs"]
            }
        }
    }

    static let isSupported: Bool = {
        #if os(macOS) && arch(arm64)
        true
        #else
        false
        #endif
    }()

    static let source = """
    #import <Foundation/Foundation.h>

    @interface SelectorProbe : NSObject
    - (void)coalescingNodeObserver:(id)observer openSyncCompleted:(id)completed;
    @end

    @implementation SelectorProbe
    - (void)coalescingNodeObserver:(id)observer openSyncCompleted:(id)completed {}
    @end

    BOOL probeRespondsToSelector(id object) {
        return [object respondsToSelector:@selector(coalescingNodeObserver:openSyncCompleted:)];
    }

    SEL probeReturnsSelector(void) {
        return @selector(name);
    }

    id probePerformsSelector(id object) {
        return [object performSelector:@selector(copy)];
    }

    id probeSendsDescription(id object) {
        return [object description];
    }

    """

    struct Scan {
        let machO: MachOFile
        let recording: SelectorRecording

        private func functionRange(_ name: String) throws -> Range<UInt64> {
            guard let text = machO.sections64.first(where: { $0.segmentName == "__TEXT" && $0.sectionName == "__text" }),
                  let symbol = machO.symbols.first(where: { $0.name == name })
            else { throw ProbeLookupError(description: "no \(name) in __text") }
            let textRange = UInt64(text.address) ..< UInt64(text.address + text.size)
            let start = UInt64(symbol.offset)
            let laterStarts = machO.symbols.map { UInt64($0.offset) }.filter { $0 > start && textRange.contains($0) }
            return start ..< (laterStarts.min() ?? textRange.upperBound)
        }

        func selectorReferences(inFunctionNamed name: String) throws -> [String] {
            let range = try functionRange(name)
            return recording.selectorReferences.filter { range.contains($0.instructionAddress) }.map(\.selector)
        }

        func sends(inFunctionNamed name: String) throws -> [String] {
            let range = try functionRange(name)
            return recording.sends.filter { range.contains($0.instructionAddress) }.map(\.selector)
        }
    }

    static func scan(sendForm: SendForm, findsSelectorReferences: Bool) throws -> Scan {
        let libraryURL = try FixtureCompiler.shared.dynamicLibrary(
            named: "SelectorProbe\(sendForm.rawValue.prefix(1).uppercased())\(sendForm.rawValue.dropFirst())",
            language: .c,
            sourceFiles: [FixtureSourceFile(name: "SelectorProbe.m", contents: source)],
            arguments: ["-O2", "-framework", "Foundation"] + sendForm.arguments
        )
        let machO = try HostSlice.machOFile(at: libraryURL)
        let images = CodeImageSet.files(
            [machO],
            rules: RuntimeLibraryRules(isRuntimeLibrary: ObjCRuntimeFunctions.isRuntimeLibrary, isRuntimeHelperName: { _ in false }),
            visitingRuntimeLibrarySymbols: { _, _ in }
        )
        let recognizer = ObjCCodeReferenceRecognizer(images: images, runtimeFunctions: ObjCRuntimeFunctions())
        let table = images.transientFunctionTable(ofImageAt: 0)
        let recording = SelectorRecording()
        let session = recognizer.makeSession(table: table, recording: recording, findsClassReferences: false, findsSelectorReferences: findsSelectorReferences)
        var scanner = ReferenceScanner(images: images, table: table, sessions: [session], recording: recording)
        for index in table.starts.indices {
            scanner.scanFunction(at: index)
        }
        return Scan(machO: machO, recording: recording)
    }
}

struct ProbeLookupError: Error, CustomStringConvertible {
    let description: String
}

/// Keeps the sends and the selector references a scan records.
final class SelectorRecording: ObjCCodeReferenceRecording {
    private(set) var sends: [(selector: String, instructionAddress: UInt64)] = []
    private(set) var selectorReferences: [(selector: String, instructionAddress: UInt64)] = []

    func recordMessageSend(selector: String, receiver: ReceiverClassHint, at site: ScanSite) {
        sends.append((selector, site.instructionAddress))
    }

    func recordSuperMessageSend(selector: String, className: String?, at site: ScanSite) {
        sends.append((selector, site.instructionAddress))
    }

    func recordClassReference(_ classObject: ObjectiveCClassObject, at site: ScanSite) {}
    func recordInstanceVariableReference(className: String, name: String, at site: ScanSite) {}

    func recordSelectorReference(selector: String, at site: ScanSite) {
        selectorReferences.append((selector, site.instructionAddress))
    }

    func recordCall(to target: ResolvedCallTarget, targetAddress: UInt64, at site: ScanSite, isRuntimeHelperCall: Bool) {}
    func recordIndirectCall(_ evidence: IndirectCallEvidence, at site: ScanSite) {}
    func recordString(_ string: StringLiteralReference, at site: ScanSite) {}
    func recordImportedSymbolReference(named name: String, at site: ScanSite) {}
    func recordFunctionAddressReference(to function: CodeLocation, at site: ScanSite) {}
}
