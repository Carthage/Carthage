//
// Created by Werner Altewischer on 24/01/2018.
// Copyright (c) 2018 Carthage. All rights reserved.
//

import Foundation
import XCTest
@testable import CarthageKit

class FastResolverTest: XCTestCase {

    func testSortedSet() {

        let set = SortedSet<String>()
        let array = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]
        let shuffledArray = array.shuffled()

        for s in shuffledArray {
            XCTAssertTrue(set.insertObject(s))
            XCTAssertFalse(set.insertObject(s))
        }

        let array1 = Array(set)

        XCTAssertEqual(array, array1)
        XCTAssertEqual(array.count, set.count)

        for s in shuffledArray {
            XCTAssertTrue(set.contains(s))
            XCTAssertTrue(set.removeObject(s))
            XCTAssertFalse(set.contains(s))
            XCTAssertFalse(set.removeObject(s))
        }

        XCTAssertEqual(0, set.count)
    }


    func testConcreteVersionOrdering() {
        let versions = [
            "3.10.0",
            "2.2.1",
            "2.1.5",
            "2.0.0",
            "1.5.2",
            "1.4.9",
            "1.0.0",
            "0.5.2",
            "0.5.0",
            "0.4.10",
            "0.0.5",
            "0.0.1",
            "fedcba0987654321",
            "1234567890abcdef",
        ]

        let shuffledVersions = versions.shuffled()
        let set = SortedSet<ConcreteVersion>()

        for versionString in shuffledVersions {
            let pinnedVersion = PinnedVersion(versionString)
            XCTAssertTrue(set.insertObject(ConcreteVersion(pinnedVersion: pinnedVersion)))
        }

        let orderedVersions = Array(set).map { return $0.pinnedVersion.commitish }

        XCTAssertEqual(versions, orderedVersions)
    }


}

private extension MutableCollection {
    /// Shuffles the contents of this collection.
    mutating func shuffle() {
        let c = count
        guard c > 1 else { return }

        for (firstUnshuffled, unshuffledCount) in zip(indices, stride(from: c, to: 1, by: -1)) {
            let d: IndexDistance = numericCast(arc4random_uniform(numericCast(unshuffledCount)))
            let i = index(firstUnshuffled, offsetBy: d)
            swapAt(firstUnshuffled, i)
        }
    }
}

private extension Sequence {
    /// Returns an array with the contents of this sequence, shuffled.
    func shuffled() -> [Element] {
        var result = Array(self)
        result.shuffle()
        return result
    }
}