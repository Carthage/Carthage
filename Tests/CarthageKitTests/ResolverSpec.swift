import CarthageKit
import Foundation
import Nimble
import Quick
import ReactiveSwift
import Result
import Tentacle

private let git1 = Dependency.git(GitURL("https://example.com/repo1"))
private let git2 = Dependency.git(GitURL("https://example.com/repo2.git"))
private let github1 = Dependency.gitHub(.dotCom, Repository(owner: "gob", name: "1"))
private let github2 = Dependency.gitHub(.dotCom, Repository(owner: "gob", name: "2"))
private let github3 = Dependency.gitHub(.dotCom, Repository(owner: "gob", name: "3"))

// swiftlint:disable no_extension_access_modifier
private extension PinnedVersion {
	static let v0_1_0 = PinnedVersion("v0.1.0")
	static let v1_0_0 = PinnedVersion("v1.0.0")
	static let v1_1_0 = PinnedVersion("v1.1.0")
	static let v1_2_0 = PinnedVersion("v1.2.0")
	static let v2_0_0 = PinnedVersion("v2.0.0")
	static let v2_0_0_beta_1 = PinnedVersion("v2.0.0-beta.1")
	static let v2_0_1 = PinnedVersion("v2.0.1")
	static let v3_0_0_beta_1 = PinnedVersion("v3.0.0-beta.1")
}

private extension SemanticVersion {
	static let v0_1_0 = SemanticVersion(major: 0, minor: 1, patch: 0)
	static let v1_0_0 = SemanticVersion(major: 1, minor: 0, patch: 0)
	static let v1_1_0 = SemanticVersion(major: 1, minor: 1, patch: 0)
	static let v1_2_0 = SemanticVersion(major: 1, minor: 2, patch: 0)
	static let v2_0_0 = SemanticVersion(major: 2, minor: 0, patch: 0)
	static let v2_0_1 = SemanticVersion(major: 2, minor: 0, patch: 1)
	static let v3_0_0 = SemanticVersion(major: 3, minor: 0, patch: 0)
}
// swiftlint:enable no_extension_access_modifier

// swiftlint:enable identifier_name
private struct DB {
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

private func ==<A: Equatable, B: Equatable>(lhs: [(A, B)], rhs: [(A, B)]) -> Bool {
	guard lhs.count == rhs.count else { return false }
	for (lhs, rhs) in zip(lhs, rhs) {
		guard lhs == rhs else { return false }
	}
	return true
}

private func equal<A: Equatable, B: Equatable>(_ expectedValue: [(A, B)]?) -> Predicate<[(A, B)]> {
	return NonNilMatcherFunc { actualExpression, failureMessage in
		failureMessage.postfixMessage = "equal <\(stringify(expectedValue))>"
		let actualValue = try actualExpression.evaluate()
		if expectedValue == nil || actualValue == nil {
			if expectedValue == nil {
				failureMessage.postfixActual = " (use beNil() to match nils)"
			}
			return false
		}
		return expectedValue! == actualValue!
	}.predicate
}

private func ==<A: Equatable, B: Equatable>(lhs: Expectation<[(A, B)]>, rhs: [(A, B)]) {
	lhs.to(equal(rhs))
}

class ResolverSpec: QuickSpec {
	override func spec() {
		itBehavesLike(ResolverBehavior.self) { () in Resolver.self }
		// TODO: Will uncomment when the new resolver is checked in
		// itBehavesLike(ResolverBehavior.self) { () in NewResolver.self }
	}
}

class ResolverBehavior: Behavior<ResolverProtocol.Type> {
	override static func spec(_ aContext: @escaping () -> ResolverProtocol.Type) {
		let resolverType = aContext()

		describe("\(resolverType)") {

			it("should resolve a simple Cartfile") {
				let db: DB = [
					github1: [
						.v0_1_0: [
							github2: .compatibleWith(.v1_0_0),
						],
					],
					github2: [
						.v1_0_0: [:],
					],
					]

				let resolved = db.resolve(resolverType, [ github1: .exactly(.v0_1_0) ])
				expect(resolved.value!) == [
					github2: .v1_0_0,
					github1: .v0_1_0,
				]
			}

			it("should resolve to the latest matching versions") {
				let db: DB = [
					github1: [
						.v0_1_0: [
							github2: .compatibleWith(.v1_0_0),
						],
						.v1_0_0: [
							github2: .compatibleWith(.v2_0_0),
						],
						.v1_1_0: [
							github2: .compatibleWith(.v2_0_0),
						],
					],
					github2: [
						.v1_0_0: [:],
						.v2_0_0: [:],
						.v2_0_1: [:],
					],
					]

				let resolved = db.resolve(resolverType, [ github1: .any ])
				expect(resolved.value!) == [
					github2: .v2_0_1,
					github1: .v1_1_0,
				]
			}

			it("should resolve a subset when given specific dependencies") {
				let db: DB = [
					github1: [
						.v1_0_0: [
							github2: .compatibleWith(.v1_0_0),
						],
						.v1_1_0: [
							github2: .compatibleWith(.v1_0_0),
						],
					],
					github2: [
						.v1_0_0: [ github3: .compatibleWith(.v1_0_0) ],
						.v1_1_0: [ github3: .compatibleWith(.v1_0_0) ],
					],
					github3: [
						.v1_0_0: [:],
						.v1_1_0: [:],
						.v1_2_0: [:],
					],
					git1: [
						.v1_0_0: [:],
					],
					]

				let resolved = db.resolve(resolverType,
										  [
											github1: .any,
											// Newly added dependencies which are not inclued in the
											// list should not be resolved.
											git1: .any,
											],
										  resolved: [ github1: .v1_0_0, github2: .v1_0_0, github3: .v1_0_0 ],
										  updating: [ github2 ]
				)
				expect(resolved.value!) == [
					github3: .v1_2_0,
					github2: .v1_1_0,
					github1: .v1_0_0,
				]
			}

			it("should fail when given incompatible nested version specifiers") {
				let db: DB = [
					github1: [
						.v1_0_0: [
							git1: .compatibleWith(.v1_0_0),
							github2: .any,
						],
					],
					github2: [
						.v1_0_0: [
							git1: .compatibleWith(.v2_0_0),
						],
					],
					git1: [
						.v1_0_0: [:],
						.v1_1_0: [:],
						.v2_0_0: [:],
						.v2_0_1: [:],
					]
				]
				let resolved = db.resolve(resolverType, [github1: .any])
				expect(resolved.value).to(beNil())
				expect(resolved.error).notTo(beNil())
			}

			it("should correctly resolve when specifiers intersect") {
				let db: DB = [
					github1: [
						.v1_0_0: [
							github2: .compatibleWith(.v1_0_0)
						]
					],
					github2: [
						.v1_0_0: [:],
						.v2_0_0: [:]
					]
				]

				let resolved = db.resolve(resolverType, [ github1: .any, github2: .atLeast(.v1_0_0) ])
				expect(resolved.value!) == [
					github1: .v1_0_0,
					github2: .v1_0_0
				]
			}

			// Only the new resolver passes the following tests. Will change to non-pending when checked in
			pending("should resolve a subset when given specific dependencies that have constraints") {
				let db: DB = [
					github1: [
						.v1_0_0: [
							github2: .compatibleWith(.v1_0_0),
						],
						.v1_1_0: [
							github2: .compatibleWith(.v1_0_0),
						],
						.v2_0_0: [
							github2: .compatibleWith(.v2_0_0),
						],
					],
					github2: [
						.v1_0_0: [ github3: .compatibleWith(.v1_0_0) ],
						.v1_1_0: [ github3: .compatibleWith(.v1_0_0) ],
						.v2_0_0: [:],
					],
					github3: [
						.v1_0_0: [:],
						.v1_1_0: [:],
						.v1_2_0: [:],
					],
					]

				let resolved = db.resolve(resolverType,
										  [ github1: .any ],
										  resolved: [ github1: .v1_0_0, github2: .v1_0_0, github3: .v1_0_0 ],
										  updating: [ github2 ]
				)
				expect(resolved.value!) == [
					github3: .v1_2_0,
					github2: .v1_1_0,
					github1: .v1_0_0,
				]
			}


			pending("should fail when the only valid graph is not in the specified dependencies") {
				let db: DB = [
					github1: [
						.v1_0_0: [
							github2: .compatibleWith(.v1_0_0),
						],
						.v1_1_0: [
							github2: .compatibleWith(.v1_0_0),
						],
						.v2_0_0: [
							github2: .compatibleWith(.v2_0_0),
						],
					],
					github2: [
						.v1_0_0: [ github3: .compatibleWith(.v1_0_0) ],
						.v1_1_0: [ github3: .compatibleWith(.v1_0_0) ],
						.v2_0_0: [:],
					],
					github3: [
						.v1_0_0: [:],
						.v1_1_0: [:],
						.v1_2_0: [:],
					],
					]
				let resolved = db.resolve(resolverType,
										  [ github1: .exactly(.v2_0_0) ],
										  resolved: [ github1: .v1_0_0, github2: .v1_0_0, github3: .v1_0_0 ],
										  updating: [ github2 ]
				)
				expect(resolved.value).to(beNil())
				expect(resolved.error).notTo(beNil())
			}

			it("should resolve a Cartfile whose dependency is specified by both a branch name and a SHA which is the HEAD of that branch") {
				let branch = "development"
				let sha = "8ff4393ede2ca86d5a78edaf62b3a14d90bffab9"

				var db: DB = [
					github1: [
						.v1_0_0: [
							github2: .any,
							github3: .gitReference(sha),
						],
					],
					github2: [
						.v1_0_0: [
							github3: .gitReference(branch),
						],
					],
					github3: [
						.v1_0_0: [:],
					],
					]
				db.references = [
					github3: [
						branch: PinnedVersion(sha),
						sha: PinnedVersion(sha),
					],
				]

				let resolved = db.resolve(resolverType, [ github1: .any, github2: .any ])
				expect(resolved.value!) == [
					github3: PinnedVersion(sha),
					github2: .v1_0_0,
					github1: .v1_0_0,
				]
			}

			it("should correctly order transitive dependencies") {
				let db: DB = [
					github1: [
						.v1_0_0: [
							github2: .any,
							github3: .any,
						],
					],
					github2: [
						.v1_0_0: [
							github3: .any,
							git1: .any,
						],
					],
					github3: [
						.v1_0_0: [ git2: .any ],
					],
					git1: [
						.v1_0_0: [ github3: .any ],
					],
					git2: [
						.v1_0_0: [:],
					],
					]

				let resolved = db.resolve(resolverType, [ github1: .any ])
				expect(resolved.value!) == [
					git2: .v1_0_0,
					github3: .v1_0_0,
					git1: .v1_0_0,
					github2: .v1_0_0,
					github1: .v1_0_0,
				]
			}

			pending("should fail if no versions match the requirements and prerelease versions exist") {
				let db: DB = [
					github1: [
						.v1_0_0: [:],
						.v2_0_0_beta_1: [:],
						.v2_0_0: [:],
						.v3_0_0_beta_1: [:],
					],
					]

				do {
					let resolved = db.resolve(resolverType, [ github1: .atLeast(.v3_0_0) ])
					expect(resolved.value).to(beNil())
					expect(resolved.error).notTo(beNil())
				}
				
				do {
					let resolved = db.resolve(resolverType, [ github1: .compatibleWith(.v3_0_0) ])
					expect(resolved.value).to(beNil())
					expect(resolved.error).notTo(beNil())
				}
				
				do {
					let resolved = db.resolve(resolverType, [ github1: .exactly(.v3_0_0) ])
					expect(resolved.value).to(beNil())
					expect(resolved.error).notTo(beNil())
				}
			}
		}
	}
}
