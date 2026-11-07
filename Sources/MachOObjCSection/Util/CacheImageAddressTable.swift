//
//  CacheImageAddressTable.swift
//  MachOObjCSection
//

import Foundation

/// The images of a dyld cache by the address ranges of their segments, for
/// finding the image an address lies in without walking every image.
///
/// A cache holds thousands of images — about four thousand on macOS 27 — and
/// the walk this replaces built each of them and compared every segment, once
/// for every protocol, class and category pointer read out of the cache.
///
/// The table is a list of disjoint ranges sorted by start, each naming the
/// image the walk answers for every address in it: the first image, in the
/// walk's order, one of whose segments contains the address. Where segments
/// of several images overlap — every image of a cache maps the same
/// `__LINKEDIT` — the range belongs to the image listed first.
struct CacheImageAddressTable<Image> {
    private let rangeStarts: [UInt64]
    private let rangeEnds: [UInt64]
    private let rangeImages: [Image]

    /// - Parameters:
    ///   - images: The images in the order the walk visits them.
    ///   - segmentRanges: The address ranges of an image's segments.
    init(images: some Sequence<Image>, segmentRanges: (Image) -> [Range<UInt64>]) {
        var orderedImages: [Image] = []
        var segmentRangesInWalkOrder: [(range: Range<UInt64>, imageOrder: Int)] = []
        var boundarySet: Set<UInt64> = []
        for image in images {
            let imageOrder = orderedImages.count
            orderedImages.append(image)
            for range in segmentRanges(image) where !range.isEmpty {
                segmentRangesInWalkOrder.append((range, imageOrder))
                boundarySet.insert(range.lowerBound)
                boundarySet.insert(range.upperBound)
            }
        }
        let boundaries = boundarySet.sorted()
        let elementaryRangeCount = max(boundaries.count - 1, 0)

        // The image owning each elementary range — between two consecutive
        // boundaries — painted in the walk's order, so the first image to
        // reach a range keeps it.
        var ownerImageOrders = [Int?](repeating: nil, count: elementaryRangeCount)
        // The next unpainted elementary range at or after each index, with
        // path compression, so a segment overlapping painted ones — the shared
        // `__LINKEDIT` of every image — repaints nothing. The last entry is
        // the end sentinel.
        var nextUnpaintedIndexes = Array(0 ... elementaryRangeCount)
        func nextUnpaintedIndex(from startIndex: Int) -> Int {
            var rootIndex = startIndex
            while nextUnpaintedIndexes[rootIndex] != rootIndex {
                rootIndex = nextUnpaintedIndexes[rootIndex]
            }
            var currentIndex = startIndex
            while nextUnpaintedIndexes[currentIndex] != rootIndex {
                let followingIndex = nextUnpaintedIndexes[currentIndex]
                nextUnpaintedIndexes[currentIndex] = rootIndex
                currentIndex = followingIndex
            }
            return rootIndex
        }
        for (range, imageOrder) in segmentRangesInWalkOrder {
            let endIndex = Self.index(of: range.upperBound, in: boundaries)
            var index = nextUnpaintedIndex(from: Self.index(of: range.lowerBound, in: boundaries))
            while index < endIndex {
                ownerImageOrders[index] = imageOrder
                nextUnpaintedIndexes[index] = index + 1
                index = nextUnpaintedIndex(from: index + 1)
            }
        }

        // Adjacent elementary ranges of one image merge into one range.
        var rangeStarts: [UInt64] = []
        var rangeEnds: [UInt64] = []
        var rangeImageOrders: [Int] = []
        for index in 0 ..< elementaryRangeCount {
            guard let ownerImageOrder = ownerImageOrders[index] else { continue }
            if rangeImageOrders.last == ownerImageOrder, rangeEnds.last == boundaries[index] {
                rangeEnds[rangeEnds.count - 1] = boundaries[index + 1]
            } else {
                rangeStarts.append(boundaries[index])
                rangeEnds.append(boundaries[index + 1])
                rangeImageOrders.append(ownerImageOrder)
            }
        }
        self.rangeStarts = rangeStarts
        self.rangeEnds = rangeEnds
        self.rangeImages = rangeImageOrders.map { orderedImages[$0] }
    }

    /// The image the walk answers for `address`, or `nil` when no image's
    /// segment contains it.
    func image(containing address: UInt64) -> Image? {
        // The last range starting at or before the address.
        var lowerIndex = 0
        var upperIndex = rangeStarts.count
        while lowerIndex < upperIndex {
            let middleIndex = (lowerIndex + upperIndex) / 2
            if rangeStarts[middleIndex] <= address {
                lowerIndex = middleIndex + 1
            } else {
                upperIndex = middleIndex
            }
        }
        let rangeIndex = lowerIndex - 1
        guard rangeIndex >= 0, address < rangeEnds[rangeIndex] else { return nil }
        return rangeImages[rangeIndex]
    }

    /// The position of `boundary` in the sorted, duplicate-free `boundaries`,
    /// which holds it.
    private static func index(of boundary: UInt64, in boundaries: [UInt64]) -> Int {
        var lowerIndex = 0
        var upperIndex = boundaries.count
        while lowerIndex < upperIndex {
            let middleIndex = (lowerIndex + upperIndex) / 2
            if boundaries[middleIndex] < boundary {
                lowerIndex = middleIndex + 1
            } else {
                upperIndex = middleIndex
            }
        }
        return lowerIndex
    }
}
