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
		let testCartfileURL = NSBundle(forClass: self.dynamicType).URLForResource("TestCartfile", withExtension: "json")!

		it("should parse a JSON Cartfile") {
			let result: Result<Cartfile> = parseJSONAtURL(testCartfileURL)
			expect(result.error()).to(beNil())

			let cartfile = result.value()!
			expect(cartfile.dependencies.count).to(equal(3))

			let depReactiveCocoa = cartfile.dependencies[0]
			expect(depReactiveCocoa.repository.name).to(equal("ReactiveCocoa"))
			expect(depReactiveCocoa.repository.owner).to(equal("ReactiveCocoa"))

			let expectedVersion = VersionSpecifier.Exactly(Version(major: 2, minor: 3, patch: 1))
			expect(depReactiveCocoa.version).to(equal(expectedVersion))
		}
	}
}
