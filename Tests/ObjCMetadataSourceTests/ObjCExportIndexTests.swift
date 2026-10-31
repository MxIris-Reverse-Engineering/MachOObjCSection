import Testing
import Foundation
import MachOKit
import MachOKitExtensions
import MachOObjCSection
import ObjCDump
import ObjCMetadataSource
import ObjectiveC

/// The symbol spellings under test, written out here rather than reached for
/// through the implementation: a test that borrowed the constant it is
/// checking would pass just as happily with the wrong one.
private enum ExportSymbolSpelling {
    static let objcClassPrefix = "_OBJC_CLASS_$_"
    static let objcIvarPrefix = "_OBJC_IVAR_$_"
    static let swiftClassMetadataSuffix = "CN"
}

/// A framework that is certain to be loaded in the test process, carries a
/// large Objective-C surface, and mixes public and internal classes.
private func loadedFoundationImage() throws -> MachOImage {
    try #require(MachOImage(name: "Foundation"), "Foundation is not loaded in the test process")
}

/// Every class record of an image, 64-bit and 32-bit lists both, lazy and
/// non-lazy both — the same union `ObjCInterfaceIndexer` walks.
private func allClassRecords<MachO: ObjCMetadataSource>(in machO: MachO) -> [any ObjCClassProtocol] {
    (machO.objc.classes64 ?? []) as [any ObjCClassProtocol]
        + ((machO.objc.classes32 ?? []) as [any ObjCClassProtocol])
        + ((machO.objc.nonLazyClasses64 ?? []) as [any ObjCClassProtocol])
        + ((machO.objc.nonLazyClasses32 ?? []) as [any ObjCClassProtocol])
}

/// Every class record of an image by its name.
private func classRecordsByName<MachO: ObjCMetadataSource>(in machO: MachO) -> [String: any ObjCClassProtocol] {
    var classRecordsByName: [String: any ObjCClassProtocol] = [:]
    for classRecord in allClassRecords(in: machO) {
        guard let className = machO.objcClassName(of: classRecord) else { continue }
        classRecordsByName[className] = classRecord
    }
    return classRecordsByName
}

/// The running system's dyld shared cache, whichever architecture this machine
/// is. `nil` when there is none to read, which gates the cache tests off
/// rather than failing them.
private func systemDyldSharedCachePath() -> String? {
    ["arm64e", "x86_64h", "x86_64"]
        .map { "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_\($0)" }
        .first { FileManager.default.fileExists(atPath: $0) }
}

/// Foundation as read out of the shared cache **as a file** — the `MachOFile`
/// path, which reaches the export trie through an entirely different route
/// than the in-process `MachOImage` one.
private func foundationFileInSharedCache() throws -> MachOFile {
    let cachePath = try #require(systemDyldSharedCachePath())
    let cache = try FullDyldCache(url: URL(fileURLWithPath: cachePath))
    return try #require(
        cache.machOFiles().first { $0.imagePath.hasSuffix("/Foundation") },
        "no Foundation image in the shared cache"
    )
}

@Suite("ObjC export index")
struct ObjCExportIndexTests {

    // MARK: - Symbol Spelling

    /// Pins the one assumption the whole index rests on: MachOKit hands back
    /// export trie labels verbatim, so the names carry the linker's leading
    /// underscore. If a MachOKit release ever starts stripping it, every
    /// prefix match would silently miss and every clang class would read as
    /// `notExported` — a wrong answer delivered confidently, with no crash
    /// and no empty result to notice.
    @Test("Export trie symbol names carry the linker's leading underscore")
    func exportTrieSymbolNamesCarryLeadingUnderscore() throws {
        let foundation = try loadedFoundationImage()
        let exportedNames = Set(foundation.exportedSymbols.map(\.name))

        #expect(exportedNames.contains("\(ExportSymbolSpelling.objcClassPrefix)NSString"))
        #expect(!exportedNames.contains("OBJC_CLASS_$_NSString"))
    }

    // MARK: - Verdict Spread

    /// A real framework must produce *both* verdicts. All-exported means the
    /// symbol filter matched something it should not have, or the negative
    /// branch is unreachable; all-unexported means the locations never line
    /// up. Either way the index would be useless while still returning
    /// plausible-looking values, which is exactly what a count-based check
    /// catches and a spot-check does not.
    @Test("A real framework yields both exported and unexported classes")
    func realFrameworkYieldsBothVerdicts() throws {
        let foundation = try loadedFoundationImage()
        let exportIndex = ObjCExportIndex(machO: foundation)

        var exportedCount = 0
        var notExportedCount = 0
        var noInformationCount = 0

        for classRecord in allClassRecords(in: foundation) {
            switch exportIndex.exportStatus(ofClassObjectAt: classRecord.offset) {
            case .exported: exportedCount += 1
            case .notExported: notExportedCount += 1
            case .imageHasNoExportInformation: noInformationCount += 1
            }
        }

        #expect(exportedCount > 0, "no class of Foundation read as exported")
        #expect(notExportedCount > 0, "no class of Foundation read as unexported")
        #expect(noInformationCount == 0, "Foundation must have export information")
    }

    /// Classes Foundation itself exports.
    @Test("Known public classes are exported")
    func knownPublicClassesAreExported() throws {
        let foundation = try loadedFoundationImage()
        let exportIndex = ObjCExportIndex(machO: foundation)
        let classRecords = classRecordsByName(in: foundation)

        for className in ["NSString", "NSError", "NSBundle"] {
            let classRecord = try #require(classRecords[className], "Foundation lists no \(className)")
            #expect(exportIndex.exportStatus(ofClassObjectAt: classRecord.offset) == .exported, "\(className)")
        }
    }

    // MARK: - Address Cross-Checks

    /// The premise of judging by location: an exported `_OBJC_CLASS_$_` symbol
    /// sits **at the class record's own address**. It fails if two different
    /// offset conventions got mixed, which a check of the verdicts alone would
    /// not notice — they were built from the same symbols.
    @Test("An exported class symbol sits at that class record's own address")
    func exportedClassSymbolSitsAtClassRecordAddress() throws {
        let foundation = try loadedFoundationImage()

        var symbolOffsetByClassName: [String: Int] = [:]
        for exportedSymbol in foundation.exportedSymbols
        where exportedSymbol.name.hasPrefix(ExportSymbolSpelling.objcClassPrefix) {
            guard let symbolOffset = exportedSymbol.offset else { continue }
            let className = String(
                exportedSymbol.name.dropFirst(ExportSymbolSpelling.objcClassPrefix.count)
            )
            symbolOffsetByClassName[className] = symbolOffset
        }

        var comparedCount = 0
        for (className, classRecord) in classRecordsByName(in: foundation) {
            guard let symbolOffset = symbolOffsetByClassName[className] else { continue }
            #expect(
                symbolOffset == classRecord.offset,
                "class \(className): export trie says \(symbolOffset), class record is at \(classRecord.offset)"
            )
            comparedCount += 1
        }

        #expect(comparedCount > 0, "nothing was cross-checked")
    }

    /// Where the Objective-C spelling exists the verdict is the one it gives,
    /// and where only the location says exported, the class is a Swift one
    /// published by its type metadata symbol — the one kind of class the
    /// spelling misses. Holds the verdict to the symbols from both sides
    /// instead of rebuilding it from them.
    @Test("A class reads exported exactly when its Objective-C symbol or its Swift metadata symbol is exported")
    func classVerdictFollowsItsPublishingSymbol() throws {
        let foundation = try loadedFoundationImage()
        let exportIndex = ObjCExportIndex(machO: foundation)

        var exportedObjectiveCClassNames: Set<String> = []
        var exportedSwiftClassMetadataOffsets: Set<Int> = []
        for exportedSymbol in foundation.exportedSymbols {
            if exportedSymbol.name.hasPrefix(ExportSymbolSpelling.objcClassPrefix) {
                exportedObjectiveCClassNames.insert(String(exportedSymbol.name.dropFirst(ExportSymbolSpelling.objcClassPrefix.count)))
            } else if exportedSymbol.name.hasPrefix("_$s"),
                      exportedSymbol.name.hasSuffix(ExportSymbolSpelling.swiftClassMetadataSuffix),
                      let symbolOffset = exportedSymbol.offset {
                exportedSwiftClassMetadataOffsets.insert(symbolOffset)
            }
        }

        var exportedThroughObjectiveCSymbolCount = 0
        for (className, classRecord) in classRecordsByName(in: foundation) {
            let status = exportIndex.exportStatus(ofClassObjectAt: classRecord.offset)
            if exportedObjectiveCClassNames.contains(className) {
                #expect(status == .exported, "\(className) exports _OBJC_CLASS_$_ but reads \(status)")
                exportedThroughObjectiveCSymbolCount += 1
            } else if status == .exported {
                #expect(classRecord.isSwiftStable, "\(className) reads exported with no Objective-C symbol, and is no Swift class")
                #expect(
                    exportedSwiftClassMetadataOffsets.contains(classRecord.offset),
                    "\(className) reads exported with no symbol at its class object"
                )
            }
        }

        #expect(exportedThroughObjectiveCSymbolCount > 0, "nothing was cross-checked")
    }

    // MARK: - Ivars

    /// Runs the ivar claim backwards: take every `_OBJC_IVAR_$_<class>.<ivar>`
    /// the trie exports, split it, and require that the image really does
    /// declare that ivar on *that* class. It fails if `ObjCClassInfo.ivars`
    /// turned out to include inherited ivars (the symbol belongs to the
    /// declaring class, so the mapping would not line up).
    ///
    /// Only symbols whose class this image also defines are checked — a
    /// framework can export an ivar offset for a class that lives elsewhere.
    @Test("Every exported ivar symbol names an ivar its class actually declares")
    func exportedIvarSymbolsNameDeclaredIvars() throws {
        let foundation = try loadedFoundationImage()

        var declaredIvarNamesByClassName: [String: Set<String>] = [:]
        for (className, classRecord) in classRecordsByName(in: foundation) {
            guard let classInfo = foundation.objcClassInfo(of: classRecord) else { continue }
            declaredIvarNamesByClassName[className] = Set(classInfo.ivars.map(\.name))
        }

        var checkedCount = 0
        for exportedSymbol in foundation.exportedSymbols
        where exportedSymbol.name.hasPrefix(ExportSymbolSpelling.objcIvarPrefix) {
            guard let (className, ivarName) = Self.classAndIvarName(ofIvarSymbolNamed: exportedSymbol.name),
                  let declaredIvarNames = declaredIvarNamesByClassName[className]
            else { continue }
            #expect(
                declaredIvarNames.contains(ivarName),
                "\(className) exports an offset for ivar \(ivarName) but does not declare it"
            )
            checkedCount += 1
        }

        #expect(checkedCount > 0, "no exported ivar symbol was cross-checked")
    }

    /// The premise of judging an ivar by location: the exported
    /// `_OBJC_IVAR_$_<class>.<ivar>` sits exactly where that ivar's record
    /// points, and the verdict read there is `exported`. It fails if the
    /// pointer is read from the wrong field, resolved into another offset
    /// convention, or keyed under another ivar's name.
    @Test("An exported ivar symbol sits at the offset variable of the ivar it names")
    func exportedIvarSymbolSitsAtItsOffsetVariable() throws {
        let foundation = try loadedFoundationImage()
        let exportIndex = ObjCExportIndex(machO: foundation)
        let classRecords = classRecordsByName(in: foundation)

        var checkedCount = 0
        for exportedSymbol in foundation.exportedSymbols
        where exportedSymbol.name.hasPrefix(ExportSymbolSpelling.objcIvarPrefix) {
            guard let (className, ivarName) = Self.classAndIvarName(ofIvarSymbolNamed: exportedSymbol.name),
                  let classRecord = classRecords[className],
                  let symbolOffset = exportedSymbol.offset
            else { continue }
            let offsetVariableOffset = foundation.objcIvarOffsetVariableOffsets(of: classRecord)[ivarName]
            #expect(offsetVariableOffset == symbolOffset, "\(className).\(ivarName)")
            #expect(exportIndex.exportStatus(ofIvarOffsetVariableAt: symbolOffset) == .exported, "\(className).\(ivarName)")
            checkedCount += 1
        }

        #expect(checkedCount > 0, "no exported ivar symbol was cross-checked")
    }

    /// Splits `_OBJC_IVAR_$_<class>.<ivar>` on the first `.`: neither an ObjC
    /// class name nor a Swift mangled runtime name contains one.
    private static func classAndIvarName(ofIvarSymbolNamed symbolName: String) -> (className: String, ivarName: String)? {
        let qualifiedName = symbolName.dropFirst(ExportSymbolSpelling.objcIvarPrefix.count)
        guard let separatorIndex = qualifiedName.firstIndex(of: ".") else { return nil }
        return (
            String(qualifiedName[qualifiedName.startIndex..<separatorIndex]),
            String(qualifiedName[qualifiedName.index(after: separatorIndex)...])
        )
    }

    // MARK: - dyld Shared Cache, File Mode

    /// The one that decides whether this feature is worth anything to a host
    /// reading cache images as files.
    ///
    /// `MachOFile` reaches the export trie by a completely different route
    /// than `MachOImage`: for an image inside the shared cache the linkedit
    /// segment is not in the file at all, and MachOKit has to redirect the
    /// read through the cache's own segments
    /// (`MachOFile._fileSliceForLinkEditData`). If that redirect ever fails,
    /// the trie reads as empty and every class of every cache image comes back
    /// ``ObjCExportStatus/imageHasNoExportInformation``.
    @Test(
        "A dyld shared cache image yields export information in file mode",
        .enabled(if: systemDyldSharedCachePath() != nil)
    )
    func cacheImageYieldsExportInformationInFileMode() throws {
        let foundationFile = try foundationFileInSharedCache()
        let exportIndex = ObjCExportIndex(machO: foundationFile)
        let classRecords = classRecordsByName(in: foundationFile)

        for className in ["NSString", "NSError"] {
            let classRecord = try #require(classRecords[className], "Foundation lists no \(className)")
            #expect(exportIndex.exportStatus(ofClassObjectAt: classRecord.offset) == .exported, "\(className)")
        }
    }

    /// The same image judged both ways must agree on every class and every
    /// ivar. The two modes count offsets from different places — the image's
    /// header in process, the main cache's start in a file — so this is what
    /// catches a conversion between the export trie's offsets and a mode's
    /// own that is off. It compares whole verdict sets, so a mode that quietly
    /// returns "no information" for everything cannot pass by being trivially
    /// consistent with itself.
    @Test(
        "File mode and image mode agree on every class and every ivar",
        .enabled(if: systemDyldSharedCachePath() != nil)
    )
    func fileModeAndImageModeAgreeOnEveryClassAndIvar() throws {
        let foundationImage = try loadedFoundationImage()
        let foundationFile = try foundationFileInSharedCache()

        let imageExportIndex = ObjCExportIndex(machO: foundationImage)
        let fileExportIndex = ObjCExportIndex(machO: foundationFile)
        let fileClassRecords = classRecordsByName(in: foundationFile)

        var comparedClassCount = 0
        var exportedClassCount = 0
        var comparedIvarCount = 0
        var exportedIvarCount = 0
        for (className, imageClassRecord) in classRecordsByName(in: foundationImage) {
            guard let fileClassRecord = fileClassRecords[className] else {
                Issue.record("class \(className) is listed in the image but not in the file")
                continue
            }
            let fromImage = imageExportIndex.exportStatus(ofClassObjectAt: imageClassRecord.offset)
            let fromFile = fileExportIndex.exportStatus(ofClassObjectAt: fileClassRecord.offset)
            #expect(fromImage == fromFile, "class \(className) differs between modes")
            if fromImage == .exported { exportedClassCount += 1 }
            comparedClassCount += 1

            let imageIvarStatuses = foundationImage.objcIvarOffsetVariableOffsets(of: imageClassRecord)
                .mapValues(imageExportIndex.exportStatus(ofIvarOffsetVariableAt:))
            let fileIvarStatuses = foundationFile.objcIvarOffsetVariableOffsets(of: fileClassRecord)
                .mapValues(fileExportIndex.exportStatus(ofIvarOffsetVariableAt:))
            #expect(imageIvarStatuses == fileIvarStatuses, "ivars of \(className) differ between modes")
            comparedIvarCount += imageIvarStatuses.count
            exportedIvarCount += imageIvarStatuses.values.count { $0 == .exported }
        }

        #expect(comparedClassCount > 0, "no class was compared")
        #expect(exportedClassCount > 0, "both modes agreed on no class being exported")
        #expect(comparedIvarCount > 0, "no ivar was compared")
        #expect(exportedIvarCount > 0, "both modes agreed on no ivar being exported")
    }
}
