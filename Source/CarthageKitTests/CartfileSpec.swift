//
//  CartfileSpec.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import Result
import Tentacle
import Nimble
import Quick

class CartfileSpec: QuickSpec {
	override func spec() {
		it("should parse a Cartfile") {
			let testCartfileURL = Bundle(for: type(of: self)).url(forResource: "TestCartfile", withExtension: "")!
			let testCartfile = try! String(contentsOfURL: testCartfileURL, encoding: NSUTF8StringEncoding)

			let result = Cartfile.fromString(testCartfile)
			expect(result.error).to(beNil())

			let cartfile = result.value!
			expect(cartfile.dependencies.count) == 7

			let depReactiveCocoa = cartfile.dependencies[0]
			expect(depReactiveCocoa.project) == ProjectIdentifier.gitHub(Repository(owner: "ReactiveCocoa", name: "ReactiveCocoa"))
			expect(depReactiveCocoa.version) == VersionSpecifier.atLeast(SemanticVersion(major: 2, minor: 3, patch: 1))

			let depMantle = cartfile.dependencies[1]
			expect(depMantle.project) == ProjectIdentifier.gitHub(Repository(owner: "Mantle", name: "Mantle"))
			expect(depMantle.version) == VersionSpecifier.compatibleWith(SemanticVersion(major: 1, minor: 0, patch: 0))

			let depLibextobjc = cartfile.dependencies[2]
			expect(depLibextobjc.project) == ProjectIdentifier.gitHub(Repository(owner: "jspahrsummers", name: "libextobjc"))
			expect(depLibextobjc.version) == VersionSpecifier.exactly(SemanticVersion(major: 0, minor: 4, patch: 1))

			let depConfigs = cartfile.dependencies[3]
			expect(depConfigs.project) == ProjectIdentifier.gitHub(Repository(owner: "jspahrsummers", name: "xcconfigs"))
			expect(depConfigs.version) == VersionSpecifier.any

			let depCharts = cartfile.dependencies[4]
			expect(depCharts.project) == ProjectIdentifier.gitHub(Repository(owner: "danielgindi", name: "ios-charts"))
			expect(depCharts.version) == VersionSpecifier.any

			let depErrorTranslations2 = cartfile.dependencies[5]
			expect(depErrorTranslations2.project) == ProjectIdentifier.gitHub(Repository(server: .Enterprise(url: NSURL(string: "https://enterprise.local/ghe")!), owner: "desktop", name: "git-error-translations"))
			expect(depErrorTranslations2.version) == VersionSpecifier.any

			let depErrorTranslations = cartfile.dependencies[6]
			expect(depErrorTranslations.project) == ProjectIdentifier.git(GitURL("https://enterprise.local/desktop/git-error-translations2.git"))
			expect(depErrorTranslations.version) == VersionSpecifier.gitReference("development")
		}

		it("should parse a Cartfile.resolved") {
			let testCartfileURL = Bundle(for: type(of: self)).url(forResource: "TestCartfile", withExtension: "resolved")!
			let testCartfile = try! String(contentsOfURL: testCartfileURL, encoding: NSUTF8StringEncoding)

			let result = ResolvedCartfile.fromString(testCartfile)
			expect(result.error).to(beNil())

			let resolvedCartfile = result.value!
			expect(resolvedCartfile.dependencies.count) == 2

			let depReactiveCocoa = resolvedCartfile.dependencies[0]
			expect(depReactiveCocoa.project) == ProjectIdentifier.gitHub(Repository(owner: "ReactiveCocoa", name: "ReactiveCocoa"))
			expect(depReactiveCocoa.version) == PinnedVersion("v2.3.1")

			let depMantle = resolvedCartfile.dependencies[1]
			expect(depMantle.project) == ProjectIdentifier.git(GitURL("https://github.com/Mantle/Mantle.git"))
			expect(depMantle.version) == PinnedVersion("40abed6e58b4864afac235c3bb2552e23bc9da47")
		}

		it("should detect duplicate dependencies in a single Cartfile") {
			let testCartfileURL = Bundle(for: type(of: self)).url(forResource: "DuplicateDependencies/Cartfile", withExtension: "")!
			let testCartfile = try! String(contentsOfURL: testCartfileURL, encoding: NSUTF8StringEncoding)

			let result = Cartfile.fromString(testCartfile)
			expect(result.error).to(beNil())

			let cartfile = result.value!
			expect(cartfile.dependencies.count) == 11

			let dupes = cartfile.duplicateProjects().sort { $0.description < $1.description }
			expect(dupes.count) == 2

			let self2Dupe = dupes[0]
			expect(self2Dupe) == ProjectIdentifier.gitHub(Repository(owner: "self2", name: "self2"))

			let self3Dupe = dupes[1]
			expect(self3Dupe) == ProjectIdentifier.gitHub(Repository(owner: "self3", name: "self3"))
		}

		it("should detect duplicate dependencies across two Cartfiles") {
			let testCartfileURL = Bundle(for: type(of: self)).url(forResource: "DuplicateDependencies/Cartfile", withExtension: "")!
			let testCartfile2URL = Bundle(for: type(of: self)).url(forResource: "DuplicateDependencies/Cartfile.private", withExtension: "")!

			let testCartfile = try! String(contentsOfURL: testCartfileURL, encoding: NSUTF8StringEncoding)
			let testCartfile2 = try! String(contentsOfURL: testCartfile2URL, encoding: NSUTF8StringEncoding)

			let result = Cartfile.fromString(testCartfile)
			expect(result.error).to(beNil())

			let result2 = Cartfile.fromString(testCartfile2)
			expect(result2.error).to(beNil())

			let cartfile = result.value!
			expect(cartfile.dependencies.count) == 11

			let cartfile2 = result2.value!
			expect(cartfile2.dependencies.count) == 3

			let dupes = duplicateProjectsInCartfiles(cartfile, cartfile2).sort { $0.description < $1.description }
			expect(dupes.count) == 3

			let dupe1 = dupes[0]
			expect(dupe1) == ProjectIdentifier.gitHub(Repository(owner: "1", name: "1"))

			let dupe3 = dupes[1]
			expect(dupe3) == ProjectIdentifier.gitHub(Repository(owner: "3", name: "3"))

			let dupe5 = dupes[2]
			expect(dupe5) == ProjectIdentifier.gitHub(Repository(owner: "5", name: "5"))
		}

		describe("ResolvedCartfile") {
			it("should output GitHub dependencies as expected") {
				let project = ProjectIdentifier.gitHub(Repository(owner: "ReactiveCocoa", name: "ReactiveCocoa"))
				let version = PinnedVersion("v2.3.1")
				let dependency = Dependency(project: project, version: version)

				let resolvedCartfile = ResolvedCartfile(dependencies: [ dependency ])
				let outputs = resolvedCartfile
					.description
					.characters
					.split("\n")
					.map(String.init)

				expect(outputs).to(contain("github \"ReactiveCocoa/ReactiveCocoa\" \"v2.3.1\""))
			}
		}
	}
}
