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
import ReactiveCocoa
import Tentacle
import Result
import ReactiveTask

class ProjectSpec: QuickSpec {
	override func spec() {
		describe("createAndCheckVersionFiles") {
			let directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("DependencyTest", withExtension: nil)!
			let buildDirectoryURL = directoryURL.appendingPathComponent(CarthageBinariesFolderPath)
			
			func buildDependencyTest(platforms platforms: Set<Platform> = [], ignoreCached: Bool = false) -> Set<String> {
				var builtSchemes: [String] = []
				
				let project = Project(directoryURL: directoryURL)
				let result = project.buildCheckedOutDependenciesWithOptions(BuildOptions(configuration: "Debug", platforms: platforms, ignoreCachedBuilds: ignoreCached))
					.flatten(.Concat)
					.ignoreTaskData()
					.on(next: { (project, scheme) in
						NSLog("Building scheme \"\(scheme)\" in \(project)")
						builtSchemes.append(scheme)
					})
					.wait()
				expect(result.error).to(beNil())
				
				return Set(builtSchemes)
			}
			
			func overwriteFramework(frameworkName: String, forPlatformName platformName: String, inDirectory buildDirectoryURL: NSURL) {
				let platformURL = buildDirectoryURL.appendingPathComponent(platformName, isDirectory: true)
				let frameworkURL = platformURL.appendingPathComponent("\(frameworkName).framework", isDirectory: false)
				let binaryURL = frameworkURL.appendingPathComponent(frameworkName, isDirectory: false)
				let binaryPath = binaryURL.path!
				
				let data = "junkdata".dataUsingEncoding(NSUTF8StringEncoding)!
				let result = data.writeToFile(binaryPath, atomically: true)
				expect(result).to(beTrue())
			}
			
			beforeEach {
				let _ = try? NSFileManager.defaultManager().removeItemAtURL(buildDirectoryURL)
			}
			
			it("should not rebuild cached frameworks unless instructed to ignore cached builds") {
				let expected: Set = ["Prelude-Mac", "Either-Mac", "Madness-Mac"]
				
				let result1 = buildDependencyTest(platforms: [.Mac])
				expect(result1).to(equal(expected))
				
				let result2 = buildDependencyTest(platforms: [.Mac])
				expect(result2).to(equal(Set<String>()))
				
				let result3 = buildDependencyTest(platforms: [.Mac], ignoreCached: true)
				expect(result3).to(equal(expected))
			}
			
			it("should rebuild cached frameworks (and dependencies) whose sha1 does not match the version file") {
				let expected: Set = ["Prelude-Mac", "Either-Mac", "Madness-Mac"]
				
				let result1 = buildDependencyTest(platforms: [.Mac])
				expect(result1).to(equal(expected))
				
				overwriteFramework("Prelude", forPlatformName: "Mac", inDirectory: buildDirectoryURL)
				
				let result2 = buildDependencyTest(platforms: [.Mac])
				expect(result2).to(equal(expected))
			}
			
			it("should rebuild cached frameworks (and dependencies) whose version does not match the version file") {
				let expected: Set = ["Prelude-Mac", "Either-Mac", "Madness-Mac"]
				
				let result1 = buildDependencyTest(platforms: [.Mac])
				expect(result1).to(equal(expected))
				
				let preludeVersionFileURL = buildDirectoryURL.appendingPathComponent(".Prelude.version", isDirectory: false)
				let preludeVersionFilePath = preludeVersionFileURL.path!
				
				let json = try! NSString(contentsOfURL: preludeVersionFileURL, encoding: NSUTF8StringEncoding)
				let modifiedJson = json.stringByReplacingOccurrencesOfString("\"commitish\" : \"1.6.0\"", withString: "\"commitish\" : \"1.6.1\"")
				let _ = try! modifiedJson.writeToFile(preludeVersionFilePath, atomically: true, encoding: NSUTF8StringEncoding)
				
				let result2 = buildDependencyTest(platforms: [.Mac])
				expect(result2).to(equal(expected))
			}
			
			it("should not rebuild cached frameworks unnecessarily") {
				let expected: Set = ["Prelude-Mac", "Either-Mac", "Madness-Mac"]
				
				let result1 = buildDependencyTest(platforms: [.Mac])
				expect(result1).to(equal(expected))
				
				overwriteFramework("Either", forPlatformName: "Mac", inDirectory: buildDirectoryURL)
				
				let result2 = buildDependencyTest(platforms: [.Mac])
				expect(result2).to(equal(["Either-Mac", "Madness-Mac"]))
			}
			
			it("should rebuild a framework for all platforms even a cached framework is invalid for only a single platform") {
				// This is a limitation of the current version file implementation: the frameworks for all platforms
				// are rebuilt even if only a single platform's framework is invalid because the platforms to build for
				// are not determined until later in the build process (if the platforms to build for are not specified
				// via build options).
				
				let expected: Set = ["Prelude-Mac", "Prelude-iOS", "Either-Mac", "Either-iOS", "Madness-Mac", "Madness-iOS"]
				
				let result1 = buildDependencyTest()
				expect(result1).to(equal(expected))
				
				overwriteFramework("Madness", forPlatformName: "Mac", inDirectory: buildDirectoryURL)
				
				let result2 = buildDependencyTest()
				expect(result2).to(equal(["Madness-Mac", "Madness-iOS"]))
			}
		}
		
		describe("loadCombinedCartfile") {
			it("should load a combined Cartfile when only a Cartfile is present") {
				let directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("CartfileOnly", withExtension: nil)!
				let result = Project(directoryURL: directoryURL).loadCombinedCartfile().single()
				expect(result).notTo(beNil())
				expect(result?.value).notTo(beNil())
				
				let dependencies = result?.value?.dependencies
				expect(dependencies?.count) == 1
				expect(dependencies?.first?.project.name) == "Carthage"
			}

			it("should load a combined Cartfile when only a Cartfile.private is present") {
				let directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("CartfilePrivateOnly", withExtension: nil)!
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
			
			it("should error when neither a Cartfile nor a Cartfile.private exists") {
				let directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("NoCartfile", withExtension: nil)!
				let result = Project(directoryURL: directoryURL).loadCombinedCartfile().single()
				expect(result).notTo(beNil())
				
				if case let .ReadFailed(_, underlyingError)? = result?.error {
					expect(underlyingError?.domain) == NSCocoaErrorDomain
					expect(underlyingError?.code) == NSFileReadNoSuchFileError
				} else {
					fail()
				}
			}
		}

		describe("cloneOrFetchProject") {
			// https://github.com/Carthage/Carthage/issues/1191
			let temporaryPath = (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent(NSProcessInfo.processInfo().globallyUniqueString)
			let temporaryURL = NSURL(fileURLWithPath: temporaryPath, isDirectory: true)
			let repositoryURL = temporaryURL.appendingPathComponent("carthage1191", isDirectory: true)
			let cacheDirectoryURL = temporaryURL.appendingPathComponent("cache", isDirectory: true)
			let projectIdentifier = ProjectIdentifier.Git(GitURL(repositoryURL.carthage_absoluteString))

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

			func assertProjectEvent(commitish commitish: String? = nil, clearFetchTime: Bool = true, action: ProjectEvent? -> ()) {
				waitUntil { done in
					if clearFetchTime {
						FetchCache.clearFetchTimes()
					}
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
