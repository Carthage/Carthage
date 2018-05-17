//
// Created by Werner Altewischer on 24/01/2018.
// Copyright (c) 2018 Carthage. All rights reserved.
//

import Foundation
import XCTest
@testable import CarthageKit

class ConcreteVersionTest: XCTestCase {
	
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
            "1234567890abcdef",
			"fedcba0987654321",
        ]

        let shuffledVersions = versions.shuffled()
        var set = SortedSet<ConcreteVersion>()

        for versionString in shuffledVersions {
            let pinnedVersion = PinnedVersion(versionString)
            XCTAssertTrue(set.insert(ConcreteVersion(pinnedVersion: pinnedVersion)))
        }

        let orderedVersions = Array(set).map { return $0.pinnedVersion.commitish }

        XCTAssertEqual(versions, orderedVersions)
    }

	func testConcreteVersionComparison() {
		var v1 = ConcreteVersion(string: "1.0.0")
		var v2 = ConcreteVersion(string: "1.1.0")

		XCTAssertTrue(v2 < v1)
		XCTAssertTrue(v1 > v2)
		XCTAssertTrue(v2 <= v1)
		XCTAssertTrue(v1 >= v2)

		v1 = ConcreteVersion(string: "aap")
		v2 = ConcreteVersion(string: "1.0.0")

		XCTAssertTrue(v2 < v1)
		XCTAssertTrue(v1 > v2)
		XCTAssertTrue(v2 <= v1)
		XCTAssertTrue(v1 >= v2)
	}

    func testRetainVersions() {

        let versions = [
            "3.10.0",
            "2.2.1",
            "2.1.5",
            "2.0.0",
            "1.5.2",
            "1.4.9",
            "1.0.0",
			"0.8.0",
            "0.5.2",
            "0.5.0",
            "0.4.10",
            "0.0.5",
            "0.0.1",
            "1234567890abcdef",
			"fedcba0987654321",
        ]

        let set = ConcreteVersionSet()

        for versionString in versions {
            XCTAssertTrue(set.insert(ConcreteVersion(string: versionString)))
        }

        var set1 = set.copy

        set1.retainVersions(compatibleWith: VersionSpecifier.any)

        XCTAssertEqual(Array(set), Array(set1))

		set1 = set.copy

        set1.retainVersions(compatibleWith: VersionSpecifier.gitReference("aap"))

        XCTAssertEqual(Array(set), Array(set1))

		set1 = set.copy

        set1.retainVersions(compatibleWith: VersionSpecifier.atLeast(SemanticVersion(major: 1, minor: 0, patch: 0)))

        XCTAssertEqual([
			ConcreteVersion(string: "3.10.0"),
			ConcreteVersion(string: "2.2.1"),
			ConcreteVersion(string: "2.1.5"),
			ConcreteVersion(string: "2.0.0"),
            ConcreteVersion(string: "1.5.2"),
            ConcreteVersion(string: "1.4.9"),
            ConcreteVersion(string: "1.0.0"),
            ConcreteVersion(string: "1234567890abcdef"),
			ConcreteVersion(string: "fedcba0987654321"),
        ], Array(set1))

		set1 = set.copy

		set1.retainVersions(compatibleWith: VersionSpecifier.atLeast(SemanticVersion(major: 1, minor: 0, patch: 1)))

		XCTAssertEqual([
			ConcreteVersion(string: "3.10.0"),
			ConcreteVersion(string: "2.2.1"),
			ConcreteVersion(string: "2.1.5"),
			ConcreteVersion(string: "2.0.0"),
			ConcreteVersion(string: "1.5.2"),
			ConcreteVersion(string: "1.4.9"),
			ConcreteVersion(string: "1234567890abcdef"),
			ConcreteVersion(string: "fedcba0987654321"),
		], Array(set1))

		set1 = set.copy

		set1.retainVersions(compatibleWith: VersionSpecifier.atLeast(SemanticVersion(major: 0, minor: 9, patch: 0)))

		XCTAssertEqual([
			ConcreteVersion(string: "3.10.0"),
			ConcreteVersion(string: "2.2.1"),
			ConcreteVersion(string: "2.1.5"),
			ConcreteVersion(string: "2.0.0"),
			ConcreteVersion(string: "1.5.2"),
			ConcreteVersion(string: "1.4.9"),
			ConcreteVersion(string: "1.0.0"),
			ConcreteVersion(string: "1234567890abcdef"),
			ConcreteVersion(string: "fedcba0987654321"),
		], Array(set1))


		set1 = set.copy

		set1.retainVersions(compatibleWith: VersionSpecifier.compatibleWith(SemanticVersion(major: 1, minor: 0, patch: 0)))

		XCTAssertEqual([
			ConcreteVersion(string: "1.5.2"),
			ConcreteVersion(string: "1.4.9"),
			ConcreteVersion(string: "1.0.0"),
			ConcreteVersion(string: "1234567890abcdef"),
			ConcreteVersion(string: "fedcba0987654321"),
		], Array(set1))

		set1 = set.copy

		set1.retainVersions(compatibleWith: VersionSpecifier.compatibleWith(SemanticVersion(major: 1, minor: 0, patch: 1)))

		XCTAssertEqual([
			ConcreteVersion(string: "1.5.2"),
			ConcreteVersion(string: "1.4.9"),
			ConcreteVersion(string: "1234567890abcdef"),
			ConcreteVersion(string: "fedcba0987654321"),
		], Array(set1))


		set1 = set.copy

		set1.retainVersions(compatibleWith: VersionSpecifier.compatibleWith(SemanticVersion(major: 0, minor: 5, patch: 0)))

		XCTAssertEqual([
			ConcreteVersion(string: "0.5.2"),
			ConcreteVersion(string: "0.5.0"),
			ConcreteVersion(string: "1234567890abcdef"),
			ConcreteVersion(string: "fedcba0987654321"),
		], Array(set1))

		set1 = set.copy

		set1.retainVersions(compatibleWith: VersionSpecifier.compatibleWith(SemanticVersion(major: 0, minor: 5, patch: 1)))

		XCTAssertEqual([
			ConcreteVersion(string: "0.5.2"),
			ConcreteVersion(string: "1234567890abcdef"),
			ConcreteVersion(string: "fedcba0987654321"),
		], Array(set1))

		set1 = set.copy

		set1.retainVersions(compatibleWith: VersionSpecifier.compatibleWith(SemanticVersion(major: 3, minor: 1, patch: 0)))

		XCTAssertEqual([
			ConcreteVersion(string: "3.10.0"),
			ConcreteVersion(string: "1234567890abcdef"),
			ConcreteVersion(string: "fedcba0987654321"),
		], Array(set1))

		set1 = set.copy

		set1.retainVersions(compatibleWith: VersionSpecifier.exactly(SemanticVersion(major: 0, minor: 5, patch: 0)))

		XCTAssertEqual([
			ConcreteVersion(string: "0.5.0"),
			ConcreteVersion(string: "1234567890abcdef"),
			ConcreteVersion(string: "fedcba0987654321"),
		], Array(set1))

		set1 = set.copy

		set1.retainVersions(compatibleWith: VersionSpecifier.exactly(SemanticVersion(major: 0, minor: 5, patch: 1)))

		XCTAssertEqual([
			ConcreteVersion(string: "1234567890abcdef"),
			ConcreteVersion(string: "fedcba0987654321"),
		], Array(set1))
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
