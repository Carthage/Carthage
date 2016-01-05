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
import ReactiveCocoa

class ProjectSpec: QuickSpec {
	override func spec() {
		let directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("CartfilePrivateOnly", withExtension: nil)!

		it("should load a combined Cartfile when only a Cartfile.private is present") {
			let result = Project(directoryURL: directoryURL).loadCombinedCartfile().single()
			expect(result).notTo(beNil())
			expect(result?.value).notTo(beNil())

			let dependencies = result?.value?.dependencies
			expect(dependencies?.count) == 1
			expect(dependencies?.first?.project.name) == "Carthage"
		}

        it("should detect duplicate dependencies across Cartfile and Cartfile.private") {
            let directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("DuplicateDependencies", withExtension: nil)!
            let result = Project(directoryURL: directoryURL).loadCombinedCartfile().single()
			expect(result).notTo(beNil())

			let resultError = result?.error
			expect(resultError).notTo(beNil())

			let makeDependency: (String, String, [String]) -> DuplicateDependency = { (repoOwner, repoName, locations) in
				let project = ProjectIdentifier.GitHub(GitHubRepository(owner: repoOwner, name: repoName))
				return DuplicateDependency(project: project, locations: locations)
			}

			let mainLocation = ["\(CarthageProjectCartfilePath)"]
			let bothLocations = ["\(CarthageProjectCartfilePath)", "\(CarthageProjectPrivateCartfilePath)"]

			let expectedError = CarthageError.DuplicateDependencies([
				makeDependency("self2", "self2", mainLocation),
				makeDependency("self3", "self3", mainLocation),
				makeDependency("1", "1", bothLocations),
				makeDependency("3", "3", bothLocations),
				makeDependency("5", "5", bothLocations),
			])

			expect(resultError) == expectedError
        }
	}
}
