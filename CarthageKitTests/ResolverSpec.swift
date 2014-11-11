//
//  ResolverSpec.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import Nimble
import Quick
import ReactiveCocoa

class ResolverSpec: QuickSpec {
	override func spec() {
		it("should resolve a Cartfile") {
			let testCartfileURL = NSBundle(forClass: self.dynamicType).URLForResource("TestCartfile", withExtension: "")!
			let testCartfile = NSString(contentsOfURL: testCartfileURL, encoding: NSUTF8StringEncoding, error: nil)

			let cartfile = Cartfile.fromString(testCartfile!).value()!

			let resolver = Resolver(versionsForDependency: self.versionsForDependency, cartfileForDependency: self.cartfileForDependency)
			let result = resolver.resolveDependencesInCartfile(cartfile)
				.reduce(initial: [:]) { (var dict, dependency) -> [String: SemanticVersion] in
					switch dependency.identifier {
					case let .GitHub(repo):
						dict[repo.description] = dependency.version

					default:
						break
					}

					return dict
				}
				.first()

			expect(result.error()).to(beNil())

			let versionByRepo = result.value()!
			expect(versionByRepo["ReactiveCocoa/ReactiveCocoa"]).to(equal(SemanticVersion(major: 3, minor: 0, patch: 0)))
			expect(versionByRepo["Mantle/Mantle"]).to(equal(SemanticVersion(major: 1, minor: 3, patch: 0)))
			expect(versionByRepo["jspahrsummers/libextobjc"]).to(equal(SemanticVersion(major: 0, minor: 4, patch: 1)))
			expect(versionByRepo["jspahrsummers/xcconfigs"]).to(equal(SemanticVersion(major: 1, minor: 3, patch: 0)))
			expect(versionByRepo["jspahrsummers/objc-build-scripts"]).to(equal(SemanticVersion(major: 3, minor: 0, patch: 0)))
		}
	}

	private func versionsForDependency(dependency: ProjectIdentifier) -> ColdSignal<SemanticVersion> {
		return .fromValues([
			SemanticVersion(major: 0, minor: 4, patch: 1),
			SemanticVersion(major: 0, minor: 9, patch: 0),
			SemanticVersion(major: 1, minor: 0, patch: 2),
			SemanticVersion(major: 1, minor: 3, patch: 0),
			SemanticVersion(major: 2, minor: 4, patch: 0),
			SemanticVersion(major: 3, minor: 0, patch: 0)
		])
	}

	private func cartfileForDependency(dependency: DependencyVersion<SemanticVersion>) -> ColdSignal<Cartfile> {
		var cartfile = Cartfile()

		if dependency.identifier == ProjectIdentifier.GitHub(Repository(owner: "ReactiveCocoa", name: "ReactiveCocoa")) {
			cartfile = Cartfile.fromString("github \"jspahrsummers/libextobjc\" ~> 0.4\ngithub \"jspahrsummers/objc-build-scripts\" >= 3.0").value()!
		} else if dependency.identifier == ProjectIdentifier.GitHub(Repository(owner: "jspahrsummers", name: "objc-build-scripts")) {
			cartfile = Cartfile.fromString("github \"jspahrsummers/xcconfigs\" ~> 1.0").value()!
		}

		return .single(cartfile)
	}
}
