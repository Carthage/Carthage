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
import Tentacle

class ResolverSpec: QuickSpec {
	private func loadTestCartfile<T: CartfileType>(name: String, withExtension: String = "") -> T {
		let testCartfileURL = Bundle(for: type(of: self)).url(forResource: name, withExtension: withExtension)!
		let testCartfile = try! String(contentsOf: testCartfileURL, encoding: .utf8)

		return T.from(string: testCartfile).value!
	}

	private func dependencyForOwner(owner: String, name: String, version: String) -> CarthageKit.Dependency<PinnedVersion> {
		return CarthageKit.Dependency(project: .gitHub(Repository(owner: owner, name: name)), version: PinnedVersion(version))
	}

	private func orderedDependencies(producer: SignalProducer<CarthageKit.Dependency<PinnedVersion>, CarthageError>) -> [Dependency] {
		let result = producer
			.map { Dependency($0.project.name, $0.version.commitish) }
			.collect()
			.first()

		expect(result).notTo(beNil())
		expect(result?.error).to(beNil())

		return result?.value ?? []
	}

	override func spec() {
		var resolver: Resolver!

		beforeEach {
			resolver = Resolver(
				versionsForDependency: self.versions(for:),
				dependenciesForDependency: self.dependencies(for:),
				resolvedGitReference: self.resolvedGitReference
			)
		}

		it("should resolve a Cartfile") {
			let testCartfile: Cartfile = self.loadTestCartfile("TestCartfile")
			let producer = resolver.resolve(dependencies: testCartfile.dependencies)
			let dependencies = self.orderedDependencies(producer)
			expect(dependencies.count) == 8

			var generator = dependencies.generate()

			// Dependencies should be listed in build order.
			expect(generator.next()) == Dependency("Mantle", "1.3.0")
			expect(generator.next()) == Dependency("git-error-translations", "3.0.0")
			expect(generator.next()) == Dependency("git-error-translations2", "8ff4393ede2ca86d5a78edaf62b3a14d90bffab9")
			expect(generator.next()) == Dependency("ios-charts", "3.0.0")
			expect(generator.next()) == Dependency("libextobjc", "0.4.1")
			expect(generator.next()) == Dependency("xcconfigs", "1.3.0")
			expect(generator.next()) == Dependency("objc-build-scripts", "3.0.0") // xcconfigs
			expect(generator.next()) == Dependency("ReactiveCocoa", "3.0.0") // libextobjc, objc-build-scripts, xcconfigs
		}

		it("should resolve a Cartfile for specific dependencies") {
			let testCartfile: Cartfile = self.loadTestCartfile("TestCartfile")

			let producer = resolver.resolve(
				dependencies: testCartfile.dependencies,
				lastResolved: ResolvedCartfile(dependencies: [
						self.dependencyForOwner("danielgindi", name: "ios-charts", version: "2.4.0"),
					]).versions,
				dependenciesToUpdate: [ "Mantle", "ReactiveCocoa" ]
			)
			let dependencies = self.orderedDependencies(producer)
			expect(dependencies.count) == 6

			var generator = dependencies.generate()

			// Dependencies should be listed in build order.
			expect(generator.next()) == Dependency("Mantle", "1.3.0")

			// Existing dependencies which are not inclued in the list should
			// not be updated.
			expect(generator.next()) == Dependency("ios-charts", "2.4.0")

			// Nested dependencies should also be resolved.
			expect(generator.next()) == Dependency("libextobjc", "0.4.1")
			expect(generator.next()) == Dependency("xcconfigs", "1.3.0")
			expect(generator.next()) == Dependency("objc-build-scripts", "3.0.0") // xcconfigs
			expect(generator.next()) == Dependency("ReactiveCocoa", "3.0.0") // libextobjc, objc-build-scripts, xcconfigs

			// Newly added dependencies which are not inclued in the list should
			// not be resolved.
			expect(dependencies).notTo(contain(Dependency("git-error-translations", "3.0.0")))
			expect(dependencies).notTo(contain(Dependency("git-error-translations2", "8ff4393ede2ca86d5a78edaf62b3a14d90bffab9")))
		}

		it("should resolve a Cartfile whose dependency is specified by both a branch name and a SHA which is the HEAD of that branch") {
			let testCartfile: Cartfile = self.loadTestCartfile("TestCartfileProposedVersion")
			let producer = resolver.resolve(dependencies: testCartfile.dependencies)
			let dependencies = self.orderedDependencies(producer)
			expect(dependencies.count) == 3

			var generator = dependencies.generate()

			expect(generator.next()) == Dependency("git-error-translations2", "8ff4393ede2ca86d5a78edaf62b3a14d90bffab9")
			expect(generator.next()) == Dependency("TestCartfileBranch", "0.4.1")
			expect(generator.next()) == Dependency("TestCartfileSHA", "0.9.0")
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
			}, dependenciesForDependency: { dependency -> SignalProducer<CarthageKit.Dependency<VersionSpecifier>, CarthageError> in
				if dependency.project.name == "EmbeddedFrameworks" {
					let cartfile: Cartfile = self.loadTestCartfile("EmbeddedFrameworksCartfile")
					return SignalProducer<CarthageKit.Dependency<VersionSpecifier>, CarthageError>(Array(cartfile.dependencies))
				} else {
					return .empty
				}
			}, resolvedGitReference: { _ -> SignalProducer<PinnedVersion, CarthageError> in
				return SignalProducer(error: .invalidArgument(description: "unexpected test error"))
			})

			let testCartfile: Cartfile = self.loadTestCartfile("EmbeddedFrameworksContainerCartfile")
			let producer = resolver.resolve(dependencies: testCartfile.dependencies)
			let dependencies = self.orderedDependencies(producer)
			expect(dependencies.count) == 4

			var generator = dependencies.generate()

			// Dependencies should be listed in build order.
			expect(generator.next()) == Dependency("Alamofire", "1.1.2")
			expect(generator.next()) == Dependency("Swell", "1.0.0")
			expect(generator.next()) == Dependency("SwiftyJSON", "2.1.2")
			expect(generator.next()) == Dependency("EmbeddedFrameworks", "1.0.0") // Alamofire, Swell, SwiftyJSON
		}
	}

	private func versions(for project: ProjectIdentifier) -> SignalProducer<PinnedVersion, CarthageError> {
		return SignalProducer([
			PinnedVersion("0.4.1"),
			PinnedVersion("0.9.0"),
			PinnedVersion("1.0.2"),
			PinnedVersion("1.3.0"),
			PinnedVersion("2.4.0"),
			PinnedVersion("3.0.0")
		])
	}

	private func dependencies(for dependency: CarthageKit.Dependency<PinnedVersion>) -> SignalProducer<CarthageKit.Dependency<VersionSpecifier>, CarthageError> {
		switch dependency.project {
		case .gitHub(Repository(owner: "ReactiveCocoa", name: "ReactiveCocoa")):
			return SignalProducer([
				CarthageKit.Dependency(
					project: .gitHub(Repository(owner: "jspahrsummers", name: "libextobjc")),
					version: .compatibleWith(SemanticVersion(major: 0, minor: 4, patch: 0))
				),
				CarthageKit.Dependency(
					project: .gitHub(Repository(owner: "jspahrsummers", name: "objc-build-scripts")),
					version: .atLeast(SemanticVersion(major: 3, minor: 0, patch: 0))
				),
			])

		case .gitHub(Repository(owner: "jspahrsummers", name: "objc-build-scripts")):
			return SignalProducer([
				CarthageKit.Dependency(
					project: .gitHub(Repository(owner: "jspahrsummers", name: "xcconfigs")),
					version: .compatibleWith(SemanticVersion(major: 1, minor: 0, patch: 0))
				),
			])

		case .git(GitURL("/tmp/TestCartfileBranch")):
			return SignalProducer([
				CarthageKit.Dependency(
					project: .git(GitURL("https://enterprise.local/desktop/git-error-translations2.git")),
					version: .gitReference("development")
				),
			])

		case .git(GitURL("/tmp/TestCartfileSHA")):
			return SignalProducer([
				CarthageKit.Dependency(
					project: .git(GitURL("https://enterprise.local/desktop/git-error-translations2.git")),
					version: .gitReference("8ff4393ede2ca86d5a78edaf62b3a14d90bffab9")
				),
			])

		default:
			return .empty
		}
	}

	private func resolvedGitReference(project: ProjectIdentifier, reference: String) -> SignalProducer<PinnedVersion, CarthageError> {
		return SignalProducer(value: PinnedVersion("8ff4393ede2ca86d5a78edaf62b3a14d90bffab9"))
	}
}

// MARK: - Helpers

private struct Dependency: Equatable {
	let name: String
	let version: PinnedVersion

	init(_ name: String, _ versionString: String) {
		self.name = name
		self.version = PinnedVersion(versionString)
	}
}

private func == (lhs: Dependency, rhs: Dependency) -> Bool {
	return lhs.name == rhs.name && lhs.version == rhs.version
}

private protocol CartfileType {
	static func from(string string: String) -> Result<Self, CarthageError>
}

extension Cartfile: CartfileType {}
extension ResolvedCartfile: CartfileType {}
