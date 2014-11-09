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
		it("should parse a Cartfile") {
			let testCartfileURL = NSBundle(forClass: self.dynamicType).URLForResource("TestCartfile", withExtension: "")!
			let testCartfile = NSString(contentsOfURL: testCartfileURL, encoding: NSUTF8StringEncoding, error: nil)

			let result = Cartfile.fromString(testCartfile!)
			expect(result.error()).to(beNil())

			let cartfile = result.value()!
			expect(cartfile.dependencies.count).to(equal(4))

			let depReactiveCocoa = cartfile.dependencies[0]
			expect(depReactiveCocoa.repository.name).to(equal("ReactiveCocoa"))
			expect(depReactiveCocoa.repository.owner).to(equal("ReactiveCocoa"))
			expect(depReactiveCocoa.version).to(equal(VersionSpecifier.AtLeast(SemanticVersion(major: 2, minor: 3, patch: 1))))

			let depMantle = cartfile.dependencies[1]
			expect(depMantle.repository.name).to(equal("Mantle"))
			expect(depMantle.repository.owner).to(equal("Mantle"))
			expect(depMantle.version).to(equal(VersionSpecifier.CompatibleWith(SemanticVersion(major: 1, minor: 0, patch: 0))))

			let depLibextobjc = cartfile.dependencies[2]
			expect(depLibextobjc.repository.owner).to(equal("jspahrsummers"))
			expect(depLibextobjc.repository.name).to(equal("libextobjc"))
			expect(depLibextobjc.version).to(equal(VersionSpecifier.Exactly(SemanticVersion(major: 0, minor: 4, patch: 1))))

			let depConfigs = cartfile.dependencies[3]
			expect(depConfigs.repository.owner).to(equal("jspahrsummers"))
			expect(depConfigs.repository.name).to(equal("xcconfigs"))
			expect(depConfigs.version).to(equal(VersionSpecifier.Any))
		}

		it("should parse a Cartfile.lock") {
			let testCartfileURL = NSBundle(forClass: self.dynamicType).URLForResource("TestCartfile", withExtension: "lock")!
			let testCartfile = NSString(contentsOfURL: testCartfileURL, encoding: NSUTF8StringEncoding, error: nil)

			let result = CartfileLock.fromString(testCartfile!)
			expect(result.error()).to(beNil())

			let cartfileLock = result.value()!
			expect(cartfileLock.dependencies.count).to(equal(2))

			let depReactiveCocoa = cartfileLock.dependencies[0]
			expect(depReactiveCocoa.repository.name).to(equal("ReactiveCocoa"))
			expect(depReactiveCocoa.repository.owner).to(equal("ReactiveCocoa"))
			expect(depReactiveCocoa.version).to(equal(PinnedVersion(tag: "v2.3.1")))

			let depMantle = cartfileLock.dependencies[1]
			expect(depMantle.repository.name).to(equal("Mantle"))
			expect(depMantle.repository.owner).to(equal("Mantle"))
			expect(depMantle.version).to(equal(PinnedVersion(tag: "1.0")))
		}
	}
}
