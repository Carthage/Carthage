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
			let result = Project(directoryURL: directoryURL).loadCombinedCartfile().single()

			expect(result.isSuccess()).to(beTruthy())

			let dependencies = result.value()?.dependencies ?? []

			expect(countElements(dependencies)).to(equal(1))
			expect(dependencies.first?.project.name).to(equal("Carthage"))
		}

        it("should detect duplicate dependencies across Cartfile and Cartfile.private") {
            let directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("DuplicateDependencies", withExtension: nil)!
            let result = Project(directoryURL: directoryURL).loadCombinedCartfile().single()
			let resultError = result.error()

			expect(resultError).toNot(beNil())

			let makeDependency: (String, String, [String]) -> DuplicateDependency = { (repoOwner, repoName, locations) in
				let project = ProjectIdentifier.GitHub(GitHubRepository(owner: repoOwner, name: repoName))
				return DuplicateDependency(project: project, locations: locations)
			}

			let expectedError = CarthageError.DuplicateDependencies([
				makeDependency("self2", "self2", ["\(CarthageProjectCartfilePath)"]),
				makeDependency("self3", "self3", ["\(CarthageProjectCartfilePath)"]),
				makeDependency("1", "1", ["\(CarthageProjectCartfilePath)", "\(CarthageProjectPrivateCartfilePath)"]),
				makeDependency("3", "3", ["\(CarthageProjectCartfilePath)", "\(CarthageProjectPrivateCartfilePath)"]),
				makeDependency("5", "5", ["\(CarthageProjectCartfilePath)", "\(CarthageProjectPrivateCartfilePath)"]),
			])

			expect(resultError!).to(equal(expectedError.error))
        }
	}
}
