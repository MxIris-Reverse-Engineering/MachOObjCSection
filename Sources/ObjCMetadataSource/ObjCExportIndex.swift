import Foundation
import MachOKit
import MachOKitExtensions

/// One image's Objective-C export symbol index: build it once, then ask it
/// about every class and ivar in that image.
///
/// ```swift
/// let exportIndex = ObjCExportIndex(machO: machO)
/// for objcClass in machO.objc.classes64 ?? [] {
///     let status = exportIndex.exportStatus(ofClassObjectAt: objcClass.offset)
///     // …mark the row
/// }
/// ```
///
/// `ObjCInterfaceIndexer` builds one during `prepare()` and keeps the verdict
/// of every class it lists; a host with an indexer asks it about a class
/// rather than this.
///
/// ## Judged by location
///
/// A verdict asks whether some exported symbol sits where the declaration
/// is — at the class object for a class, at the variable its record's offset
/// pointer points at for an ivar — because the two compilers that emit
/// Objective-C metadata name those places differently:
///
/// - clang publishes a class object under `_OBJC_CLASS_$_<name>` and an ivar's
///   offset variable under `_OBJC_IVAR_$_<class>.<ivar>`.
/// - Swift publishes a class object under its type metadata symbol `$s…CN`,
///   and adds an `_OBJC_CLASS_$_` alias at the same address only for a class
///   with an Objective-C ancestor (`emitObjCClassSymbol` in
///   `swift/lib/IRGen/GenMeta.cpp` runs only when `isObjC()`). A class rooted
///   in `Swift._SwiftObject` has no Objective-C symbol at all, yet sits in
///   `__objc_classlist` like any other. An ivar Swift emits — for a Swift
///   class, or for an `@objc @implementation` one — points at the field
///   offset `$s…Wvd` (`buildIvar` in `GenClass.cpp`), never at an
///   `_OBJC_IVAR_$_` symbol.
///
/// So the trie pass keeps the locations of all four kinds, and a lookup is a
/// set membership test on an offset. The superseded queries by name,
/// ``exportStatus(ofClassNamed:)`` and
/// ``exportStatus(ofIvarNamed:inClassNamed:)``, find only the clang spellings
/// and answer ``ObjCExportStatus/notExported`` for every exported Swift class
/// without an Objective-C ancestor and every exported ivar Swift emits.
///
/// ## Built for the whole-image sweep
///
/// The shape here follows the one consumption pattern this exists for:
/// labelling *every* class of an image, hundreds to thousands at a time. So
/// the cost is paid once in ``init(machO:)`` — a single pass over the export
/// trie — and every query after it is a hash lookup.
///
/// That is also why there is no `machO.objcExportStatus(of:)` convenience on
/// ``ObjCMetadataSource`` itself. Such a call would have to re-reach for
/// `exportTrie` each time (on a `MachOFile` that means walking the load
/// commands, which is file I/O) and walk the trie again — turning the sweep
/// into O(n) I/O. A shortcut whose only plausible use is the one that makes
/// it quadratic is better left unwritten.
///
/// ## Lifetime is the caller's
///
/// This is a value holding sets, so it is `Sendable` without ceremony: build
/// it on the background pass that indexes the image, read it from wherever
/// renders. There is no process-wide cache behind it — a host keeps it alive
/// alongside whatever else it holds for that image, and drops it with them.
public struct ObjCExportIndex: Sendable {
    /// The linker symbol clang publishes a class object under. Note the
    /// leading underscore: the export trie stores the linker's own spelling,
    /// and MachOKit hands the trie labels back verbatim.
    private static let classSymbolPrefix = "_OBJC_CLASS_$_"

    /// The linker symbol clang publishes an ivar's offset variable under,
    /// whose suffix is `<class name>.<ivar name>`.
    private static let ivarSymbolPrefix = "_OBJC_IVAR_$_"

    /// The suffix of a Swift class's type metadata symbol (`$s…CN`), which
    /// sits at the class object.
    ///
    /// Matched on the suffix alone: a symbol of another kind that happens to
    /// end this way is harmless, since only a symbol at a class object's exact
    /// location can affect a verdict, and one there publishes that object.
    private static let swiftClassMetadataSymbolSuffix = "CN"

    /// The suffix of a Swift field offset symbol (`$s…Wvd`), the variable an
    /// ivar Swift emits keeps its offset in. Matched on the suffix alone, for
    /// the same reason.
    private static let swiftFieldOffsetSymbolSuffix = "Wvd"

    /// Exported class names, prefix already stripped (`NSAlert`, not
    /// `_OBJC_CLASS_$_NSAlert`). Read only by the superseded
    /// ``exportStatus(ofClassNamed:)``.
    private let exportedClassNames: Set<String>

    /// Exported ivars keyed `<class name>.<ivar name>`, prefix stripped. Read
    /// only by the superseded ``exportStatus(ofIvarNamed:inClassNamed:)``.
    private let exportedIvarQualifiedNames: Set<String>

    /// Where an exported symbol publishes a class object, in the source's
    /// offset convention (the one `ObjCClassProtocol.offset` reads back).
    private let exportedClassObjectOffsets: Set<Int>

    /// Where an exported symbol publishes an ivar's offset variable, in the
    /// source's offset convention.
    private let exportedIvarOffsetVariableOffsets: Set<Int>

    /// Whether this image yielded any export information at all. Drives the
    /// ``ObjCExportStatus/imageHasNoExportInformation`` answer.
    private let hasExportInformation: Bool

    /// Walks the image's export trie once and keeps the entries that can
    /// publish a class object or an ivar's offset variable.
    ///
    /// ## Why the whole trie, and not a prefix search
    ///
    /// MachOKit offers `ExportTrie.search(byKeyPrefix:)`, which looks like
    /// exactly the right tool for "give me everything under
    /// `_OBJC_CLASS_$_`". It is not used, on correctness grounds:
    /// `TrieTreeProtocol._search(byKeyPrefix:)` descends with
    /// `children.first(where:)`, so once the prefix is consumed, if *several*
    /// children still begin with it, only one branch is taken and the rest are
    /// silently dropped. Whether it returns everything depends on the trie
    /// happening to have a node boundary right at the prefix — which the usual
    /// export-trie writers do produce, but "usually correct" is not something
    /// to build a verdict on. A missed branch would report a batch of exported
    /// classes as internal, with nothing to show for it. Two of the four
    /// kinds are told apart by a suffix, which no prefix search reaches anyway.
    ///
    /// A full pass costs one traversal per image (AppKit: 8774 entries in) and
    /// is what `MachOSwiftSection`'s `SymbolIndexStore` does for the same
    /// purpose.
    public init(machO: some ObjCMetadataSource) {
        let exportedSymbols = machO.exportedSymbols

        var exportedClassNames: Set<String> = []
        var exportedIvarQualifiedNames: Set<String> = []
        var classObjectSymbolOffsets: [Int] = []
        var ivarOffsetVariableSymbolOffsets: [Int] = []

        for exportedSymbol in exportedSymbols {
            let symbolName = exportedSymbol.name
            if symbolName.hasPrefix(Self.classSymbolPrefix) {
                exportedClassNames.insert(
                    String(symbolName.dropFirst(Self.classSymbolPrefix.count))
                )
                if let symbolOffset = exportedSymbol.offset {
                    classObjectSymbolOffsets.append(symbolOffset)
                }
            } else if symbolName.hasPrefix(Self.ivarSymbolPrefix) {
                exportedIvarQualifiedNames.insert(
                    String(symbolName.dropFirst(Self.ivarSymbolPrefix.count))
                )
                if let symbolOffset = exportedSymbol.offset {
                    ivarOffsetVariableSymbolOffsets.append(symbolOffset)
                }
            } else if symbolName.hasSuffix(Self.swiftClassMetadataSymbolSuffix) {
                if let symbolOffset = exportedSymbol.offset {
                    classObjectSymbolOffsets.append(symbolOffset)
                }
            } else if symbolName.hasSuffix(Self.swiftFieldOffsetSymbolSuffix) {
                if let symbolOffset = exportedSymbol.offset {
                    ivarOffsetVariableSymbolOffsets.append(symbolOffset)
                }
            }
        }

        // An empty result is treated as "no information", never as "nothing is
        // exported". The two are indistinguishable from here — a `.o` file
        // with no trie, a dyld shared cache image whose linkedit this reader
        // failed to reach, and a dylib genuinely built with an empty export
        // list all arrive as zero symbols — and the failure modes are wildly
        // asymmetric. Calling it "no information" costs a caller the ability
        // to judge an image that exports nothing, which is close to
        // hypothetical. Calling it "not exported" would silently label every
        // class in the image as internal, which is a wrong answer delivered
        // confidently.
        self.hasExportInformation = !exportedSymbols.isEmpty
        self.exportedClassNames = exportedClassNames
        self.exportedIvarQualifiedNames = exportedIvarQualifiedNames
        self.exportedClassObjectOffsets = Set(
            machO.objcOffsets(ofExportedSymbolOffsets: classObjectSymbolOffsets).compactMap(\.self)
        )
        self.exportedIvarOffsetVariableOffsets = Set(
            machO.objcOffsets(ofExportedSymbolOffsets: ivarOffsetVariableSymbolOffsets).compactMap(\.self)
        )
    }

    /// Whether an exported symbol publishes the class object at `offset`.
    ///
    /// `offset` is a class record's own, in the source's offset convention —
    /// what `ObjCClassProtocol.offset` reads back for a record this image
    /// lists. A record of another image counts from somewhere else, and its
    /// offset means nothing here.
    public func exportStatus(ofClassObjectAt offset: Int) -> ObjCExportStatus {
        exportStatus(at: offset, in: exportedClassObjectOffsets)
    }

    /// Whether an exported symbol publishes the ivar offset variable at
    /// `offset`.
    ///
    /// `offset` is where an ivar's record points, in the source's offset
    /// convention — what `ObjCMetadataSource.objcIvarOffsetVariableOffsets(of:)`
    /// reads.
    public func exportStatus(ofIvarOffsetVariableAt offset: Int) -> ObjCExportStatus {
        exportStatus(at: offset, in: exportedIvarOffsetVariableOffsets)
    }

    /// Whether `_OBJC_CLASS_$_<className>` is in the export trie **of the
    /// image this index was built from**.
    ///
    /// Only clang's spelling is looked for, so every exported Swift class
    /// without an Objective-C ancestor reads ``ObjCExportStatus/notExported``:
    /// Swift publishes it under its type metadata symbol alone. A class this
    /// image does not define reads the same, indistinguishable from one it
    /// keeps internal (`NSArray` asked of Foundation, which leaves it to
    /// CoreFoundation).
    @available(*, deprecated, message: "Misreads every Swift class without an Objective-C ancestor, which has no _OBJC_CLASS_$_ symbol; use ObjCInterfaceIndexer.exportStatus(ofClassNamed:) or exportStatus(ofClassObjectAt:)")
    public func exportStatus(ofClassNamed className: String) -> ObjCExportStatus {
        exportStatus(ofSymbolSuffix: className, in: exportedClassNames)
    }

    /// Whether `_OBJC_IVAR_$_<className>.<ivarName>` is in the image's export
    /// trie.
    ///
    /// Only clang's spelling is looked for, so every exported ivar Swift
    /// emits reads ``ObjCExportStatus/notExported``: its offset variable is a
    /// `$s…Wvd` field offset.
    @available(*, deprecated, message: "Misreads every ivar Swift emits, whose offset variable is a $s…Wvd field offset; use exportStatus(ofIvarOffsetVariableAt:) with ObjCMetadataSource.objcIvarOffsetVariableOffsets(of:)")
    public func exportStatus(
        ofIvarNamed ivarName: String,
        inClassNamed className: String
    ) -> ObjCExportStatus {
        exportStatus(
            ofSymbolSuffix: "\(className).\(ivarName)",
            in: exportedIvarQualifiedNames
        )
    }

    private func exportStatus(at offset: Int, in exportedOffsets: Set<Int>) -> ObjCExportStatus {
        guard hasExportInformation else { return .imageHasNoExportInformation }
        return exportedOffsets.contains(offset) ? .exported : .notExported
    }

    private func exportStatus(
        ofSymbolSuffix symbolSuffix: String,
        in exportedNames: Set<String>
    ) -> ObjCExportStatus {
        guard hasExportInformation else { return .imageHasNoExportInformation }
        return exportedNames.contains(symbolSuffix) ? .exported : .notExported
    }
}
