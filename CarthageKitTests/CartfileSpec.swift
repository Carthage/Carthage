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
			expect(cartfile.dependencies.count).to(equal(5))

			let depReactiveCocoa = cartfile.dependencies[0]
			expect(depReactiveCocoa.project).to(equal(ProjectIdentifier.GitHub(GitHubRepository(owner: "ReactiveCocoa", name: "ReactiveCocoa"))))
			expect(depReactiveCocoa.version).to(equal(VersionSpecifier.AtLeast(SemanticVersion(major: 2, minor: 3, patch: 1))))

			let depMantle = cartfile.dependencies[1]
			expect(depMantle.project).to(equal(ProjectIdentifier.GitHub(GitHubRepository(owner: "Mantle", name: "Mantle"))))
			expect(depMantle.version).to(equal(VersionSpecifier.CompatibleWith(SemanticVersion(major: 1, minor: 0, patch: 0))))

			let depLibextobjc = cartfile.dependencies[2]
			expect(depLibextobjc.project).to(equal(ProjectIdentifier.GitHub(GitHubRepository(owner: "jspahrsummers", name: "libextobjc"))))
			expect(depLibextobjc.version).to(equal(VersionSpecifier.Exactly(SemanticVersion(major: 0, minor: 4, patch: 1))))

			let depConfigs = cartfile.dependencies[3]
			expect(depConfigs.project).to(equal(ProjectIdentifier.GitHub(GitHubRepository(owner: "jspahrsummers", name: "xcconfigs"))))
			expect(depConfigs.version).to(equal(VersionSpecifier.Any))

			let depErrorTranslations = cartfile.dependencies[4]
			expect(depErrorTranslations.project).to(equal(ProjectIdentifier.Git(GitURL("https://enterprise.local/desktop/git-error-translations.git"))))
			expect(depErrorTranslations.version).to(equal(VersionSpecifier.GitReference("development")))
		}

		it("should parse a Cartfile.lock") {
			let testCartfileURL = NSBundle(forClass: self.dynamicType).URLForResource("TestCartfile", withExtension: "lock")!
			let testCartfile = NSString(contentsOfURL: testCartfileURL, encoding: NSUTF8StringEncoding, error: nil)

			let result = CartfileLock.fromString(testCartfile!)
			expect(result.error()).to(beNil())

			let cartfileLock = result.value()!
			expect(cartfileLock.dependencies.count).to(equal(2))

			let depReactiveCocoa = cartfileLock.dependencies[0]
			expect(depReactiveCocoa.project).to(equal(ProjectIdentifier.GitHub(GitHubRepository(owner: "ReactiveCocoa", name: "ReactiveCocoa"))))
			expect(depReactiveCocoa.version).to(equal(PinnedVersion(commitish: "v2.3.1")))

			let depMantle = cartfileLock.dependencies[1]
			expect(depMantle.project).to(equal(ProjectIdentifier.Git(GitURL("https://github.com/Mantle/Mantle.git"))))
			expect(depMantle.version).to(equal(PinnedVersion(commitish: "40abed6e58b4864afac235c3bb2552e23bc9da47")))
		}
	}
}
