import Testing
import Foundation
import MachOKit
@testable import MachOObjCSection

/// `__objc_methlist` holds method lists back to back, each starting at the
/// section's alignment. Both iterators over it — the one reading a file's
/// bytes and the one reading an image's memory — get synthetic sections here,
/// so where every list starts is known exactly instead of read off a binary.
@Suite("Iterating __objc_methlist")
struct MethodListSectionIterationTests {
    enum Iterator: String, CaseIterable, Sendable {
        case file
        case image
    }

    /// Lists laid out the way a section declared with `alignmentExponent`
    /// (the section's `align` field, a power of two) spaces them.
    struct AlignedLayout: Sendable, CustomTestStringConvertible {
        let alignmentExponent: Int
        let listOffsets: [Int]
        let sectionSize: Int

        var testDescription: String { "aligned to 2^\(alignmentExponent)" }
    }

    /// A relative method list with one entry: the header — `entsizeAndFlags`
    /// carrying the relative flag and a 12-byte entry size, then the count —
    /// followed by one zeroed entry. 20 bytes.
    private static let singleEntryRelativeList: [UInt8] = {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: UInt32(0x8000_000C).littleEndian) { bytes += $0 }
        withUnsafeBytes(of: UInt32(1).littleEndian) { bytes += $0 }
        bytes += [UInt8](repeating: 0, count: 12)
        return bytes
    }()

    /// A zeroed section of `sectionSize` bytes with a single-entry list at
    /// each of `listOffsets`.
    private static func section(placingListsAt listOffsets: [Int], sectionSize: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: sectionSize)
        for listOffset in listOffsets {
            bytes.replaceSubrange(
                listOffset ..< listOffset + singleEntryRelativeList.count,
                with: singleEntryRelativeList
            )
        }
        return bytes
    }

    private static func listOffsets(
        in bytes: [UInt8],
        alignmentExponent: Int,
        readBy iterator: Iterator
    ) -> [Int] {
        switch iterator {
        case .file:
            let lists = MachOFile.ObjCMethodLists(
                data: Data(bytes),
                offset: 0,
                align: alignmentExponent,
                is64Bit: true
            )
            return lists.map(\.offset)
        case .image:
            return bytes.withUnsafeBytes { buffer in
                let lists = MachOImage.ObjCMethodLists(
                    offset: 0,
                    basePointer: buffer.baseAddress!,
                    tableSize: buffer.count,
                    align: alignmentExponent,
                    is64Bit: true
                )
                return lists.map(\.offset)
            }
        }
    }

    @Test("Every list of a section is read, up to its end", arguments: Iterator.allCases)
    func readsEveryList(iterator: Iterator) {
        let listOffsets = [0, 20, 40, 60, 80, 100]
        let bytes = Self.section(placingListsAt: listOffsets, sectionSize: 120)

        #expect(Self.listOffsets(in: bytes, alignmentExponent: 2, readBy: iterator) == listOffsets)
    }

    @Test(
        "Each list starts at the section's alignment",
        arguments: [
            AlignedLayout(alignmentExponent: 0, listOffsets: [0, 20, 40], sectionSize: 60),
            AlignedLayout(alignmentExponent: 4, listOffsets: [0, 32, 64], sectionSize: 84),
        ],
        Iterator.allCases
    )
    func listsStartAtSectionAlignment(layout: AlignedLayout, iterator: Iterator) {
        let bytes = Self.section(placingListsAt: layout.listOffsets, sectionSize: layout.sectionSize)

        #expect(
            Self.listOffsets(in: bytes, alignmentExponent: layout.alignmentExponent, readBy: iterator)
                == layout.listOffsets
        )
    }
}
