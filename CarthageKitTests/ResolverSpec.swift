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
	private func loadTestCartfile(name: String) -> Cartfile {
		let testCartfileURL = NSBundle(forClass: self.dynamicType).URLForResource(name, withExtension: "")!
		let testCartfile = NSString(contentsOfURL: testCartfileURL, encoding: NSUTF8StringEncoding, error: nil)

		return Cartfile.fromString(testCartfile!).value()!
	}

	private func orderedDependencies(resolver: Resolver, fromCartfile cartfile: Cartfile) -> [[String: SemanticVersion]] {
		let result = resolver.resolveDependenciesInCartfile(cartfile)
			.reduce(initial: []) { (var dependencies, dependency) -> [[String: SemanticVersion]] in
				dependencies.append([ dependency.project.name: dependency.version ])
				return dependencies
			}
			.first()

		expect(result.error()).to(beNil())

		return result.value()!
	}

	override func spec() {
		it("should resolve a Cartfile") {
			let resolver = Resolver(versionsForDependency: self.versionsForDependency, cartfileForDependency: self.cartfileForDependency)
			let dependencies = self.orderedDependencies(resolver, fromCartfile: self.loadTestCartfile("TestCartfile"))
			expect(dependencies.count).to(equal(6));

			var generator = dependencies.generate()

			// Dependencies should be listed in build order.
			expect(generator.next()).to(equal([ "Mantle": SemanticVersion(major: 1, minor: 3, patch: 0) ]))
			expect(generator.next()).to(equal([ "git-error-translations": SemanticVersion(major: 3, minor: 0, patch: 0) ]))
			expect(generator.next()).to(equal([ "libextobjc": SemanticVersion(major: 0, minor: 4, patch: 1) ]))
			expect(generator.next()).to(equal([ "xcconfigs": SemanticVersion(major: 1, minor: 3, patch: 0) ]))
			expect(generator.next()).to(equal([ "objc-build-scripts": SemanticVersion(major: 3, minor: 0, patch: 0) ]))
			expect(generator.next()).to(equal([ "ReactiveCocoa": SemanticVersion(major: 3, minor: 0, patch: 0) ]))
		}

		it("should correctly order transitive dependencies") {
			let resolver = Resolver(versionsForDependency: { project in
				switch project.name {
				case "EmbeddedFrameworks":
					return .single(SemanticVersion(major: 1, minor: 0, patch: 0))

				case "Alamofire":
					return .single(SemanticVersion(major: 1, minor: 1, patch: 2))

				case "SwiftyJSON":
					return .single(SemanticVersion(major: 2, minor: 1, patch: 2))

				case "Swell":
					return .single(SemanticVersion(major: 1, minor: 0, patch: 0))
				
				default:
					assert(false)
				}
			}, cartfileForDependency: { dependency in
				if dependency.project.name == "EmbeddedFrameworks" {
					return .single(self.loadTestCartfile("EmbeddedFrameworksCartfile"))
				} else {
					return .single(Cartfile())
				}
			})

			let dependencies = self.orderedDependencies(resolver, fromCartfile: self.loadTestCartfile("EmbeddedFrameworksContainerCartfile"))
			expect(dependencies.count).to(equal(4));

			var generator = dependencies.generate()

			// Dependencies should be listed in build order.
			expect(generator.next()).to(equal([ "Alamofire": SemanticVersion(major: 1, minor: 1, patch: 2) ]))
			expect(generator.next()).to(equal([ "Swell": SemanticVersion(major: 1, minor: 0, patch: 0) ]))
			expect(generator.next()).to(equal([ "SwiftyJSON": SemanticVersion(major: 2, minor: 1, patch: 2) ]))
			expect(generator.next()).to(equal([ "EmbeddedFrameworks": SemanticVersion(major: 1, minor: 0, patch: 0) ]))
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

	private func cartfileForDependency(dependency: Dependency<SemanticVersion>) -> ColdSignal<Cartfile> {
		var cartfile = Cartfile()

		if dependency.project == ProjectIdentifier.GitHub(GitHubRepository(owner: "ReactiveCocoa", name: "ReactiveCocoa")) {
			cartfile = Cartfile.fromString("github \"jspahrsummers/libextobjc\" ~> 0.4\ngithub \"jspahrsummers/objc-build-scripts\" >= 3.0").value()!
		} else if dependency.project == ProjectIdentifier.GitHub(GitHubRepository(owner: "jspahrsummers", name: "objc-build-scripts")) {
			cartfile = Cartfile.fromString("github \"jspahrsummers/xcconfigs\" ~> 1.0").value()!
		}

		return .single(cartfile)
	}
}
