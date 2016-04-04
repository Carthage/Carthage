//
//  ProjectSpec.swift
//  Carthage
//
//  Created by Robert Böhnke on 27/12/14.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import Nimble
import Quick
import ReactiveCocoa
import Tentacle

class ProjectSpec: QuickSpec {
	override func spec() {
		let directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("CartfilePrivateOnly", withExtension: nil)!

		it("should load a combined Cartfile when only a Cartfile.private is present") {
			let result = Project(directoryURL: directoryURL).loadCombinedCartfile().single()
			expect(result).notTo(beNil())
			expect(result?.value).notTo(beNil())

			let dependencies = result?.value?.dependencies
			expect(dependencies?.count) == 1
			expect(dependencies?.first?.project.name) == "Carthage"
		}

        it("should detect duplicate dependencies across Cartfile and Cartfile.private") {
            let directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("DuplicateDependencies", withExtension: nil)!
            let result = Project(directoryURL: directoryURL).loadCombinedCartfile().single()
			expect(result).notTo(beNil())

			let resultError = result?.error
			expect(resultError).notTo(beNil())

			let makeDependency: (String, String, [String]) -> DuplicateDependency = { (repoOwner, repoName, locations) in
				let project = ProjectIdentifier.GitHub(Repository(owner: repoOwner, name: repoName))
				return DuplicateDependency(project: project, locations: locations)
			}

			let mainLocation = ["\(CarthageProjectCartfilePath)"]
			let bothLocations = ["\(CarthageProjectCartfilePath)", "\(CarthageProjectPrivateCartfilePath)"]

			let expectedError = CarthageError.DuplicateDependencies([
				makeDependency("self2", "self2", mainLocation),
				makeDependency("self3", "self3", mainLocation),
				makeDependency("1", "1", bothLocations),
				makeDependency("3", "3", bothLocations),
				makeDependency("5", "5", bothLocations),
			])

			expect(resultError) == expectedError
        }

		describe("build cache") {
			context("when the Cartfile.resolved has commitish for a repository and built framework") {
				beforeEach {
					//setup a directory with a Cartfile.resolved and a Carthage/Build folder with a built framework
				}

				context("when the version file does not exist") {
					it("should build the framework") {
						//TODO
						//keep track of the existing framework's sha

						//assert that the built framework's sha is different
					}

					it("should create a version file with the commitish") {
						//TODO
					}

					it("should create a version file with the sha of the built framework") {
						//TODO
					}
				}

				context("when the version file exists") {
					beforeEach {
						//add the version file with the commitish and the sha of the built framework
					}

					context("when the commitish and framework sha matches the content of the version file") {
						it("should not rebuild the framework") {
							//TODO
						}
					}

					context("when the commitish does not match the commitish in the version file") {
						it("should build the framework") {
							//TODO
						}
					}

					context("when the framework's sha does not match the sha in the version file") {
						it("should build the framework") {
							//TODO
						}
					}
				}
			}
		}

		describe("cloneOrFetchProject") {
			// https://github.com/Carthage/Carthage/issues/1191
			let temporaryPath = (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent(NSProcessInfo.processInfo().globallyUniqueString)
			let temporaryURL = NSURL(fileURLWithPath: temporaryPath, isDirectory: true)
			let repositoryURL = temporaryURL.URLByAppendingPathComponent("carthage1191", isDirectory: true)
			let cacheDirectoryURL = temporaryURL.URLByAppendingPathComponent("cache", isDirectory: true)
			let projectIdentifier = ProjectIdentifier.Git(GitURL(repositoryURL.absoluteString))

			func initRepository() {
				expect { try NSFileManager.defaultManager().createDirectoryAtPath(repositoryURL.path!, withIntermediateDirectories: true, attributes: nil) }.notTo(throwError())
				_ = launchGitTask([ "init" ], repositoryFileURL: repositoryURL).wait()
			}

			func addCommit() -> String {
				_ = launchGitTask([ "commit", "--allow-empty", "-m \"Empty commit\"" ], repositoryFileURL: repositoryURL).wait()
				return launchGitTask([ "rev-parse", "--short", "HEAD" ], repositoryFileURL: repositoryURL)
					.last()!
					.value!
					.stringByTrimmingCharactersInSet(.newlineCharacterSet())
			}

			func cloneOrFetch(commitish commitish: String? = nil) -> SignalProducer<(ProjectEvent?, NSURL), CarthageError> {
				return cloneOrFetchProject(projectIdentifier, preferHTTPS: false, destinationURL: cacheDirectoryURL, commitish: commitish)
			}

			func assertProjectEvent(commitish commitish: String? = nil, action: ProjectEvent? -> ()) {
				waitUntil { done in
					cloneOrFetch(commitish: commitish).start(Observer(
						completed: done,
						next: { event, _ in action(event) }
					))
				}
			}

			beforeEach {
				expect { try NSFileManager.defaultManager().createDirectoryAtPath(temporaryURL.path!, withIntermediateDirectories: true, attributes: nil) }.notTo(throwError())
				initRepository()
			}

			afterEach {
				_ = try? NSFileManager.defaultManager().removeItemAtURL(temporaryURL)
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
		}
	}
}

private extension ProjectEvent {
	var isCloning: Bool {
		if case .Cloning = self {
			return true
		}
		return false
	}

	var isFetching: Bool {
		if case .Fetching = self {
			return true
		}
		return false
	}
}
