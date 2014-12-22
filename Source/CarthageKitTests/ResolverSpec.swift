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

	private func orderedDependencies(resolver: Resolver, fromCartfile cartfile: Cartfile) -> [[String: PinnedVersion]] {
		let result = resolver.resolveDependenciesInCartfile(cartfile)
			.reduce(initial: []) { (var dependencies, dependency) -> [[String: PinnedVersion]] in
				dependencies.append([ dependency.project.name: dependency.version ])
				return dependencies
			}
			.first()

		expect(result.error()).to(beNil())

		return result.value()!
	}

	override func spec() {
		it("should resolve a Cartfile") {
			let resolver = Resolver(versionsForDependency: self.versionsForDependency, cartfileForDependency: self.cartfileForDependency, resolvedGitReference: self.resolvedGitReference)
			let dependencies = self.orderedDependencies(resolver, fromCartfile: self.loadTestCartfile("TestCartfile"))
			expect(dependencies.count).to(equal(6));

			var generator = dependencies.generate()

			// Dependencies should be listed in build order.
			expect(generator.next()).to(equal([ "Mantle": PinnedVersion("1.3.0") ]))
			expect(generator.next()).to(equal([ "git-error-translations": PinnedVersion("8ff4393ede2ca86d5a78edaf62b3a14d90bffab9") ]))
			expect(generator.next()).to(equal([ "libextobjc": PinnedVersion("0.4.1") ]))
			expect(generator.next()).to(equal([ "xcconfigs": PinnedVersion("1.3.0") ]))
			expect(generator.next()).to(equal([ "objc-build-scripts": PinnedVersion("3.0.0") ]))
			expect(generator.next()).to(equal([ "ReactiveCocoa": PinnedVersion("3.0.0") ]))
		}

		it("should correctly order transitive dependencies") {
			let resolver = Resolver(versionsForDependency: { project in
				switch project.name {
				case "EmbeddedFrameworks":
					return .single(PinnedVersion("1.0.0"))

				case "Alamofire":
					return .single(PinnedVersion("1.1.2"))

				case "SwiftyJSON":
					return .single(PinnedVersion("2.1.2"))

				case "Swell":
					return .single(PinnedVersion("1.0.0"))

				default:
					assert(false)
				}
			}, cartfileForDependency: { dependency in
				if dependency.project.name == "EmbeddedFrameworks" {
					return .single(self.loadTestCartfile("EmbeddedFrameworksCartfile"))
				} else {
					return .single(Cartfile())
				}
			}, resolvedGitReference: { _ in .error(RACError.Empty.error) })

			let dependencies = self.orderedDependencies(resolver, fromCartfile: self.loadTestCartfile("EmbeddedFrameworksContainerCartfile"))
			expect(dependencies.count).to(equal(4));

			var generator = dependencies.generate()

			// Dependencies should be listed in build order.
			expect(generator.next()).to(equal([ "Alamofire": PinnedVersion("1.1.2") ]))
			expect(generator.next()).to(equal([ "Swell": PinnedVersion("1.0.0") ]))
			expect(generator.next()).to(equal([ "SwiftyJSON": PinnedVersion("2.1.2") ]))
			expect(generator.next()).to(equal([ "EmbeddedFrameworks": PinnedVersion("1.0.0") ]))
		}
	}

	private func versionsForDependency(project: ProjectIdentifier) -> ColdSignal<PinnedVersion> {
		return .fromValues([
			PinnedVersion("0.4.1"),
			PinnedVersion("0.9.0"),
			PinnedVersion("1.0.2"),
			PinnedVersion("1.3.0"),
			PinnedVersion("2.4.0"),
			PinnedVersion("3.0.0")
		])
	}

	private func cartfileForDependency(dependency: Dependency<PinnedVersion>) -> ColdSignal<Cartfile> {
		var cartfile = Cartfile()

		if dependency.project == ProjectIdentifier.GitHub(GitHubRepository(owner: "ReactiveCocoa", name: "ReactiveCocoa")) {
			cartfile = Cartfile.fromString("github \"jspahrsummers/libextobjc\" ~> 0.4\ngithub \"jspahrsummers/objc-build-scripts\" >= 3.0").value()!
		} else if dependency.project == ProjectIdentifier.GitHub(GitHubRepository(owner: "jspahrsummers", name: "objc-build-scripts")) {
			cartfile = Cartfile.fromString("github \"jspahrsummers/xcconfigs\" ~> 1.0").value()!
		}

		return .single(cartfile)
	}

	private func resolvedGitReference(project: ProjectIdentifier, reference: String) -> ColdSignal<PinnedVersion> {
		return .single(PinnedVersion("8ff4393ede2ca86d5a78edaf62b3a14d90bffab9"))
	}
}
