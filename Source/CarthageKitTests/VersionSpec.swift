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

			expect(version).to(beLessThan(SemanticVersion(major: 3, minor: 0, patch: 0)))
			expect(version).to(beLessThan(SemanticVersion(major: 2, minor: 2, patch: 0)))
			expect(version).to(beLessThan(SemanticVersion(major: 2, minor: 1, patch: 2)))

			expect(version).to(beGreaterThan(SemanticVersion(major: 1, minor: 2, patch: 2)))
			expect(version).to(beGreaterThan(SemanticVersion(major: 2, minor: 0, patch: 2)))
			expect(version).to(beGreaterThan(SemanticVersion(major: 2, minor: 1, patch: 0)))

			expect(version).to(beLessThan(SemanticVersion(major: 10, minor: 0, patch: 0)))
			expect(version).to(beLessThan(SemanticVersion(major: 2, minor: 10, patch: 1)))
			expect(version).to(beLessThan(SemanticVersion(major: 2, minor: 1, patch: 10)))
		}

		it("should parse semantic versions") {
			expect(SemanticVersion.fromPinnedVersion(PinnedVersion("1.4")).value).to(equal(SemanticVersion(major: 1, minor: 4, patch: 0)))
			expect(SemanticVersion.fromPinnedVersion(PinnedVersion("v2.8.9")).value).to(equal(SemanticVersion(major: 2, minor: 8, patch: 9)))
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

		func testIntersection(lhs: VersionSpecifier, rhs: VersionSpecifier, #expected: VersionSpecifier?) {
			if let expected = expected {
				expect(intersection(lhs, rhs)).to(equal(expected))
				expect(intersection(rhs, lhs)).to(equal(expected))
			} else {
				expect(intersection(lhs, rhs)).to(beNil())
				expect(intersection(rhs, lhs)).to(beNil())
			}
		}

		describe("satisfiedBy") {
			it("should allow all versions for Any") {
				let specifier = VersionSpecifier.Any
				expect(specifier.satisfiedBy(versionOne.pinnedVersion!)).to(beTruthy())
				expect(specifier.satisfiedBy(versionTwoZero.pinnedVersion!)).to(beTruthy())
				expect(specifier.satisfiedBy(versionTwoOne.pinnedVersion!)).to(beTruthy())
				expect(specifier.satisfiedBy(versionTwoTwo.pinnedVersion!)).to(beTruthy())
				expect(specifier.satisfiedBy(versionThree.pinnedVersion!)).to(beTruthy())
			}

			it("should allow greater or equal versions for AtLeast") {
				let specifier = VersionSpecifier.AtLeast(versionTwoOne)
				expect(specifier.satisfiedBy(versionOne.pinnedVersion!)).to(beFalsy())
				expect(specifier.satisfiedBy(versionTwoZero.pinnedVersion!)).to(beFalsy())
				expect(specifier.satisfiedBy(versionTwoOne.pinnedVersion!)).to(beTruthy())
				expect(specifier.satisfiedBy(versionTwoTwo.pinnedVersion!)).to(beTruthy())
				expect(specifier.satisfiedBy(versionThree.pinnedVersion!)).to(beTruthy())
			}

			it("should allow greater or equal minor and patch versions for CompatibleWith") {
				let specifier = VersionSpecifier.CompatibleWith(versionTwoOne)
				expect(specifier.satisfiedBy(versionOne.pinnedVersion!)).to(beFalsy())
				expect(specifier.satisfiedBy(versionTwoZero.pinnedVersion!)).to(beFalsy())
				expect(specifier.satisfiedBy(versionTwoOne.pinnedVersion!)).to(beTruthy())
				expect(specifier.satisfiedBy(versionTwoTwo.pinnedVersion!)).to(beTruthy())
				expect(specifier.satisfiedBy(versionThree.pinnedVersion!)).to(beFalsy())
			}

			it("should only allow exact versions for Exactly") {
				let specifier = VersionSpecifier.Exactly(versionTwoTwo)
				expect(specifier.satisfiedBy(versionOne.pinnedVersion!)).to(beFalsy())
				expect(specifier.satisfiedBy(versionTwoZero.pinnedVersion!)).to(beFalsy())
				expect(specifier.satisfiedBy(versionTwoOne.pinnedVersion!)).to(beFalsy())
				expect(specifier.satisfiedBy(versionTwoTwo.pinnedVersion!)).to(beTruthy())
				expect(specifier.satisfiedBy(versionThree.pinnedVersion!)).to(beFalsy())
			}

			it("should allow only greater patch versions to satisfy 0.x") {
				let specifier = VersionSpecifier.CompatibleWith(versionZeroOne)
				expect(specifier.satisfiedBy(versionZeroOneOne.pinnedVersion!)).to(beTruthy())
				expect(specifier.satisfiedBy(versionZeroTwo.pinnedVersion!)).to(beFalsy())
			}
		}

		describe("intersection") {
			it("should return the tighter specifier when one is Any") {
				testIntersection(VersionSpecifier.Any, VersionSpecifier.Any, expected: VersionSpecifier.Any)
				testIntersection(VersionSpecifier.Any, VersionSpecifier.AtLeast(versionOne), expected: VersionSpecifier.AtLeast(versionOne))
				testIntersection(VersionSpecifier.Any, VersionSpecifier.CompatibleWith(versionOne), expected: VersionSpecifier.CompatibleWith(versionOne))
				testIntersection(VersionSpecifier.Any, VersionSpecifier.Exactly(versionOne), expected: VersionSpecifier.Exactly(versionOne))
			}

			it("should return the higher specifier when one is AtLeast") {
				testIntersection(VersionSpecifier.AtLeast(versionOne), VersionSpecifier.AtLeast(versionOne), expected: VersionSpecifier.AtLeast(versionOne))
				testIntersection(VersionSpecifier.AtLeast(versionOne), VersionSpecifier.AtLeast(versionTwoOne), expected: VersionSpecifier.AtLeast(versionTwoOne))
				testIntersection(VersionSpecifier.AtLeast(versionOne), VersionSpecifier.CompatibleWith(versionTwoOne), expected: VersionSpecifier.CompatibleWith(versionTwoOne))
				testIntersection(VersionSpecifier.AtLeast(versionTwoOne), VersionSpecifier.CompatibleWith(versionTwoTwo), expected: VersionSpecifier.CompatibleWith(versionTwoTwo))
				testIntersection(VersionSpecifier.AtLeast(versionOne), VersionSpecifier.Exactly(versionTwoTwo), expected: VersionSpecifier.Exactly(versionTwoTwo))
			}

			it("should return the higher minor or patch version when one is CompatibleWith") {
				testIntersection(VersionSpecifier.CompatibleWith(versionOne), VersionSpecifier.CompatibleWith(versionOne), expected: VersionSpecifier.CompatibleWith(versionOne))
				testIntersection(VersionSpecifier.CompatibleWith(versionOne), VersionSpecifier.CompatibleWith(versionTwoOne), expected: nil)
				testIntersection(VersionSpecifier.CompatibleWith(versionTwoOne), VersionSpecifier.CompatibleWith(versionTwoTwo), expected: VersionSpecifier.CompatibleWith(versionTwoTwo))
				testIntersection(VersionSpecifier.CompatibleWith(versionTwoOne), VersionSpecifier.Exactly(versionTwoTwo), expected: VersionSpecifier.Exactly(versionTwoTwo))
			}

			it("should only match exact specifiers for Exactly") {
				testIntersection(VersionSpecifier.AtLeast(versionTwoOne), VersionSpecifier.Exactly(versionOne), expected: nil)
				testIntersection(VersionSpecifier.CompatibleWith(versionOne), VersionSpecifier.Exactly(versionTwoOne), expected: nil)
				testIntersection(VersionSpecifier.CompatibleWith(versionTwoTwo), VersionSpecifier.Exactly(versionTwoOne), expected: nil)
				testIntersection(VersionSpecifier.Exactly(versionOne), VersionSpecifier.Exactly(versionOne), expected: VersionSpecifier.Exactly(versionOne))
				testIntersection(VersionSpecifier.Exactly(versionTwoOne), VersionSpecifier.Exactly(versionOne), expected: nil)
			}

			it("should not let ~> 0.1.1 be compatible with 0.1.2, but not 0.2") {
				testIntersection(VersionSpecifier.CompatibleWith(versionZeroOne), VersionSpecifier.CompatibleWith(versionZeroOneOne), expected: VersionSpecifier.CompatibleWith(versionZeroOneOne))
				testIntersection(VersionSpecifier.CompatibleWith(versionZeroOne), VersionSpecifier.CompatibleWith(versionZeroTwo), expected: nil)
			}
		}
	}
}
