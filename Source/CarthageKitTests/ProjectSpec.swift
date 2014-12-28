//
//  ProjectSpec.swift
//  Carthage
//
//  Created by Robert Böhnke on 27/12/14.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import Nimble
import Quick

class ProjectSpec: QuickSpec {
	override func spec() {
		let directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("CartfilePrivateOnly", withExtension: nil)!

		it("should load a combined Cartfile when only a Cartfile.private is present") {
			let result = Project.loadCombinedCartfile(directoryURL).single()

			expect(result.isSuccess()).to(beTruthy())

			let dependencies = result.value()?.dependencies ?? []

			expect(countElements(dependencies)).to(equal(1))
			expect(dependencies.first?.project.name).to(equal("Carthage"))
		}
	}
}
