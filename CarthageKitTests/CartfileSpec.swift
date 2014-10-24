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
			expect(cartfile.dependencies.count).to(equal(3))

			let depReactiveCocoa = cartfile.dependencies[0]
			expect(depReactiveCocoa.repository.name).to(equal("ReactiveCocoa"))
			expect(depReactiveCocoa.repository.owner).to(equal("ReactiveCocoa"))
			expect(depReactiveCocoa.version).to(equal(VersionSpecifier.Exactly(Version(major: 2, minor: 3, patch: 1))))

			let depConfigs = cartfile.dependencies[1]
			expect(depConfigs.repository.owner).to(equal("jspahrsummers"))
			expect(depConfigs.repository.name).to(equal("xcconfigs"))
			expect(depConfigs.version).to(equal(VersionSpecifier.Exactly(Version(major: 0, minor: 1, patch: 0))))

			let depBuildScripts = cartfile.dependencies[2]
			expect(depBuildScripts.repository.owner).to(equal("jspahrsummers"))
			expect(depBuildScripts.repository.name).to(equal("objc-build-scripts"))
			expect(depBuildScripts.version).to(equal(VersionSpecifier.Any))
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
