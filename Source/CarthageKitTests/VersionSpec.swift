//
//  VersionSpec.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-08.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import Nimble
import Quick

class SemanticVersionSpec: QuickSpec {
	override func spec() {
		it("should order versions correctly") {
			let version = SemanticVersion(major: 2, minor: 1, patch: 1)

			expect(version) < SemanticVersion(major: 3, minor: 0, patch: 0)
			expect(version) < SemanticVersion(major: 2, minor: 2, patch: 0)
			expect(version) < SemanticVersion(major: 2, minor: 1, patch: 2)

			expect(version) > SemanticVersion(major: 1, minor: 2, patch: 2)
			expect(version) > SemanticVersion(major: 2, minor: 0, patch: 2)
			expect(version) > SemanticVersion(major: 2, minor: 1, patch: 0)

			expect(version) < SemanticVersion(major: 10, minor: 0, patch: 0)
			expect(version) < SemanticVersion(major: 2, minor: 10, patch: 1)
			expect(version) < SemanticVersion(major: 2, minor: 1, patch: 10)
		}

		it("should parse semantic versions") {
			expect(SemanticVersion.fromPinnedVersion(PinnedVersion("1.4")).value) == SemanticVersion(major: 1, minor: 4, patch: 0)
			expect(SemanticVersion.fromPinnedVersion(PinnedVersion("v2.8.9")).value) == SemanticVersion(major: 2, minor: 8, patch: 9)
		}

		it("should fail on invalid semantic versions") {
			expect(SemanticVersion.fromPinnedVersion(PinnedVersion("v1")).value).to(beNil())
			expect(SemanticVersion.fromPinnedVersion(PinnedVersion("v2.8-alpha")).value).to(beNil())
			expect(SemanticVersion.fromPinnedVersion(PinnedVersion("null-string-beta-2")).value).to(beNil())
		}
	}
}

class VersionSpecifierSpec: QuickSpec {
	override func spec() {
		let versionZeroOne = SemanticVersion.fromPinnedVersion(PinnedVersion("0.1.0")).value!
		let versionZeroOneOne = SemanticVersion.fromPinnedVersion(PinnedVersion("0.1.1")).value!
		let versionZeroTwo = SemanticVersion.fromPinnedVersion(PinnedVersion("0.2.0")).value!
		let versionOne = SemanticVersion.fromPinnedVersion(PinnedVersion("1.3.2")).value!
		let versionTwoZero = SemanticVersion.fromPinnedVersion(PinnedVersion("2.0.2")).value!
		let versionTwoOne = SemanticVersion.fromPinnedVersion(PinnedVersion("2.1.1")).value!
		let versionTwoTwo = SemanticVersion.fromPinnedVersion(PinnedVersion("2.2.0")).value!
		let versionThree = SemanticVersion.fromPinnedVersion(PinnedVersion("3.0.0")).value!

		func testIntersection(lhs: VersionSpecifier, _ rhs: VersionSpecifier, expected: VersionSpecifier?) {
			if let expected = expected {
				expect(intersection(lhs, rhs)) == expected
				expect(intersection(rhs, lhs)) == expected
			} else {
				expect(intersection(lhs, rhs)).to(beNil())
				expect(intersection(rhs, lhs)).to(beNil())
			}
		}

		describe("isSatisfied(by:)") {
			it("should allow all versions for .any") {
				let specifier = VersionSpecifier.any
				expect(specifier.isSatisfied(by: versionOne.pinnedVersion!)) == true
				expect(specifier.isSatisfied(by: versionTwoZero.pinnedVersion!)) == true
				expect(specifier.isSatisfied(by: versionTwoOne.pinnedVersion!)) == true
				expect(specifier.isSatisfied(by: versionTwoTwo.pinnedVersion!)) == true
				expect(specifier.isSatisfied(by: versionThree.pinnedVersion!)) == true
			}

			it("should allow greater or equal versions for .atLeast") {
				let specifier = VersionSpecifier.atLeast(versionTwoOne)
				expect(specifier.isSatisfied(by: versionOne.pinnedVersion!)) == false
				expect(specifier.isSatisfied(by: versionTwoZero.pinnedVersion!)) == false
				expect(specifier.isSatisfied(by: versionTwoOne.pinnedVersion!)) == true
				expect(specifier.isSatisfied(by: versionTwoTwo.pinnedVersion!)) == true
				expect(specifier.isSatisfied(by: versionThree.pinnedVersion!)) == true
			}

			it("should allow greater or equal minor and patch versions for .compatibleWith") {
				let specifier = VersionSpecifier.compatibleWith(versionTwoOne)
				expect(specifier.isSatisfied(by: versionOne.pinnedVersion!)) == false
				expect(specifier.isSatisfied(by: versionTwoZero.pinnedVersion!)) == false
				expect(specifier.isSatisfied(by: versionTwoOne.pinnedVersion!)) == true
				expect(specifier.isSatisfied(by: versionTwoTwo.pinnedVersion!)) == true
				expect(specifier.isSatisfied(by: versionThree.pinnedVersion!)) == false
			}

			it("should only allow exact versions for .exactly") {
				let specifier = VersionSpecifier.exactly(versionTwoTwo)
				expect(specifier.isSatisfied(by: versionOne.pinnedVersion!)) == false
				expect(specifier.isSatisfied(by: versionTwoZero.pinnedVersion!)) == false
				expect(specifier.isSatisfied(by: versionTwoOne.pinnedVersion!)) == false
				expect(specifier.isSatisfied(by: versionTwoTwo.pinnedVersion!)) == true
				expect(specifier.isSatisfied(by: versionThree.pinnedVersion!)) == false
			}

			it("should allow only greater patch versions to satisfy 0.x") {
				let specifier = VersionSpecifier.compatibleWith(versionZeroOne)
				expect(specifier.isSatisfied(by: versionZeroOneOne.pinnedVersion!)) == true
				expect(specifier.isSatisfied(by: versionZeroTwo.pinnedVersion!)) == false
			}
		}

		describe("intersection") {
			it("should return the tighter specifier when one is .any") {
				testIntersection(VersionSpecifier.any, VersionSpecifier.any, expected: VersionSpecifier.any)
				testIntersection(VersionSpecifier.any, VersionSpecifier.atLeast(versionOne), expected: VersionSpecifier.atLeast(versionOne))
				testIntersection(VersionSpecifier.any, VersionSpecifier.compatibleWith(versionOne), expected: VersionSpecifier.compatibleWith(versionOne))
				testIntersection(VersionSpecifier.any, VersionSpecifier.exactly(versionOne), expected: VersionSpecifier.exactly(versionOne))
			}

			it("should return the higher specifier when one is .atLeast") {
				testIntersection(VersionSpecifier.atLeast(versionOne), VersionSpecifier.atLeast(versionOne), expected: VersionSpecifier.atLeast(versionOne))
				testIntersection(VersionSpecifier.atLeast(versionOne), VersionSpecifier.atLeast(versionTwoOne), expected: VersionSpecifier.atLeast(versionTwoOne))
				testIntersection(VersionSpecifier.atLeast(versionOne), VersionSpecifier.compatibleWith(versionTwoOne), expected: VersionSpecifier.compatibleWith(versionTwoOne))
				testIntersection(VersionSpecifier.atLeast(versionTwoOne), VersionSpecifier.compatibleWith(versionTwoTwo), expected: VersionSpecifier.compatibleWith(versionTwoTwo))
				testIntersection(VersionSpecifier.atLeast(versionOne), VersionSpecifier.exactly(versionTwoTwo), expected: VersionSpecifier.exactly(versionTwoTwo))
			}

			it("should return the higher minor or patch version when one is .compatibleWith") {
				testIntersection(VersionSpecifier.compatibleWith(versionOne), VersionSpecifier.compatibleWith(versionOne), expected: VersionSpecifier.compatibleWith(versionOne))
				testIntersection(VersionSpecifier.compatibleWith(versionOne), VersionSpecifier.compatibleWith(versionTwoOne), expected: nil)
				testIntersection(VersionSpecifier.compatibleWith(versionTwoOne), VersionSpecifier.compatibleWith(versionTwoTwo), expected: VersionSpecifier.compatibleWith(versionTwoTwo))
				testIntersection(VersionSpecifier.compatibleWith(versionTwoOne), VersionSpecifier.exactly(versionTwoTwo), expected: VersionSpecifier.exactly(versionTwoTwo))
			}

			it("should only match exact specifiers for .exactly") {
				testIntersection(VersionSpecifier.atLeast(versionTwoOne), VersionSpecifier.exactly(versionOne), expected: nil)
				testIntersection(VersionSpecifier.compatibleWith(versionOne), VersionSpecifier.exactly(versionTwoOne), expected: nil)
				testIntersection(VersionSpecifier.compatibleWith(versionTwoTwo), VersionSpecifier.exactly(versionTwoOne), expected: nil)
				testIntersection(VersionSpecifier.exactly(versionOne), VersionSpecifier.exactly(versionOne), expected: VersionSpecifier.exactly(versionOne))
				testIntersection(VersionSpecifier.exactly(versionTwoOne), VersionSpecifier.exactly(versionOne), expected: nil)
			}

			it("should not let ~> 0.1.1 be compatible with 0.1.2, but not 0.2") {
				testIntersection(VersionSpecifier.compatibleWith(versionZeroOne), VersionSpecifier.compatibleWith(versionZeroOneOne), expected: VersionSpecifier.compatibleWith(versionZeroOneOne))
				testIntersection(VersionSpecifier.compatibleWith(versionZeroOne), VersionSpecifier.compatibleWith(versionZeroTwo), expected: nil)
			}
		}
	}
}
