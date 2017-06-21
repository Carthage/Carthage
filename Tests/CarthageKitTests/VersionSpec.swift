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
			expect(SemanticVersion.from(PinnedVersion("1.4")).value) == SemanticVersion(major: 1, minor: 4, patch: 0)
			expect(SemanticVersion.from(PinnedVersion("v2.8.9")).value) == SemanticVersion(major: 2, minor: 8, patch: 9)
		}

		it("should fail on invalid semantic versions") {
			expect(SemanticVersion.from(PinnedVersion("v1")).value).to(beNil())
			expect(SemanticVersion.from(PinnedVersion("v2.8-alpha")).value).to(beNil())
			expect(SemanticVersion.from(PinnedVersion("null-string-beta-2")).value).to(beNil())
		}
	}
}

class VersionSpecifierSpec: QuickSpec {
	override func spec() {
		func testIntersection(_ lhs: VersionSpecifier, _ rhs: VersionSpecifier, expected: VersionSpecifier?) {
			if let expected = expected {
				expect(intersection(lhs, rhs)) == expected
				expect(intersection(rhs, lhs)) == expected
			} else {
				expect(intersection(lhs, rhs)).to(beNil())
				expect(intersection(rhs, lhs)).to(beNil())
			}
		}

		describe("isSatisfied(by:)") {
			let v0_1_0 = PinnedVersion("0.1.0")
			let v0_1_1 = PinnedVersion("0.1.1")
			let v0_2_0 = PinnedVersion("0.2.0")
			let v1_3_2 = PinnedVersion("1.3.2")
			let v2_0_2 = PinnedVersion("2.0.2")
			let v2_1_1 = PinnedVersion("2.1.1")
			let v2_2_0 = PinnedVersion("2.2.0")
			let v3_0_0 = PinnedVersion("3.0.0")

			it("should allow all versions for .any") {
				let specifier = VersionSpecifier.any
				expect(specifier.isSatisfied(by: v1_3_2)) == true
				expect(specifier.isSatisfied(by: v2_0_2)) == true
				expect(specifier.isSatisfied(by: v2_1_1)) == true
				expect(specifier.isSatisfied(by: v2_2_0)) == true
				expect(specifier.isSatisfied(by: v3_0_0)) == true
			}

			it("should allow greater or equal versions for .atLeast") {
				let specifier = VersionSpecifier.atLeast(SemanticVersion.from(v2_1_1).value!)
				expect(specifier.isSatisfied(by: v1_3_2)) == false
				expect(specifier.isSatisfied(by: v2_0_2)) == false
				expect(specifier.isSatisfied(by: v2_1_1)) == true
				expect(specifier.isSatisfied(by: v2_2_0)) == true
				expect(specifier.isSatisfied(by: v3_0_0)) == true
			}

			it("should allow greater or equal minor and patch versions for .compatibleWith") {
				let specifier = VersionSpecifier.compatibleWith(SemanticVersion.from(v2_1_1).value!)
				expect(specifier.isSatisfied(by: v1_3_2)) == false
				expect(specifier.isSatisfied(by: v2_0_2)) == false
				expect(specifier.isSatisfied(by: v2_1_1)) == true
				expect(specifier.isSatisfied(by: v2_2_0)) == true
				expect(specifier.isSatisfied(by: v3_0_0)) == false
			}

			it("should only allow exact versions for .exactly") {
				let specifier = VersionSpecifier.exactly(SemanticVersion.from(v2_2_0).value!)
				expect(specifier.isSatisfied(by: v1_3_2)) == false
				expect(specifier.isSatisfied(by: v2_0_2)) == false
				expect(specifier.isSatisfied(by: v2_1_1)) == false
				expect(specifier.isSatisfied(by: v2_2_0)) == true
				expect(specifier.isSatisfied(by: v3_0_0)) == false
			}

			it("should allow only greater patch versions to satisfy 0.x") {
				let specifier = VersionSpecifier.compatibleWith(SemanticVersion.from(v0_1_0).value!)
				expect(specifier.isSatisfied(by: v0_1_0)) == true
				expect(specifier.isSatisfied(by: v0_1_1)) == true
				expect(specifier.isSatisfied(by: v0_2_0)) == false
			}
		}

		describe("intersection") {
			let v0_1_0 = SemanticVersion(major: 0, minor: 1, patch: 0)
			let v0_1_1 = SemanticVersion(major: 0, minor: 1, patch: 1)
			let v0_2_0 = SemanticVersion(major: 0, minor: 2, patch: 0)
			let v1_3_2 = SemanticVersion(major: 1, minor: 3, patch: 2)
			let v2_1_1 = SemanticVersion(major: 2, minor: 1, patch: 1)
			let v2_2_0 = SemanticVersion(major: 2, minor: 2, patch: 0)

			it("should return the tighter specifier when one is .any") {
				testIntersection(.any, .any, expected: .any)
				testIntersection(.any, .atLeast(v1_3_2), expected: .atLeast(v1_3_2))
				testIntersection(.any, .compatibleWith(v1_3_2), expected: .compatibleWith(v1_3_2))
				testIntersection(.any, .exactly(v1_3_2), expected: .exactly(v1_3_2))
			}

			it("should return the higher specifier when one is .atLeast") {
				testIntersection(.atLeast(v1_3_2), .atLeast(v1_3_2), expected: .atLeast(v1_3_2))
				testIntersection(.atLeast(v1_3_2), .atLeast(v2_1_1), expected: .atLeast(v2_1_1))
				testIntersection(.atLeast(v1_3_2), .compatibleWith(v2_1_1), expected: .compatibleWith(v2_1_1))
				testIntersection(.atLeast(v2_1_1), .compatibleWith(v2_2_0), expected: .compatibleWith(v2_2_0))
				testIntersection(.atLeast(v1_3_2), .exactly(v2_2_0), expected: .exactly(v2_2_0))
			}

			it("should return the higher minor or patch version when one is .compatibleWith") {
				testIntersection(.compatibleWith(v1_3_2), .compatibleWith(v1_3_2), expected: .compatibleWith(v1_3_2))
				testIntersection(.compatibleWith(v1_3_2), .compatibleWith(v2_1_1), expected: nil)
				testIntersection(.compatibleWith(v2_1_1), .compatibleWith(v2_2_0), expected: .compatibleWith(v2_2_0))
				testIntersection(.compatibleWith(v2_1_1), .exactly(v2_2_0), expected: .exactly(v2_2_0))
			}

			it("should only match exact specifiers for .exactly") {
				testIntersection(.exactly(v1_3_2), .atLeast(v2_1_1), expected: nil)
				testIntersection(.exactly(v2_1_1), .compatibleWith(v1_3_2), expected: nil)
				testIntersection(.exactly(v2_1_1), .compatibleWith(v2_2_0), expected: nil)
				testIntersection(.exactly(v1_3_2), .exactly(v1_3_2), expected: VersionSpecifier.exactly(v1_3_2))
				testIntersection(.exactly(v2_1_1), .exactly(v1_3_2), expected: nil)
			}

			it("should not let ~> 0.1.1 be compatible with 0.1.2, but not 0.2") {
				testIntersection(.compatibleWith(v0_1_0), .compatibleWith(v0_1_1), expected: .compatibleWith(v0_1_1))
				testIntersection(.compatibleWith(v0_1_0), .compatibleWith(v0_2_0), expected: nil)
			}
		}
	}
}
