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
import Result

class ResolverSpec: QuickSpec {
	private func loadTestCartfile<T: CartfileType>(name: String, withExtension: String = "") -> T {
		let testCartfileURL = NSBundle(forClass: self.dynamicType).URLForResource(name, withExtension: withExtension)!
		let testCartfile = try! String(contentsOfURL: testCartfileURL, encoding: NSUTF8StringEncoding)

		return T.fromString(testCartfile).value!
	}

	private func orderedDependencies<T: CartfileType>(resolver: Resolver, fromCartfile cartfile: T) -> [[String: PinnedVersion]] {
		let result = cartfile.resolveDependenciesWith(resolver)
			.map { [ $0.project.name: $0.version ] }
			.collect()
			.first()

		expect(result).notTo(beNil())
		expect(result?.error).to(beNil())

		return result!.value!
	}

	override func spec() {
		it("should resolve a Cartfile") {
			let resolver = Resolver(versionsForDependency: self.versionsForDependency, cartfileForDependency: self.cartfileForDependency, resolvedGitReference: self.resolvedGitReference)
			let testCartfile: Cartfile = self.loadTestCartfile("TestCartfile")
			let dependencies = self.orderedDependencies(resolver, fromCartfile: testCartfile)
			expect(dependencies.count).to(equal(8));

			var generator = dependencies.generate()

			// Dependencies should be listed in build order.
			expect(generator.next()).to(equal([ "Mantle": PinnedVersion("1.3.0") ]))
			expect(generator.next()).to(equal([ "git-error-translations": PinnedVersion("3.0.0") ]))
			expect(generator.next()).to(equal([ "git-error-translations2": PinnedVersion("8ff4393ede2ca86d5a78edaf62b3a14d90bffab9") ]))
			expect(generator.next()).to(equal([ "ios-charts": PinnedVersion("3.0.0") ]))
			expect(generator.next()).to(equal([ "libextobjc": PinnedVersion("0.4.1") ]))
			expect(generator.next()).to(equal([ "xcconfigs": PinnedVersion("1.3.0") ]))
			expect(generator.next()).to(equal([ "objc-build-scripts": PinnedVersion("3.0.0") ]))
			expect(generator.next()).to(equal([ "ReactiveCocoa": PinnedVersion("3.0.0") ]))
		}

		it("should sort dependencies from Cartfile.resolved in build order") {
			let resolver = Resolver(
				versionsForDependency: self.versionsForDependency,
				cartfileForDependency: self.cartfileForDependency,
				resolvedGitReference: { _, gitRef -> SignalProducer<PinnedVersion, CarthageError> in
					return .init(value: PinnedVersion(gitRef))
				})

			let testCartfile: ResolvedCartfile = self.loadTestCartfile("TestResolvedCartfile", withExtension: "resolved")
			let dependencies = self.orderedDependencies(resolver, fromCartfile: testCartfile)
			expect(dependencies.count).to(equal(8));

			var generator = dependencies.generate()

			// Dependencies should be listed in build order.
			expect(generator.next()).to(equal([ "Mantle": PinnedVersion("1.3.0") ]))
			expect(generator.next()).to(equal([ "git-error-translations": PinnedVersion("3.0.0") ]))
			expect(generator.next()).to(equal([ "git-error-translations2": PinnedVersion("8ff4393ede2ca86d5a78edaf62b3a14d90bffab9") ]))
			expect(generator.next()).to(equal([ "ios-charts": PinnedVersion("3.0.0") ]))
			expect(generator.next()).to(equal([ "libextobjc": PinnedVersion("0.4.1") ]))
			expect(generator.next()).to(equal([ "xcconfigs": PinnedVersion("1.3.0") ]))
			expect(generator.next()).to(equal([ "objc-build-scripts": PinnedVersion("3.0.0") ]))
			expect(generator.next()).to(equal([ "ReactiveCocoa": PinnedVersion("3.0.0") ]))
		}

		it("should correctly order transitive dependencies") {
			let resolver = Resolver(versionsForDependency: { project -> SignalProducer<PinnedVersion, CarthageError> in
				switch project.name {
				case "EmbeddedFrameworks":
					return SignalProducer(value: PinnedVersion("1.0.0"))

				case "Alamofire":
					return SignalProducer(value: PinnedVersion("1.1.2"))

				case "SwiftyJSON":
					return SignalProducer(value: PinnedVersion("2.1.2"))

				case "Swell":
					return SignalProducer(value: PinnedVersion("1.0.0"))

				default:
					assert(false)
				}
			}, cartfileForDependency: { dependency -> SignalProducer<Cartfile, CarthageError> in
				if dependency.project.name == "EmbeddedFrameworks" {
					return SignalProducer(value: self.loadTestCartfile("EmbeddedFrameworksCartfile"))
				} else {
					return SignalProducer(value: Cartfile())
				}
			}, resolvedGitReference: { _ -> SignalProducer<PinnedVersion, CarthageError> in
				return SignalProducer(error: .InvalidArgument(description: "unexpected test error"))
			})

			let testCartfile: Cartfile = self.loadTestCartfile("EmbeddedFrameworksContainerCartfile")
			let dependencies = self.orderedDependencies(resolver, fromCartfile: testCartfile)
			expect(dependencies.count).to(equal(4));

			var generator = dependencies.generate()

			// Dependencies should be listed in build order.
			expect(generator.next()).to(equal([ "Alamofire": PinnedVersion("1.1.2") ]))
			expect(generator.next()).to(equal([ "Swell": PinnedVersion("1.0.0") ]))
			expect(generator.next()).to(equal([ "SwiftyJSON": PinnedVersion("2.1.2") ]))
			expect(generator.next()).to(equal([ "EmbeddedFrameworks": PinnedVersion("1.0.0") ]))
		}
	}

	private func versionsForDependency(project: ProjectIdentifier) -> SignalProducer<PinnedVersion, CarthageError> {
		return SignalProducer(values: [
			PinnedVersion("0.4.1"),
			PinnedVersion("0.9.0"),
			PinnedVersion("1.0.2"),
			PinnedVersion("1.3.0"),
			PinnedVersion("2.4.0"),
			PinnedVersion("3.0.0")
		])
	}

	private func cartfileForDependency(dependency: Dependency<PinnedVersion>) -> SignalProducer<Cartfile, CarthageError> {
		var cartfile = Cartfile()

		if dependency.project == ProjectIdentifier.GitHub(GitHubRepository(owner: "ReactiveCocoa", name: "ReactiveCocoa")) {
			cartfile = Cartfile.fromString("github \"jspahrsummers/libextobjc\" ~> 0.4\ngithub \"jspahrsummers/objc-build-scripts\" >= 3.0").value!
		} else if dependency.project == ProjectIdentifier.GitHub(GitHubRepository(owner: "jspahrsummers", name: "objc-build-scripts")) {
			cartfile = Cartfile.fromString("github \"jspahrsummers/xcconfigs\" ~> 1.0").value!
		}

		return SignalProducer(value: cartfile)
	}

	private func resolvedGitReference(project: ProjectIdentifier, reference: String) -> SignalProducer<PinnedVersion, CarthageError> {
		return SignalProducer(value: PinnedVersion("8ff4393ede2ca86d5a78edaf62b3a14d90bffab9"))
	}
}

// MARK: - Helpers

private protocol CartfileType {
	static func fromString(string: String) -> Result<Self, CarthageError>
	func resolveDependenciesWith(resolver: Resolver) -> SignalProducer<Dependency<PinnedVersion>, CarthageError>
}

extension Cartfile: CartfileType {
	private func resolveDependenciesWith(resolver: Resolver) -> SignalProducer<Dependency<PinnedVersion>, CarthageError> {
		return resolver.resolveDependenciesInCartfile(self)
	}
}

extension ResolvedCartfile: CartfileType {
	private func resolveDependenciesWith(resolver: Resolver) -> SignalProducer<Dependency<PinnedVersion>, CarthageError> {
		return resolver.resolveDependenciesInResolvedCartfile(self)
	}
}
