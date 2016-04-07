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
import Result
import ReactiveTask
import Argo
import CryptoSwift

class ProjectSpec: QuickSpec {
	override func spec() {
		let directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("CartfilePrivateOnly", withExtension: nil)!

		describe("build cache") {
			let directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("ReactiveCocoaLayout", withExtension: nil)!
			let projectURL = directoryURL.URLByAppendingPathComponent("ReactiveCocoaLayout.xcodeproj")
			let buildFolderURL = directoryURL.URLByAppendingPathComponent(CarthageBinariesFolderPath)
			let targetFolderURL = NSURL(fileURLWithPath: (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent(NSProcessInfo.processInfo().globallyUniqueString), isDirectory: true)
			let dependenciesToBuild = ["Archimedes"]
			let platformsToBuild: Set<Platform> = [Platform.Mac]
			let project1 = Project(directoryURL: directoryURL)
			let macArchimedesBinaryPath = buildFolderURL.URLByAppendingPathComponent("Mac/Archimedes.framework").path!
			let archimedesBinaryURL = buildFolderURL.URLByAppendingPathComponent("Mac/Archimedes.framework/Archimedes")

			beforeEach {
				_ = try? NSFileManager.defaultManager().removeItemAtURL(buildFolderURL)

				expect { try NSFileManager.defaultManager().createDirectoryAtPath(targetFolderURL.path!, withIntermediateDirectories: true, attributes: nil) }.notTo(throwError())
				return
			}

			afterEach {
				_ = try? NSFileManager.defaultManager().removeItemAtURL(targetFolderURL)
				return
			}

			func build(project: Project, dependencies: [String], platforms: Set<Platform>) {
				_ = project.buildCheckedOutDependenciesWithConfiguration("Debug", dependenciesToBuild: ["Archimedes"], forPlatforms: platforms, derivedDataPath: nil)
					.flatten(.Concat)
					.wait()

				Task.waitForAllTaskTermination()
			}

			func cleanUp() {
				var isDirectory: ObjCBool = true
				if NSFileManager.defaultManager().fileExistsAtPath(macArchimedesBinaryPath, isDirectory: &isDirectory) {
					try! NSFileManager.defaultManager().removeItemAtPath(macArchimedesBinaryPath)
				}
			}

			func getSHA1() -> String {
				let frameworkData = NSData(contentsOfURL: archimedesBinaryURL)!
				return frameworkData.sha1()!.toHexString()
			}

			context("when the Cartfile.resolved has commitish for a repository and built framework") {

				beforeEach {
					cleanUp()
					build(project1, dependencies: dependenciesToBuild, platforms: platformsToBuild)
				}

				afterEach {
					cleanUp()
				}

				fit("it creates the version file when the build is created") {
					let macArchimedesVersionFileURL = buildFolderURL.URLByAppendingPathComponent("Mac/.Archimedes.version")
					let versionFileData = NSData(contentsOfURL: macArchimedesVersionFileURL)!
					let jsonObject: AnyObject = try! NSJSONSerialization.JSONObjectWithData(versionFileData, options: .AllowFragments)
					let versionFile: VersionFile? = decode(jsonObject)
					expect(versionFile?.commitish).to(equal("1.1.1"))
					expect(versionFile?.frameworkSHA1).to(equal(getSHA1()))
				}

				context("when the version file does not exist") {

					beforeEach {
						//remove the .version if it exists
//						let builtDirectoryParentURL = builtProductURL.URLByDeletingLastPathComponent
//						let versionFileURL = builtDirectoryParentURL.URLByAppendingPathComponent(".\(projectName).version")
					}

					it("should build the framework again") {
						//TODO
						//keep track of the existing framework's sha

						// build it again

						//assert that the built framework's sha is different
					}
				}

				context("when the commitish and framework sha matches the content of the version file") {
					//x
					it("should not rebuild the framework") {
						let oldSHA1 = getSHA1()

						//method under test
						build(project1, dependencies: dependenciesToBuild, platforms: platformsToBuild)

						let newSHA1 = getSHA1()
						expect(oldSHA1).to(equal(newSHA1))
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
