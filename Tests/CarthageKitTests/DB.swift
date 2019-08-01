import CarthageKit
import ReactiveSwift
import Foundation
import Result
import Tentacle
import Utility

// swiftlint:disable no_extension_access_modifier
let git1 = Dependency.git(GitURL("https://example.com/repo1"))
let git2 = Dependency.git(GitURL("https://example.com/repo2.git"))
let github1 = Dependency.gitHub(.dotCom, Repository(owner: "gob", name: "1"))
let github2 = Dependency.gitHub(.dotCom, Repository(owner: "gob", name: "2"))
let github3 = Dependency.gitHub(.dotCom, Repository(owner: "gob", name: "3"))
let github4 = Dependency.gitHub(.dotCom, Repository(owner: "gob", name: "4"))
let github5 = Dependency.gitHub(.dotCom, Repository(owner: "gob", name: "5"))
let github6 = Dependency.gitHub(.dotCom, Repository(owner: "gob", name: "6"))

extension PinnedVersion {
	static let v0_1_0 = PinnedVersion("v0.1.0")
	static let v1_0_0 = PinnedVersion("v1.0.0")
	static let v1_1_0 = PinnedVersion("v1.1.0")
	static let v1_2_0 = PinnedVersion("v1.2.0")
	static let v2_0_0 = PinnedVersion("v2.0.0")
	static let v2_0_0_beta_1 = PinnedVersion("v2.0.0-beta.1")
	static let v2_0_1 = PinnedVersion("v2.0.1")
	static let v3_0_0_beta_1 = PinnedVersion("v3.0.0-beta.1")
	static let v3_0_0 = PinnedVersion("v3.0.0")
}

extension Version {
	static let v0_1_0 = Version(0, 1, 0)
	static let v1_0_0 = Version(1, 0, 0)
	static let v1_1_0 = Version(1, 1, 0)
	static let v1_2_0 = Version(1, 2, 0)
	static let v2_0_0 = Version(2, 0, 0)
	static let v2_0_1 = Version(2, 0, 1)
	static let v3_0_0 = Version(3, 0, 0)
}
// swiftlint:enable no_extension_access_modifier

internal struct DB {
	var versions: [Dependency: [PinnedVersion: [Dependency: VersionSpecifier]]]
	var references: [Dependency: [String: PinnedVersion]] = [:]
	
	func versions(for dependency: Dependency) -> SignalProducer<PinnedVersion, CarthageError> {
		if let versions = self.versions[dependency] {
			return .init(versions.keys)
		} else {
			return .init(error: .taggedVersionNotFound(dependency))
		}
	}
	
	func dependencies(for dependency: Dependency, version: PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError> {
		if let dependencies = self.versions[dependency]?[version] {
			return .init(dependencies.map { ($0.0, $0.1) })
		} else {
			return .empty
		}
	}
	
	func resolvedGitReference(_ dependency: Dependency, reference: String) -> SignalProducer<PinnedVersion, CarthageError> {
		if let version = references[dependency]?[reference] {
			return .init(value: version)
		} else {
			return .empty
		}
	}

	func resolver(_ resolverType: ResolverProtocol.Type = Resolver.self) -> ResolverProtocol {
		return resolverType.init(
			versionsForDependency: self.versions(for:),
			dependenciesForDependency: self.dependencies(for:version:),
			resolvedGitReference: self.resolvedGitReference(_:reference:)
		)
	}

	func resolve(
		_ resolverType: ResolverProtocol.Type,
		_ dependencies: [Dependency: VersionSpecifier],
		resolved: [Dependency: PinnedVersion] = [:],
		updating: Set<Dependency> = []
		) -> Result<[Dependency: PinnedVersion], CarthageError> {
		let resolver = resolverType.init(
			versionsForDependency: self.versions(for:),
			dependenciesForDependency: self.dependencies(for:version:),
			resolvedGitReference: self.resolvedGitReference(_:reference:)
		)
		return resolver
			.resolve(
				dependencies: dependencies,
				lastResolved: resolved,
				dependenciesToUpdate: updating.map { $0.name }
			)
			.first()!
	}
}

extension DB: ExpressibleByDictionaryLiteral {
	init(dictionaryLiteral elements: (Dependency, [PinnedVersion: [Dependency: VersionSpecifier]])...) {
		self.init(versions: [:], references: [:])
		for (key, value) in elements {
			versions[key] = value
		}
	}
}
