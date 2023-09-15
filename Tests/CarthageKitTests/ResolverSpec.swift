import CarthageKit
import Foundation
import Nimble
import Quick
import ReactiveSwift
import Result
import Tentacle

private func ==<A: Equatable, B: Equatable>(lhs: [(A, B)], rhs: [(A, B)]) -> Bool {
	guard lhs.count == rhs.count else { return false }
	for (lhs, rhs) in zip(lhs, rhs) {
		guard lhs == rhs else { return false }
	}
	return true
}

private func equal<A: Equatable, B: Equatable>(_ expectedValue: [(A, B)]?) -> Nimble.Predicate<[(A, B)]> {
	return Predicate.define("equal <\(stringify(expectedValue))>") { actualExpression, message in
		let actualValue = try actualExpression.evaluate()
		if expectedValue == nil || actualValue == nil {
			if expectedValue == nil {
				return PredicateResult(status: .fail, message: message.appendedBeNilHint())
			}
			return PredicateResult(status: .fail, message: message)
		}
		return PredicateResult(bool: expectedValue! == actualValue!, message: message)
	}
}

private func ==<A: Equatable, B: Equatable>(lhs: Expectation<[(A, B)]>, rhs: [(A, B)]) {
	lhs.to(equal(rhs))
}

class ResolverSpec: QuickSpec {
	override func spec() {
		itBehavesLike(ResolverBehavior.self) { () in Resolver.self }
		itBehavesLike(ResolverBehavior.self) { () in NewResolver.self }
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

			it("should update a dependency that is in the root list and nested when the parent is marked for update") {
				let db: DB = [
					github1: [
						.v1_0_0: [
							git1: .compatibleWith(.v1_0_0)
						]
					],
					git1: [
						.v1_0_0: [:],
						.v1_1_0: [:]
					]
				]

				let resolved = db.resolve(resolverType,
				                          [ github1: .any, git1: .any],
				                          resolved: [ github1: .v1_0_0, git1: .v1_0_0 ],
				                          updating: [ github1 ])
				expect(resolved.value!) == [
					github1: .v1_0_0,
					git1: .v1_1_0
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

			// Only the new resolver passes the following tests.
			if resolverType == NewResolver.self {
				it("should resolve a subset when given specific dependencies that have constraints") {
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


				it("should fail when the only valid graph is not in the specified dependencies") {
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
