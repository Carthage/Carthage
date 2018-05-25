@testable import CarthageKit
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

private func equal<A: Equatable, B: Equatable>(_ expectedValue: [(A, B)]?) -> Predicate<[(A, B)]> {
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
		itBehavesLike(ResolverBehavior.self) { () in BackTrackingResolver.self }
	}
}

class ResolverBehavior: Behavior<ResolverProtocol.Type> {
	override static func spec(_ aContext: @escaping () -> ResolverProtocol.Type) {
		let resolverClass = aContext()
		
		describe("\(resolverClass)") {

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

				let resolved = db.resolve(resolverClass, [ github1: .exactly(.v0_1_0) ])
				
				switch resolved {
				case .success(let value):
					expect(value) == [
						github2: .v1_0_0,
						github1: .v0_1_0,
					]
				case .failure(let error):
					fail("Expected no error to occur: \(error)")
				}
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

				let resolved = db.resolve(resolverClass, [ github1: .any ])
				
				switch resolved {
				case .success(let value):
					expect(value) == [
						github2: .v2_0_1,
						github1: .v1_1_0,
					]
				case .failure(let error):
					fail("Expected no error to occur: \(error)")
				}
			}

			it("should resolve a subset when given specific dependencies") {
				let db: DB = [
					github1: [
						.v1_0_0: [
							github2: .compatibleWith(.v1_0_0),
							github4: .compatibleWith(.v1_0_0),
						],
						.v1_1_0: [
							github2: .compatibleWith(.v1_0_0),
							github4: .compatibleWith(.v1_0_0),
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
					github4: [
						.v1_0_0: [:],
						.v1_1_0: [:],
						.v1_2_0: [:],
					],
					git1: [
						.v1_0_0: [:],
					],
					]

				let resolved = db.resolve(resolverClass,
										  [
											github1: .any,
											// Newly added dependencies which are not inclued in the
											// list should not be resolved.
											git1: .any,
											],
						                  resolved: [ github1: .v1_0_0, github2: .v1_0_0, github3: .v1_0_0, github4: .v1_0_0 ],
										  updating: [ github2 ]
				)
				
				switch resolved {
				case .success(let value):
					expect(value) == [
						github4: .v1_0_0,
						github3: .v1_2_0,
						github2: .v1_1_0,
						github1: .v1_0_0,
					]
				case .failure(let error):
					fail("Expected no error to occur: \(error)")
				}
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

				let resolved = db.resolve(resolverClass,
				                          [ github1: .any, git1: .any],
				                          resolved: [ github1: .v1_0_0, git1: .v1_0_0 ],
				                          updating: [ github1 ])
				
				switch resolved {
				case .success(let value):
					expect(value) == [
						github1: .v1_0_0,
						git1: .v1_1_0
					]
				case .failure(let error):
					fail("Expected no error to occur: \(error)")
				}
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
				let resolved = db.resolve(resolverClass, [github1: .any])
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

				let resolved = db.resolve(resolverClass, [ github1: .any, github2: .atLeast(.v1_0_0) ])
				
				switch resolved {
				case .success(let value):
					expect(value) == [
						github1: .v1_0_0,
						github2: .v1_0_0
					]
				case .failure(let error):
					fail("Expected no error to occur: \(error)")
				}
			}

			it("should fail on incompatible dependencies") {
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
						.v1_0_0: [ github3: .compatibleWith(.v2_0_0) ],
						.v2_0_0: [ github3: .compatibleWith(.v2_0_0) ],
					],
					github3: [
						.v1_0_0: [:],
						.v2_0_0: [:],
					],
				]

				let resolved = db.resolve(resolverClass, [ github1: .any, github2: .compatibleWith(.v1_0_0), github3: .compatibleWith(.v1_0_0) ])
				expect(resolved.value).to(beNil())
				expect(resolved.error).notTo(beNil())
			}

			pending("should correctly resolve the latest version") {
				
				let testCartfileURL = Bundle(for: ResolverBehavior.self).url(forResource: "Resolver/LatestVersion/Cartfile", withExtension: "")!
				let projectDirectoryURL = testCartfileURL.deletingLastPathComponent()
				let repositoryURL = projectDirectoryURL.appendingPathComponent("Repository")
				
				let project = Project(directoryURL: projectDirectoryURL)
				let repository = LocalRepository(directoryURL: repositoryURL)
				
				let signalProducer = project.resolveUpdatedDependencies(from: repository,
																		resolverType: ResolverType.from(resolverClass: resolverClass)!,
																		dependenciesToUpdate: nil)
				do {
					let resolvedCartfile = try signalProducer.first()!.dematerialize()
					
					if let facebookDependency = resolvedCartfile.dependencies.first(where: { $0.key.name == "facebook-ios-sdk" }) {
						expect(facebookDependency.value.commitish) == "4.33.0"
					} else {
						fail("Expected facebook dependency to be present")
					}

					//Should not throw an error
					_ = try project.buildOrderForResolvedCartfile(resolvedCartfile).first()?.dematerialize()
					
				} catch(let error) {
					fail("Unexpected error thrown: \(error)")
				}
			}

			// Only the new resolver and fast resolvers pass the following tests.
			if resolverClass == NewResolver.self || resolverClass == BackTrackingResolver.self {
				it("should correctly resolve complex conflicting dependencies") {
					
					let testCartfileURL = Bundle(for: ResolverBehavior.self).url(forResource: "Resolver/ConflictingDependencies/Cartfile", withExtension: "")!
					let projectDirectoryURL = testCartfileURL.deletingLastPathComponent()
					let repositoryURL = projectDirectoryURL.appendingPathComponent("Repository")
					
					let project = Project(directoryURL: projectDirectoryURL)
					let repository = LocalRepository(directoryURL: repositoryURL)
					
					let signalProducer = project.resolveUpdatedDependencies(from: repository,
																			resolverType: ResolverType.from(resolverClass: resolverClass)!,
																			dependenciesToUpdate: nil)
					do {
						_ = try signalProducer.first()?.dematerialize()
						fail("Expected incompatibility error to be thrown")
					} catch(let error) {
						print("Caught error: \(error)")
						switch error {
						case CarthageError.incompatibleRequirements(_, _, _):
							return
						default:
							break
						}
						fail("Expected incompatibleRequirements error to be thrown")
					}
				}
				
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

					let resolved = db.resolve(resolverClass,
					                          [ github1: .any ],
					                          resolved: [ github1: .v1_0_0, github2: .v1_0_0, github3: .v1_0_0 ],
					                          updating: [ github2 ]
					)
					
					switch resolved {
					case .success(let value):
						expect(value) == [
							github3: .v1_2_0,
							github2: .v1_1_0,
							github1: .v1_0_0,
						]
					case .failure(let error):
						fail("Expected no error to occur: \(error)")
					}
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
					let resolved = db.resolve(resolverClass,
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

				let resolved = db.resolve(resolverClass, [ github1: .any, github2: .any ])
				
				switch resolved {
				case .success(let value):
					expect(value) == [
						github3: PinnedVersion(sha),
						github2: .v1_0_0,
						github1: .v1_0_0,
					]
				case .failure(let error):
					fail("Expected no error to occur: \(error)")
				}
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

				let resolved = db.resolve(resolverClass, [ github1: .any ])
				
				switch resolved {
				case .success(let value):
					expect(value) == [
						git2: .v1_0_0,
						github3: .v1_0_0,
						git1: .v1_0_0,
						github2: .v1_0_0,
						github1: .v1_0_0,
					]
				case .failure(let error):
					fail("Expected no error to occur: \(error)")
				}
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
					let resolved = db.resolve(resolverClass, [ github1: .atLeast(.v3_0_0) ])
					expect(resolved.value).to(beNil())
					expect(resolved.error).notTo(beNil())
				}
				
				do {
					let resolved = db.resolve(resolverClass, [ github1: .compatibleWith(.v3_0_0) ])
					expect(resolved.value).to(beNil())
					expect(resolved.error).notTo(beNil())
				}
				
				do {
					let resolved = db.resolve(resolverClass, [ github1: .exactly(.v3_0_0) ])
					expect(resolved.value).to(beNil())
					expect(resolved.error).notTo(beNil())
				}
			}
		}
		
		if resolverClass == BackTrackingResolver.self {

			it("should fail on cyclic dependencies") {
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
					],
					github3: [
						.v1_0_0: [ github1: .compatibleWith(.v1_0_0)],
					],
					]
				
				let resolved = db.resolve(resolverClass, [ github1: .any, github2: .any ])
				expect(resolved.value).to(beNil())
				expect(resolved.error).notTo(beNil())
				if let error = resolved.error {
					switch error {
					case .dependencyCycle(_):
						print("Dependency cycle error: \(error)")
					default:
						fail("Expected error to be of type .dependencyCycle")
					}
				}
			}

			it("should correctly resolve items with conflicting names, giving precedence to pinned versions") {
				let testCartfileURL = Bundle(for: ResolverBehavior.self).url(forResource: "Resolver/ConflictingNames/Cartfile", withExtension: "")!
				let projectDirectoryURL = testCartfileURL.deletingLastPathComponent()
				let repositoryURL = projectDirectoryURL.appendingPathComponent("Repository")

				let project = Project(directoryURL: projectDirectoryURL)
				let repository = LocalRepository(directoryURL: repositoryURL)

				let signalProducer = project.resolveUpdatedDependencies(from: repository,
																		resolverType: ResolverType.from(resolverClass: resolverClass)!,
																		dependenciesToUpdate: nil)
				do {
					let resolvedCartfile = try signalProducer.first()!.dematerialize()

					if let kissXMLDependency = resolvedCartfile.dependencies.first(where: { $0.key.name == "KissXML" }) {
						expect(kissXMLDependency.value.commitish) == "88665bed750e0fec9ad8e1ffc992b5b3812008d3"
					} else {
						fail("Expected kissXMLDependency dependency to be present")
					}

					//Should not throw an error
					_ = try project.buildOrderForResolvedCartfile(resolvedCartfile).first()?.dematerialize()

				} catch(let error) {
					fail("Unexpected error thrown: \(error)")
				}
			}
		}
	}
}
