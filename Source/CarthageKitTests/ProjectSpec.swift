//
//  ProjectSpec.swift
//  Carthage
//
//  Created by Robert Böhnke on 27/12/14.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

@testable import CarthageKit
import Foundation
import Nimble
import Quick
import ReactiveSwift
import Tentacle

class ProjectSpec: QuickSpec {
	override func spec() {
		describe("determineBinaryCompatibility") {
			it("should pass through Swift framework URLs with the correct Swift version") {
				let framework = "Quick.framework"
				let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
				let frameworkURL = currentDirectory.appendingPathComponent(framework)

				let result = Project(directoryURL: Bundle(for: type(of: self)).bundleURL).compatibleFrameworkURL(frameworkURL).single()

				expect(result?.value) == frameworkURL
			}

			it("should throw an error when the Swift framework has the incorrect Swift version") {
				let frameworkURL = Bundle(for: type(of: self)).url(forResource: "FakeOldSwift.framework", withExtension: nil)!
				let result = Project(directoryURL: Bundle(for: type(of: self)).bundleURL).compatibleFrameworkURL(frameworkURL).single()

				expect(result?.value).to(beNil())
				expect(result?.error) == CarthageError.internalError(description: SwiftVersionError.incompatibleFrameworkSwiftVersions(local: XcodeSpec.currentSwiftVersion, framework: "0.0.0").description)
			}

			it("should pass through ObjC framework URLs") {
				let frameworkURL = Bundle(for: type(of: self)).url(forResource: "FakeOldObjc.framework", withExtension: nil)!
				let result = Project(directoryURL: Bundle(for: type(of: self)).bundleURL).compatibleFrameworkURL(frameworkURL).single()

				expect(result?.value) == frameworkURL
			}
		}

		describe("loadCombinedCartfile") {
			it("should load a combined Cartfile when only a Cartfile is present") {
				let directoryURL = Bundle(for: type(of: self)).url(forResource: "CartfileOnly", withExtension: nil)!
				let result = Project(directoryURL: directoryURL).loadCombinedCartfile().single()
				expect(result).notTo(beNil())
				expect(result?.value).notTo(beNil())
				
				let dependencies = result?.value?.dependencies
				expect(dependencies?.count) == 1
				expect(dependencies?.first?.project.name) == "Carthage"
			}

			it("should load a combined Cartfile when only a Cartfile.private is present") {
				let directoryURL = Bundle(for: type(of: self)).url(forResource: "CartfilePrivateOnly", withExtension: nil)!
				let result = Project(directoryURL: directoryURL).loadCombinedCartfile().single()
				expect(result).notTo(beNil())
				expect(result?.value).notTo(beNil())

				let dependencies = result?.value?.dependencies
				expect(dependencies?.count) == 1
				expect(dependencies?.first?.project.name) == "Carthage"
			}

			it("should detect duplicate dependencies across Cartfile and Cartfile.private") {
				let directoryURL = Bundle(for: type(of: self)).url(forResource: "DuplicateDependencies", withExtension: nil)!
				let result = Project(directoryURL: directoryURL).loadCombinedCartfile().single()
				expect(result).notTo(beNil())

				let resultError = result?.error
				expect(resultError).notTo(beNil())

				let makeDependency: (String, String, [String]) -> DuplicateDependency = { (repoOwner, repoName, locations) in
					let project = ProjectIdentifier.gitHub(Repository(owner: repoOwner, name: repoName))
					return DuplicateDependency(project: project, locations: locations)
				}

				let locations = ["\(CarthageProjectCartfilePath)", "\(CarthageProjectPrivateCartfilePath)"]

				let expectedError = CarthageError.duplicateDependencies([
					makeDependency("1", "1", locations),
					makeDependency("3", "3", locations),
					makeDependency("5", "5", locations),
				])

				expect(resultError) == expectedError
			}
			
			it("should error when neither a Cartfile nor a Cartfile.private exists") {
				let directoryURL = Bundle(for: type(of: self)).url(forResource: "NoCartfile", withExtension: nil)!
				let result = Project(directoryURL: directoryURL).loadCombinedCartfile().single()
				expect(result).notTo(beNil())
				
				if case let .readFailed(_, underlyingError)? = result?.error {
					expect(underlyingError?.domain) == NSCocoaErrorDomain
					expect(underlyingError?.code) == NSFileReadNoSuchFileError
				} else {
					fail()
				}
			}
		}

		describe("cloneOrFetchProject") {
			// https://github.com/Carthage/Carthage/issues/1191
			let temporaryPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
			let temporaryURL = URL(fileURLWithPath: temporaryPath, isDirectory: true)
			let repositoryURL = temporaryURL.appendingPathComponent("carthage1191", isDirectory: true)
			let cacheDirectoryURL = temporaryURL.appendingPathComponent("cache", isDirectory: true)
			let projectIdentifier = ProjectIdentifier.git(GitURL(repositoryURL.carthage_absoluteString))

			func initRepository() {
				expect { try FileManager.default.createDirectory(atPath: repositoryURL.carthage_path, withIntermediateDirectories: true) }.notTo(throwError())
				_ = launchGitTask([ "init" ], repositoryFileURL: repositoryURL).wait()
			}

			@discardableResult
			func addCommit() -> String {
				_ = launchGitTask([ "commit", "--allow-empty", "-m \"Empty commit\"" ], repositoryFileURL: repositoryURL).wait()
				return launchGitTask([ "rev-parse", "--short", "HEAD" ], repositoryFileURL: repositoryURL)
					.last()!
					.value!
					.trimmingCharacters(in: .newlines)
			}

			func cloneOrFetch(commitish: String? = nil) -> SignalProducer<(ProjectEvent?, URL), CarthageError> {
				return cloneOrFetchProject(projectIdentifier, preferHTTPS: false, destinationURL: cacheDirectoryURL, commitish: commitish)
			}

			func assertProjectEvent(commitish: String? = nil, clearFetchTime: Bool = true, action: @escaping (ProjectEvent?) -> ()) {
				waitUntil { done in
					if clearFetchTime {
						FetchCache.clearFetchTimes()
					}
					cloneOrFetch(commitish: commitish).start(Observer(
						value: { event, _ in action(event) },
						completed: done
					))
				}
			}

			beforeEach {
				expect { try FileManager.default.createDirectory(atPath: temporaryURL.carthage_path, withIntermediateDirectories: true) }.notTo(throwError())
				initRepository()
			}

			afterEach {
				_ = try? FileManager.default.removeItem(at: temporaryURL)
			}

			it("should clone a project if it is not cloned yet") {
				assertProjectEvent { expect($0?.isCloning) == true }
			}

			it("should fetch a project if no commitish is given") {
				// Clone first
				expect(cloneOrFetch().wait().error).to(beNil())

				assertProjectEvent { expect($0?.isFetching) == true }
			}

			it("should fetch a project if the given commitish does not exist in the cloned repository") {
				// Clone first
				addCommit()
				expect(cloneOrFetch().wait().error).to(beNil())

				let commitish = addCommit()

				assertProjectEvent(commitish: commitish) { expect($0?.isFetching) == true }
			}

			it("should fetch a project if the given commitish exists but that is a reference") {
				// Clone first
				addCommit()
				expect(cloneOrFetch().wait().error).to(beNil())

				addCommit()

				assertProjectEvent(commitish: "master") { expect($0?.isFetching) == true }
			}

			it("should not fetch a project if the given commitish exists but that is not a reference") {
				// Clone first
				let commitish = addCommit()
				expect(cloneOrFetch().wait().error).to(beNil())

				addCommit()

				assertProjectEvent(commitish: commitish) { expect($0).to(beNil()) }
			}

			it ("should not fetch twice in a row, even if no commitish is given") {
				// Clone first
				expect(cloneOrFetch().wait().error).to(beNil())

				assertProjectEvent { expect($0?.isFetching) == true }
				assertProjectEvent(clearFetchTime: false) { expect($0).to(beNil())}
			}
		}
	}
}

private extension ProjectEvent {
	var isCloning: Bool {
		if case .cloning = self {
			return true
		}
		return false
	}

	var isFetching: Bool {
		if case .fetching = self {
			return true
		}
		return false
	}
}
