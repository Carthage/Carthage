@testable import CarthageKit
import Foundation
import Nimble
import Quick
import ReactiveSwift
import Tentacle
import Result
import ReactiveTask
import XCDBLD

// swiftlint:disable:this force_try

private enum ProjectSpecError: Error {
    case assertion(message: String)
}

class ProjectSpec: QuickSpec {
	override func spec() {
		describe("buildCheckedOutDependenciesWithOptions") {
            guard let directoryURL = Bundle(for: type(of: self)).url(forResource: "DependencyTest", withExtension: nil) else {
                fail("Could not load DependencyTest from resources")
                return
            }
			let buildDirectoryURL = directoryURL.appendingPathComponent(Constants.binariesFolderPath)

            guard let noSharedSchemesDirectoryURL = Bundle(for: type(of: self)).url(forResource: "NoSharedSchemesTest", withExtension: nil) else {
                fail("Could not load NoSharedSchemesTest from resources")
                return
            }
			let noSharedSchemesBuildDirectoryURL = noSharedSchemesDirectoryURL.appendingPathComponent(Constants.binariesFolderPath)

			func build(directoryURL url: URL, platforms: Set<Platform> = [], cacheBuilds: Bool = true, dependenciesToBuild: [String]? = nil) -> [String] {
				let project = Project(directoryURL: url)
				let result = project.buildCheckedOutDependenciesWithOptions(BuildOptions(configuration: "Debug", platforms: platforms, cacheBuilds: cacheBuilds), dependenciesToBuild: dependenciesToBuild)
					.ignoreTaskData()
					.on(value: { project, scheme in
						NSLog("Building scheme \"\(scheme)\" in \(project)")
					})
					.map { _, scheme in scheme }
					.collect()
					.single()!
				expect(result.error).to(beNil())

				return result.value!.map { $0.name }
			}

			func buildDependencyTest(platforms: Set<Platform> = [], cacheBuilds: Bool = true, dependenciesToBuild: [String]? = nil) -> [String] {
				return build(directoryURL: directoryURL, platforms: platforms, cacheBuilds: cacheBuilds, dependenciesToBuild: dependenciesToBuild)
			}

			func buildNoSharedSchemesTest(platforms: Set<Platform> = [], cacheBuilds: Bool = true, dependenciesToBuild: [String]? = nil) -> [String] {
				return build(directoryURL: noSharedSchemesDirectoryURL, platforms: platforms, cacheBuilds: cacheBuilds, dependenciesToBuild: dependenciesToBuild)
			}

			beforeEach {
				_ = try? FileManager.default.removeItem(at: buildDirectoryURL)
				// Pre-fetch the repos so we have a cache for the given tags
				let sourceRepoUrl = directoryURL.appendingPathComponent("SourceRepos")
				for repo in ["TestFramework1", "TestFramework2", "TestFramework3"] {
					let urlPath = sourceRepoUrl.appendingPathComponent(repo).path
					_ = cloneOrFetch(dependency: .git(GitURL(urlPath)), preferHTTPS: false)
						.wait()
				}
			}

			it("should build frameworks in the correct order") {
				let macOSexpected = ["TestFramework3_Mac", "TestFramework2_Mac", "TestFramework1_Mac"]
				let iOSExpected = ["TestFramework3_iOS", "TestFramework2_iOS", "TestFramework1_iOS"]

				let result = buildDependencyTest(platforms: [], cacheBuilds: false)

				expect(result.filter { $0.contains("Mac") }) == macOSexpected
				expect(result.filter { $0.contains("iOS") }) == iOSExpected
				expect(Set(result)) == Set<String>(macOSexpected + iOSExpected)
			}

			it("should determine build order without repo cache") {
				let macOSexpected = ["TestFramework3_Mac", "TestFramework2_Mac", "TestFramework1_Mac"]
				for dep in ["TestFramework3", "TestFramework2", "TestFramework1"] {
					_ = try? FileManager.default.removeItem(at: Constants.Dependency.repositoriesURL.appendingPathComponent(dep))
				}
				// Without the repo cache, it won't know to build frameworks 2 and 3 unless it reads the Cartfile from the checkout directory
				let result = buildDependencyTest(platforms: [.macOS], cacheBuilds: false, dependenciesToBuild: ["TestFramework1"])
				expect(result) == macOSexpected
			}

			it("should fall back to repo cache if checkout is missing") {
				let macOSexpected = ["TestFramework3_Mac", "TestFramework2_Mac"]
				let repoDir = directoryURL.appendingPathComponent(carthageProjectCheckoutsPath)
				let checkout = repoDir.appendingPathComponent("TestFramework1")
				let tmpCheckout = repoDir.appendingPathComponent("TestFramework1_BACKUP")
                do {
                    try FileManager.default.moveItem(at: checkout, to: tmpCheckout)
                } catch {
                    fail("Could not move checkout to tmpCheckout: \(error)")
                    return
                }

				// Without the checkout, it should still figure out it needs to build 2 and 3.
				let result = buildDependencyTest(platforms: [.macOS], cacheBuilds: false)
				expect(result) == macOSexpected
                do {
                    try FileManager.default.moveItem(at: tmpCheckout, to: checkout)
                } catch {
                    fail("Could not move tmpCheckout to checkout: \(error)")
                    return
                }
			}

			describe("createAndCheckVersionFiles") {
				func overwriteFramework(_ frameworkName: String, forPlatformName platformName: String, inDirectory buildDirectoryURL: URL) throws {
					let platformURL = buildDirectoryURL.appendingPathComponent(platformName, isDirectory: true)
					let frameworkURL = platformURL.appendingPathComponent("\(frameworkName).framework", isDirectory: false)
					let binaryURL = frameworkURL.appendingPathComponent("\(frameworkName)", isDirectory: false)

					let data = "junkdata".data(using: .utf8)!
					try data.write(to: binaryURL, options: .atomic)
				}

				func overwriteSwiftVersion(
					_ frameworkName: String,
					forPlatformName platformName: String,
					inDirectory buildDirectoryURL: URL,
					withVersion version: String) throws
				{
					let platformURL = buildDirectoryURL.appendingPathComponent(platformName, isDirectory: true)
					let frameworkURL = platformURL.appendingPathComponent("\(frameworkName).framework", isDirectory: false)
                    guard let swiftHeaderURL = frameworkURL.swiftHeaderURL() else {
                        throw ProjectSpecError.assertion(message: "Could not get Swift header URL")
                    }

                    guard let swiftVersionResult = swiftVersion().first() else {
                        throw ProjectSpecError.assertion(message: "Expected at least one swift version to be present")
                    }
					expect(swiftVersionResult.error).to(beNil())

                    var header = try String(contentsOf: swiftHeaderURL)

					// Sanitize “effective-3.2 ” value.
					if
						let effectiveVersionRegex = try? NSRegularExpression(pattern: "effective-[0-9.]+ "),
						let match = effectiveVersionRegex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
						let effectiveVersionRange = Range(match.range(at: 0), in: header)
					{
						header.replaceSubrange(effectiveVersionRange, with: "")
					}

					let versionRange = header.range(of: swiftVersionResult.value!)!
					header.replaceSubrange(versionRange, with: version)

					try header.write(to: swiftHeaderURL, atomically: true, encoding: header.fastestEncoding)
				}

				func removeDsym(
					_ frameworkName: String,
					forPlatformName platformName: String,
					inDirectory buildDirectoryURL: URL) -> Bool
				{
					let platformURL = buildDirectoryURL.appendingPathComponent(platformName, isDirectory: true)
					let dSYMURL = platformURL
						.appendingPathComponent("\(frameworkName).framework.dSYM", isDirectory: true)

					do {
						try FileManager.default.removeItem(at: dSYMURL)
						return true
					}
					catch {
						return false
					}
				}

				it("should not rebuild cached frameworks unless instructed to ignore cached builds") {
					let expected = ["TestFramework3_Mac", "TestFramework2_Mac", "TestFramework1_Mac"]

					let result1 = buildDependencyTest(platforms: [.macOS])
					expect(result1) == expected

					let result2 = buildDependencyTest(platforms: [.macOS])
					expect(result2) == []

					let result3 = buildDependencyTest(platforms: [.macOS], cacheBuilds: false)
					expect(result3) == expected
				}

				it("should rebuild cached frameworks (and dependencies) whose hash does not match the version file") {
					let expected = ["TestFramework3_Mac", "TestFramework2_Mac", "TestFramework1_Mac"]

					let result1 = buildDependencyTest(platforms: [.macOS])
					expect(result1) == expected

                    do {
                        try overwriteFramework("TestFramework3", forPlatformName: "Mac", inDirectory: buildDirectoryURL)
                    } catch {
                        fail("Could not overwrite framework: \(error)")
                        return
                    }

					let result2 = buildDependencyTest(platforms: [.macOS])
					expect(result2) == expected
				}

				it("should rebuild cached frameworks (and dependencies) whose version does not match the version file") {
					let expected = ["TestFramework3_Mac", "TestFramework2_Mac", "TestFramework1_Mac"]

					let result1 = buildDependencyTest(platforms: [.macOS])
					expect(result1) == expected

					let preludeVersionFileURL = buildDirectoryURL.appendingPathComponent(".TestFramework3.version", isDirectory: false)
					let preludeVersionFilePath = preludeVersionFileURL.path

                    guard let json = try? String(contentsOf: preludeVersionFileURL, encoding: .utf8) else {
                        fail("Could not load preludeVersionFile")
                        return
                    }
					let modifiedJson = json.replacingOccurrences(of: "\"commitish\" : \"v1.0\"", with: "\"commitish\" : \"v1.1\"")
                    do {
                        _ = try modifiedJson.write(toFile: preludeVersionFilePath, atomically: true, encoding: .utf8)
                    } catch {
                        fail("Could not write modified json to file: \(error)")
                        return
                    }

					let result2 = buildDependencyTest(platforms: [.macOS])
					expect(result2) == expected
				}

				it("should rebuild cached frameworks (and dependencies) whose swift version does not match the local swift version") {
					let expected = ["TestFramework3_Mac", "TestFramework2_Mac", "TestFramework1_Mac"]

					let result1 = buildDependencyTest(platforms: [.macOS])
					expect(result1) == expected

                    do {
                        try overwriteSwiftVersion("TestFramework3",
                                              forPlatformName: "Mac",
                                              inDirectory: buildDirectoryURL,
                                              withVersion: "1.0 (swiftlang-000.0.1 clang-000.0.0.1)")
                    } catch {
                        fail("Could not overwrite swift version: \(error)")
                        return
                    }

					let allDSymsRemoved = expected
						.compactMap { removeDsym($0.dropLast(4).description, forPlatformName: "Mac", inDirectory: buildDirectoryURL) }
						.reduce(true) { acc, next in return  acc && next }
					expect(allDSymsRemoved) == true

					let result2 = buildDependencyTest(platforms: [.macOS])
					expect(result2) == expected
				}

				it("should not rebuild cached frameworks unnecessarily") {
					let expected = ["TestFramework3_Mac", "TestFramework2_Mac", "TestFramework1_Mac"]

					let result1 = buildDependencyTest(platforms: [.macOS])
					expect(result1) == expected

                    do {
                        try overwriteFramework("TestFramework2", forPlatformName: "Mac", inDirectory: buildDirectoryURL)
                    } catch {
                        fail("Could not overwrite framework: \(error)")
                        return
                    }

					let result2 = buildDependencyTest(platforms: [.macOS])
					expect(result2) == ["TestFramework2_Mac", "TestFramework1_Mac"]
				}

				it("should not rebuild cached frameworks (and dependencies) unnecessarily based on dSYMs") {
					let expected = ["TestFramework3_Mac", "TestFramework2_Mac", "TestFramework1_Mac"]

					let result1 = buildDependencyTest(platforms: [.macOS])
					expect(result1) == expected

					// Overwrite one header, this should trigger cheking the dSYM instead
                    do {
                        try overwriteSwiftVersion("TestFramework3",
                                                  forPlatformName: "Mac",
                                                  inDirectory: buildDirectoryURL,
                                                  withVersion: "1.0 (swiftlang-000.0.1 clang-000.0.0.1)")
                    } catch {
                        fail("Could not overwrite swift version: \(error)")
                        return
                    }

					let result2 = buildDependencyTest(platforms: [.macOS])
					expect(result2) == []
				}

				it("should rebuild a framework for all platforms even a cached framework is invalid for only a single platform") {
					let macOSexpected = ["TestFramework3_Mac", "TestFramework2_Mac", "TestFramework1_Mac"]
					let iOSExpected = ["TestFramework3_iOS", "TestFramework2_iOS", "TestFramework1_iOS"]

					let result1 = buildDependencyTest()
					expect(result1.filter { $0.contains("Mac") }) == macOSexpected
					expect(result1.filter { $0.contains("iOS") }) == iOSExpected
					expect(Set(result1)) == Set<String>(macOSexpected + iOSExpected)

                    do {
                        try overwriteFramework("TestFramework1", forPlatformName: "Mac", inDirectory: buildDirectoryURL)
                    } catch {
                        fail("Could not overwrite framework: \(error)")
                        return
                    }

					let result2 = buildDependencyTest()
					expect(result2.filter { $0.contains("Mac") }) == ["TestFramework1_Mac"]
					expect(result2.filter { $0.contains("iOS") }) == ["TestFramework1_iOS"]
				}

				it("should create and read a version file for a project with no shared schemes") {
					let result = buildNoSharedSchemesTest(platforms: [.iOS])
					expect(result) == ["TestFramework1_iOS"]

					let result2 = buildNoSharedSchemesTest(platforms: [.iOS])
					expect(result2) == []

					// TestFramework2 has no shared schemes, but invalidating its version file should result in its dependencies (TestFramework1) being rebuilt
					let framework2VersionFileURL = noSharedSchemesBuildDirectoryURL.appendingPathComponent(".TestFramework2.version", isDirectory: false)
					let framework2VersionFilePath = framework2VersionFileURL.path

                    guard let json = try? String(contentsOf: framework2VersionFileURL, encoding: .utf8) else {
                        fail("Could not load framework version file")
                        return
                    }
					let modifiedJson = json.replacingOccurrences(of: "\"commitish\" : \"v1.0\"", with: "\"commitish\" : \"v1.1\"")
                    do {
                        _ = try modifiedJson.write(toFile: framework2VersionFilePath, atomically: true, encoding: .utf8)
                    } catch {
                        fail("Could not write modified json file: \(error)")
                        return
                    }

					let result3 = buildNoSharedSchemesTest(platforms: [.iOS])
					expect(result3) == ["TestFramework1_iOS"]
				}
			}
		}

		describe("loadCombinedCartfile") {
			it("should load a combined Cartfile when only a Cartfile is present") {
                guard let directoryURL = Bundle(for: type(of: self)).url(forResource: "CartfileOnly", withExtension: nil) else {
                    fail("Could not lead CartfileOnly from resources")
                    return
                }
				let result = Project(directoryURL: directoryURL).loadCombinedCartfile().single()
				expect(result).notTo(beNil())
				expect(result?.value).notTo(beNil())

				let dependencies = result?.value?.dependencies
				expect(dependencies?.count) == 1
				expect(dependencies?.keys.first?.name) == "Carthage"
			}

			it("should load a combined Cartfile when only a Cartfile.private is present") {
                guard let directoryURL = Bundle(for: type(of: self)).url(forResource: "CartfilePrivateOnly", withExtension: nil) else {
                    fail("Could not load CartfilePrivateOnly from resources")
                    return
                }
				let result = Project(directoryURL: directoryURL).loadCombinedCartfile().single()
				expect(result).notTo(beNil())
				expect(result?.value).notTo(beNil())

				let dependencies = result?.value?.dependencies
				expect(dependencies?.count) == 1
				expect(dependencies?.keys.first?.name) == "Carthage"
			}

			it("should detect duplicate dependencies across Cartfile and Cartfile.private") {
                guard let directoryURL = Bundle(for: type(of: self)).url(forResource: "DuplicateDependencies", withExtension: nil) else {
                    fail("Could not load DuplicateDependencies from resources")
                    return
                }
				let result = Project(directoryURL: directoryURL).loadCombinedCartfile().single()
				expect(result).notTo(beNil())

				let resultError = result?.error
				expect(resultError).notTo(beNil())

				let makeDependency: (String, String, [String]) -> DuplicateDependency = { repoOwner, repoName, locations in
					let dependency = Dependency.gitHub(.dotCom, Repository(owner: repoOwner, name: repoName))
					return DuplicateDependency(dependency: dependency, locations: locations)
				}

				let locations = ["\(Constants.Project.cartfilePath)", "\(Constants.Project.privateCartfilePath)"]

				let expectedError = CarthageError.duplicateDependencies([
					makeDependency("1", "1", locations),
					makeDependency("3", "3", locations),
					makeDependency("5", "5", locations),
				])

				expect(resultError) == expectedError
			}

			it("should error when neither a Cartfile nor a Cartfile.private exists") {
                guard let directoryURL = Bundle(for: type(of: self)).url(forResource: "NoCartfile", withExtension: nil) else {
                    fail("Could not load NoCartfile from resources")
                    return
                }
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
			let dependency = Dependency.git(GitURL(repositoryURL.absoluteString))

			func initRepository() {
				expect { try FileManager.default.createDirectory(atPath: repositoryURL.path, withIntermediateDirectories: true) }.notTo(throwError())
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
				return CarthageKit.cloneOrFetch(dependency: dependency, preferHTTPS: false, destinationURL: cacheDirectoryURL, commitish: commitish)
			}

			func assertProjectEvent(commitish: String? = nil, clearFetchTime: Bool = true, action: @escaping (ProjectEvent?) -> Void) {
				waitUntil { done in
					if clearFetchTime {
						FetchCache.clearFetchTimes()
					}
					cloneOrFetch(commitish: commitish).start(Signal.Observer(
						value: { event, _ in action(event) },
						completed: done
					))
				}
			}

			beforeEach {
				expect { try FileManager.default.createDirectory(atPath: temporaryURL.path, withIntermediateDirectories: true) }.notTo(throwError())
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

			it("should not fetch twice in a row, even if no commitish is given") {
				// Clone first
				expect(cloneOrFetch().wait().error).to(beNil())

				assertProjectEvent { expect($0?.isFetching) == true }
				assertProjectEvent(clearFetchTime: false) { expect($0).to(beNil()) }
			}
		}

		describe("downloadBinaryFrameworkDefinition") {
			var project: Project!
            var testDefinitionURL: URL!
            beforeEach {
                guard let nonNilURL = Bundle(for: type(of: self)).url(forResource: "BinaryOnly/successful", withExtension: "json") else {
                    fail("Could not load BinaryOnly/successful.json from resources")
                    return
                }
                testDefinitionURL = nonNilURL
				project = Project(directoryURL: URL(string: "file:///var/empty/fake")!)
			}

			it("should return definition") {
				let binary = BinaryURL(url: testDefinitionURL, resolvedDescription: testDefinitionURL.description)
				let actualDefinition = project.downloadBinaryFrameworkDefinition(binary: binary).first()?.value

				let expectedBinaryProject = BinaryProject(versions: [
					PinnedVersion("1.0"): URL(string: "https://my.domain.com/release/1.0.0/framework.zip")!,
					PinnedVersion("1.0.1"): URL(string: "https://my.domain.com/release/1.0.1/framework.zip")!,
				])
				expect(actualDefinition) == expectedBinaryProject
			}

			it("should return read failed if unable to download") {
				let url = URL(string: "file:///thisfiledoesnotexist.json")!
				let binary = BinaryURL(url: url, resolvedDescription: testDefinitionURL.description)
				let actualError = project.downloadBinaryFrameworkDefinition(binary: binary).first()?.error

				switch actualError {
				case .some(.readFailed):
					break

				default:
					fail("expected read failed error")
				}
			}

			it("should return an invalid binary JSON error if unable to parse file") {
                guard let invalidDependencyURL = Bundle(for: type(of: self)).url(forResource: "BinaryOnly/invalid", withExtension: "json") else {
                    fail("Could not load BinaryOnly/invalid.json from resources")
                    return
                }
				let binary = BinaryURL(url: invalidDependencyURL, resolvedDescription: invalidDependencyURL.description)

				let actualError = project.downloadBinaryFrameworkDefinition(binary: binary).first()?.error

				switch actualError {
				case .some(CarthageError.invalidBinaryJSON(invalidDependencyURL, BinaryJSONError.invalidJSON)):
					break

				default:
					fail("expected invalid binary JSON error")
				}
			}

			it("should broadcast downloading framework definition event") {
				var events = [ProjectEvent]()
				project.projectEvents.observeValues { events.append($0) }

				let binary = BinaryURL(url: testDefinitionURL, resolvedDescription: testDefinitionURL.description)
				_ = project.downloadBinaryFrameworkDefinition(binary: binary).first()

				expect(events) == [.downloadingBinaryFrameworkDefinition(.binary(binary), testDefinitionURL)]
			}
		}

		describe("outdated dependencies") {
			it("should return return available updates for outdated dependencies") {
				var db: DB = [
					github1: [
						.v1_0_0: [:]
					],
					github2: [
						.v1_0_0: [:],
						.v1_1_0: [:],
						.v2_0_0: [:]
					],
					github3: [
						.v1_0_0: [:],
						.v1_1_0: [:],
						.v1_2_0: [:],
						.v2_0_0: [:],
						.v2_0_1: [:]
					],
					github4: [
						.v1_0_0: [:],
						.v1_2_0: [:],
						.v3_0_0_beta_1: [:],
						.v3_0_0: [:]
					],
					github5: [
						.v1_0_0: [:]
					],
					github6: [
						.v1_0_0: [:]
					]
				]
				let currentSHA = "2ea246ae4573538886ffb946d70d141583443734"
				let nextSHA = "809b8eb20f4b6b9e805b62de3084fbc7fcde54cc"
				db.references = [
					github3: [
						"2.0": PinnedVersion("v2.0.1")
					],
					github4: [
						"2.0": PinnedVersion("v2.0.1")
					],
					github5: [
						"development": PinnedVersion(currentSHA)
					],
					github6: [
						"development": PinnedVersion(nextSHA)
					]
				]
                guard let directoryURL = Bundle(for: type(of: self)).url(forResource: "OutdatedDependencies", withExtension: nil) else {
                    fail("Could not load OutdatedDependencies from resources")
                    return
                }
				let project = Project(directoryURL: directoryURL)

                guard let result = project.outdatedDependencies(false, useNewResolver: false, resolver: db.resolver()).single() else {
                    fail("Expected result to not be nil")
                    return
                }
                expect(result.error).to(beNil())
				expect(result.value).notTo(beNil())

				guard let outdatedDependencies = result.value?.reduce(into: [:], { (result, next) in
					result[next.0] = (next.1, next.2, next.3)
                }) else {
                    fail("Expected value to not be nil")
                    return
                }

				// Github 1 has no updates available
				expect(outdatedDependencies[github1]).to(beNil())

				// Github 2 is currently at 1.0.0, can be updated to the latest version which is 2.0.0
				// Github 2 has no constraint in the Cartfile
				expect(outdatedDependencies[github2]?.0) == PinnedVersion("v1.0.0")
				expect(outdatedDependencies[github2]?.1) == PinnedVersion("v2.0.0")
				expect(outdatedDependencies[github2]?.2) == PinnedVersion("v2.0.0")

				// Github 3 is currently at 2.0.0, latest is 2.0.1, to which it can be updated
				// Github 3 has a constraint in the Cartfile
				expect(outdatedDependencies[github3]?.0) == PinnedVersion("v2.0.0")
				expect(outdatedDependencies[github3]?.1) == PinnedVersion("v2.0.1")
				expect(outdatedDependencies[github3]?.2) == PinnedVersion("v2.0.1")

				// Github 4 is currently at 2.0.0, latest is 3.0.0, but it can only be updated to 2.0.1
				expect(outdatedDependencies[github4]?.0) == PinnedVersion("v2.0.0")
				expect(outdatedDependencies[github4]?.1) == PinnedVersion("v2.0.1")
				expect(outdatedDependencies[github4]?.2) == PinnedVersion("v3.0.0")

				// Github 5 is pinned to a branch and is already at the most recent commit, so it should not be displayed
				expect(outdatedDependencies[github5]).to(beNil())

				// Github 6 is pinned ot a branch which has new commits, so it should be displayed
				expect(outdatedDependencies[github6]?.0) == PinnedVersion(currentSHA)
				expect(outdatedDependencies[github6]?.1) == PinnedVersion(nextSHA)
				expect(outdatedDependencies[github6]?.2) == PinnedVersion("v1.0.0")
			}
		}

		describe("platformForFramework") {
            guard let testStaticFrameworkURL = Bundle(for: type(of: self)).url(forResource: "Alamofire.framework", withExtension: nil) else {
                fail("Could not load Alomfire.framework from resources")
                return
            }
			// Checks the framework's executable binary, not the Info.plist.
			// The Info.plist is missing from Alamofire's bundle on purpose.
			it("should check the framework's executable binary and produce a platform") {
				let actualPlatform = platformForFramework(testStaticFrameworkURL).first()?.value
				expect(actualPlatform) == .iOS
			}
		}

		describe("transitiveDependencies") {
			it("should find the correct dependencies") {
				let cartfile = """
				github "Alamofire/Alamofire" "4.6.0"
				github "CocoaLumberjack/CocoaLumberjack" "3.4.1"
				github "Moya/Moya" "10.0.2"
				github "ReactiveCocoa/ReactiveSwift" "2.0.1"
				github "ReactiveX/RxSwift" "4.1.2"
				github "antitypical/Result" "3.2.4"
				github "yapstudios/YapDatabase" "3.0.2"
				"""

				let resolvedCartfile = ResolvedCartfile.from(string: cartfile)
				let project = Project(directoryURL: URL(string: "file:///var/empty/fake")!)

                guard let resolvedCartfileValue = resolvedCartfile.value else {
                    fail("Expected ResolvedCartfile value to not be nil")
                    return
                }

				let result = project.transitiveDependencies(["Moya"], resolvedCartfile: resolvedCartfileValue).single()

				expect(result?.value).to(contain("Alamofire"))
				expect(result?.value).to(contain("ReactiveSwift"))
				expect(result?.value).to(contain("Result"))
				expect(result?.value).to(contain("RxSwift"))
				expect(result?.value?.count) == 4
			}
		}

		describe("frameworksInDirectory") {
			it("should find all carthage compatible framework bundles and exclude improper ones") {
                guard let directoryURL = Bundle(for: type(of: self)).url(forResource: "FilterBogusFrameworks", withExtension: nil) else {
                    fail("Could not load FilterBogusFrameworks from resources")
                    return
                }

				let result = CarthageKit.frameworksInDirectory(directoryURL).collect().single()
				expect(result?.value?.count) == 3
			}
		}
	}
}

extension ProjectEvent {
	fileprivate var isCloning: Bool {
		if case .cloning = self {
			return true
		}
		return false
	}

	fileprivate var isFetching: Bool {
		if case .fetching = self {
			return true
		}
		return false
	}
}

private func ==<A: Equatable, B: Equatable>(lhs: [(A, B)], rhs: [(A, B)]) -> Bool {
	guard lhs.count == rhs.count else { return false }
	for (lhs, rhs) in zip(lhs, rhs) {
		guard lhs == rhs else { return false }
	}
	return true
}
