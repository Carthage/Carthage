//
//  CartfileSpec.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import LlamaKit
import Nimble
import Quick

class CartfileSpec: QuickSpec {
	override func spec() {
		let testCartfileURL = NSBundle(forClass: self.dynamicType).URLForResource("TestCartfile", withExtension: "")!

		it("should parse a Cartfile") {
			let testCartfile = NSString(contentsOfURL: testCartfileURL, encoding: NSUTF8StringEncoding, error: nil)

			let result = Cartfile.fromString(testCartfile!)
			expect(result.error()).to(beNil())

			let cartfile = result.value()!
			expect(cartfile.dependencies.count).to(equal(4))

			let depReactiveCocoa = cartfile.dependencies[0]
			expect(depReactiveCocoa.repository.name).to(equal("ReactiveCocoa"))
			expect(depReactiveCocoa.repository.owner).to(equal("ReactiveCocoa"))
            expect(depReactiveCocoa.version).to(equal(VersionSpecifier.AtLeast(Version(major: 2, minor: 3, patch: 1))))

			let depMantle = cartfile.dependencies[1]
			expect(depMantle.repository.name).to(equal("Mantle"))
			expect(depMantle.repository.owner).to(equal("Mantle"))
            expect(depMantle.version).to(equal(VersionSpecifier.CompatibleWith(Version(major: 1, minor: 0, patch: 0))))

			let depLibextobjc = cartfile.dependencies[2]
			expect(depLibextobjc.repository.owner).to(equal("jspahrsummers"))
			expect(depLibextobjc.repository.name).to(equal("libextobjc"))
            expect(depLibextobjc.version).to(equal(VersionSpecifier.Exactly(Version(major: 0, minor: 4, patch: 1))))

			let depConfigs = cartfile.dependencies[3]
			expect(depConfigs.repository.owner).to(equal("jspahrsummers"))
			expect(depConfigs.repository.name).to(equal("xcconfigs"))
			expect(depConfigs.version).to(equal(VersionSpecifier.Any))
		}
	}
}

class VersionSpec: QuickSpec {
	override func spec() {
		it("should order versions correctly") {
            let version = Version(major: 2, minor: 1, patch: 1)

            expect(version).to(beLessThan(Version(major: 3, minor: 0, patch: 0)))
            expect(version).to(beLessThan(Version(major: 2, minor: 2, patch: 0)))
            expect(version).to(beLessThan(Version(major: 2, minor: 1, patch: 2)))

			expect(version).to(beGreaterThan(Version(major: 1, minor: 2, patch: 2)))
			expect(version).to(beGreaterThan(Version(major: 2, minor: 0, patch: 2)))
            expect(version).to(beGreaterThan(Version(major: 2, minor: 1, patch: 0)))

            expect(version).to(beLessThan(Version(major: 10, minor: 0, patch: 0)))
            expect(version).to(beLessThan(Version(major: 2, minor: 10, patch: 1)))
            expect(version).to(beLessThan(Version(major: 2, minor: 1, patch: 10)))
		}
	}
}

class VersionSpecifierSpec: QuickSpec {
	override func spec() {
        let versionOne = Version(major: 1, minor: 3, patch: 2)
        let versionTwoZero = Version(major: 2, minor: 0, patch: 2)
        let versionTwoOne = Version(major: 2, minor: 1, patch: 1)
        let versionTwoTwo = Version(major: 2, minor: 2, patch: 0)
        let versionThree = Version(major: 3, minor: 0, patch: 0)

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
				expect(specifier.satisfiedBy(versionOne)).to(beTruthy())
				expect(specifier.satisfiedBy(versionTwoZero)).to(beTruthy())
				expect(specifier.satisfiedBy(versionTwoOne)).to(beTruthy())
				expect(specifier.satisfiedBy(versionTwoTwo)).to(beTruthy())
				expect(specifier.satisfiedBy(versionThree)).to(beTruthy())
			}

			it("should allow greater or equal versions for AtLeast") {
				let specifier = VersionSpecifier.AtLeast(versionTwoOne)
				expect(specifier.satisfiedBy(versionOne)).to(beFalsy())
				expect(specifier.satisfiedBy(versionTwoZero)).to(beFalsy())
				expect(specifier.satisfiedBy(versionTwoOne)).to(beTruthy())
				expect(specifier.satisfiedBy(versionTwoTwo)).to(beTruthy())
				expect(specifier.satisfiedBy(versionThree)).to(beTruthy())
			}

			it("should allow greater or equal minor and patch versions for CompatibleWith") {
				let specifier = VersionSpecifier.CompatibleWith(versionTwoOne)
				expect(specifier.satisfiedBy(versionOne)).to(beFalsy())
				expect(specifier.satisfiedBy(versionTwoZero)).to(beFalsy())
				expect(specifier.satisfiedBy(versionTwoOne)).to(beTruthy())
				expect(specifier.satisfiedBy(versionTwoTwo)).to(beTruthy())
				expect(specifier.satisfiedBy(versionThree)).to(beFalsy())
			}

			it("should only allow exact versions for Exactly") {
				let specifier = VersionSpecifier.Exactly(versionTwoTwo)
				expect(specifier.satisfiedBy(versionOne)).to(beFalsy())
				expect(specifier.satisfiedBy(versionTwoZero)).to(beFalsy())
				expect(specifier.satisfiedBy(versionTwoOne)).to(beFalsy())
				expect(specifier.satisfiedBy(versionTwoTwo)).to(beTruthy())
				expect(specifier.satisfiedBy(versionThree)).to(beFalsy())
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
		}
	}
}
