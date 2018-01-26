//
// Created by Werner Altewischer on 24/01/2018.
// Copyright (c) 2018 Carthage. All rights reserved.
//

import Foundation
import XCTest
@testable import CarthageKit

class FastResolverTest: XCTestCase {
	
	let resolverType = FastResolver.self
	
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
            "1234567890abcdef",
			"fedcba0987654321",
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

        let set = SortedSet<ConcreteVersion>()

        for versionString in versions {
            XCTAssertTrue(set.insertObject(ConcreteVersion(string: versionString)))
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
	
	func testResolveSimpleCartfile() {
		let db: DB = [
			github1: [
				.v0_1_0: [
					github2: .compatibleWith(.v1_0_0),
				],
			],
			github2: [
				.v1_0_0: [:],
			],
			]
		
		let resolved = db.resolve(resolverType, [ github1: .exactly(.v0_1_0) ])
		
		switch resolved {
		case .success(let value):
			let expectedValue: [Dependency: PinnedVersion] = [
				github2: .v1_0_0,
				github1: .v0_1_0,
				]
			XCTAssertEqual(expectedValue, value)
		case .failure(let error):
			XCTFail("Unexpected error occurred: \(error)")
		}
	}
	
	func testResolveMatchingVersions() {
		let db: DB = [
			github1: [
				.v0_1_0: [
					github2: .compatibleWith(.v1_0_0),
				],
				.v1_0_0: [
					github2: .compatibleWith(.v2_0_0),
				],
				.v1_1_0: [
					github2: .compatibleWith(.v2_0_0),
				],
			],
			github2: [
				.v1_0_0: [:],
				.v2_0_0: [:],
				.v2_0_1: [:],
			],
			]
		
		let resolved = db.resolve(resolverType, [ github1: .any ])
		
		switch resolved {
		case .success(let value):
			let expectedValue: [Dependency: PinnedVersion] = [
				github2: .v2_0_1,
				github1: .v1_1_0,
			]
			XCTAssertEqual(expectedValue, value)
		case .failure(let error):
			XCTFail("Unexpected error occurred: \(error)")
		}
	}
	
	func testResolveSubSetWithGivenDependencies() {
		let db: DB = [
			github1: [
				.v1_0_0: [
					github2: .compatibleWith(.v1_0_0),
				],
				.v1_1_0: [
					github2: .compatibleWith(.v1_0_0),
				],
			],
			github2: [
				.v1_0_0: [ github3: .compatibleWith(.v1_0_0) ],
				.v1_1_0: [ github3: .compatibleWith(.v1_0_0) ],
			],
			github3: [
				.v1_0_0: [:],
				.v1_1_0: [:],
				.v1_2_0: [:],
			],
			git1: [
				.v1_0_0: [:],
			],
			]
		
		let resolved = db.resolve(resolverType,
								  [
									github1: .any,
									// Newly added dependencies which are not included in the
									// list should not be resolved.
									git1: .any,
									],
								  resolved: [ github1: .v1_0_0, github2: .v1_0_0, github3: .v1_0_0 ],
								  updating: [ github2 ]
		)
		
		switch resolved {
		case .success(let value):
			let expectedValue: [Dependency: PinnedVersion] = [
				github3: .v1_2_0,
				github2: .v1_1_0,
				github1: .v1_0_0,
			]
			XCTAssertEqual(expectedValue, value)
		case .failure(let error):
			XCTFail("Unexpected error occurred: \(error)")
		}
	}
	
	func testUpdateDependencyInRootListAndNestedWhenParentIsMarkedForUpdate() {
		let db: DB = [
			github1: [
				.v1_0_0: [
					git1: .compatibleWith(.v1_0_0)
				]
			],
			git1: [
				.v1_0_0: [:],
				.v1_1_0: [:]
			]
		]
		
		let resolved = db.resolve(resolverType,
								  [ github1: .any, git1: .any],
								  resolved: [ github1: .v1_0_0, git1: .v1_0_0 ],
								  updating: [ github1 ])
		
		switch resolved {
		case .success(let value):
			let expectedValue: [Dependency: PinnedVersion] = [
				github1: .v1_0_0,
				git1: .v1_1_0
			]
			XCTAssertEqual(expectedValue, value)
		case .failure(let error):
			XCTFail("Unexpected error occurred: \(error)")
		}
	}
	
	func testIncompatibleNestedVersionSpecifiers() {
		let db: DB = [
			github1: [
				.v1_0_0: [
					git1: .compatibleWith(.v1_0_0),
					github2: .any,
				],
			],
			github2: [
				.v1_0_0: [
					git1: .compatibleWith(.v2_0_0),
				],
			],
			git1: [
				.v1_0_0: [:],
				.v1_1_0: [:],
				.v2_0_0: [:],
				.v2_0_1: [:],
			]
		]
		let resolved = db.resolve(resolverType, [github1: .any])
		
		XCTAssertNil(resolved.value)
		XCTAssertNotNil(resolved.error)
	}
	
	func testResolveIntersectingVersionSpecifiers() {
		let db: DB = [
			github1: [
				.v1_0_0: [
					github2: .compatibleWith(.v1_0_0)
				]
			],
			github2: [
				.v1_0_0: [:],
				.v2_0_0: [:]
			]
		]
		
		let resolved = db.resolve(resolverType, [ github1: .any, github2: .atLeast(.v1_0_0) ])
		
		switch resolved {
		case .success(let value):
			let expectedValue: [Dependency: PinnedVersion] = [
				github1: .v1_0_0,
				github2: .v1_0_0
			]
			XCTAssertEqual(expectedValue, value)
		case .failure(let error):
			XCTFail("Unexpected error occurred: \(error)")
		}
	}
	
	func testResolveSubsetWithConstraints() {
		let db: DB = [
			github1: [
				.v1_0_0: [
					github2: .compatibleWith(.v1_0_0),
				],
				.v1_1_0: [
					github2: .compatibleWith(.v1_0_0),
				],
				.v2_0_0: [
					github2: .compatibleWith(.v2_0_0),
				],
			],
			github2: [
				.v1_0_0: [ github3: .compatibleWith(.v1_0_0) ],
				.v1_1_0: [ github3: .compatibleWith(.v1_0_0) ],
				.v2_0_0: [:],
			],
			github3: [
				.v1_0_0: [:],
				.v1_1_0: [:],
				.v1_2_0: [:],
			],
			]
		
		let resolved = db.resolve(resolverType,
								  [ github1: .any ],
								  resolved: [ github1: .v1_0_0, github2: .v1_0_0, github3: .v1_0_0 ],
								  updating: [ github2 ]
		)
		
		switch resolved {
		case .success(let value):
			let expectedValue: [Dependency: PinnedVersion] =  [
				github3: .v1_2_0,
				github2: .v1_1_0,
				github1: .v1_0_0,
			]
			XCTAssertEqual(expectedValue, value)
		case .failure(let error):
			XCTFail("Unexpected error occurred: \(error)")
		}
	}
	
	func testValidGraphOutsideSpecifiedDependencies() {
		let db: DB = [
			github1: [
				.v1_0_0: [
					github2: .compatibleWith(.v1_0_0),
				],
				.v1_1_0: [
					github2: .compatibleWith(.v1_0_0),
				],
				.v2_0_0: [
					github2: .compatibleWith(.v2_0_0),
				],
			],
			github2: [
				.v1_0_0: [ github3: .compatibleWith(.v1_0_0) ],
				.v1_1_0: [ github3: .compatibleWith(.v1_0_0) ],
				.v2_0_0: [:],
			],
			github3: [
				.v1_0_0: [:],
				.v1_1_0: [:],
				.v1_2_0: [:],
			],
			]
		let resolved = db.resolve(resolverType,
								  [ github1: .exactly(.v2_0_0) ],
								  resolved: [ github1: .v1_0_0, github2: .v1_0_0, github3: .v1_0_0 ],
								  updating: [ github2 ]
		)
		XCTAssertNil(resolved.value)
		XCTAssertNotNil(resolved.error)
	}
	
	func testBranchNameAndSHADependency() {
		let branch = "development"
		let sha = "8ff4393ede2ca86d5a78edaf62b3a14d90bffab9"
		
		var db: DB = [
			github1: [
				.v1_0_0: [
					github2: .any,
					github3: .gitReference(sha),
				],
			],
			github2: [
				.v1_0_0: [
					github3: .gitReference(branch),
				],
			],
			github3: [
				.v1_0_0: [:],
			],
			]
		db.references = [
			github3: [
				branch: PinnedVersion(sha),
				sha: PinnedVersion(sha),
			],
		]
		
		let resolved = db.resolve(resolverType, [ github1: .any, github2: .any ])
		
		switch resolved {
		case .success(let value):
			let expectedValue: [Dependency: PinnedVersion] =  [
				github3: PinnedVersion(sha),
				github2: .v1_0_0,
				github1: .v1_0_0,
			]
			XCTAssertEqual(expectedValue, value)
		case .failure(let error):
			XCTFail("Unexpected error occurred: \(error)")
		}
	}
	
	func testOrderTransitiveDependencies() {
		let db: DB = [
			github1: [
				.v1_0_0: [
					github2: .any,
					github3: .any,
				],
			],
			github2: [
				.v1_0_0: [
					github3: .any,
					git1: .any,
				],
			],
			github3: [
				.v1_0_0: [ git2: .any ],
			],
			git1: [
				.v1_0_0: [ github3: .any ],
			],
			git2: [
				.v1_0_0: [:],
			],
			]
		
		let resolved = db.resolve(resolverType, [ github1: .any ])
		
		switch resolved {
		case .success(let value):
			let expectedValue: [Dependency: PinnedVersion] =  [
				git2: .v1_0_0,
				github3: .v1_0_0,
				git1: .v1_0_0,
				github2: .v1_0_0,
				github1: .v1_0_0,
			]
			XCTAssertEqual(expectedValue, value)
		case .failure(let error):
			XCTFail("Unexpected error occurred: \(error)")
		}
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
