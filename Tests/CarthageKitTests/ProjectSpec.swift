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

class ProjectSpec: QuickSpec {
	override func spec() {
		describe("buildCheckedOutDependenciesWithOptions") {
			let directoryURL = Bundle(for: type(of: self)).url(forResource: "DependencyTest", withExtension: nil)!
			let buildDirectoryURL = directoryURL.appendingPathComponent(Constants.binariesFolderPath)

			func buildDependencyTest(platforms: Set<Platform> = [], cacheBuilds: Bool = true, dependenciesToBuild: [String]? = nil) -> [String] {
				let project = Project(directoryURL: directoryURL)
				let result = project.buildCheckedOutDependenciesWithOptions(BuildOptions(configuration: "Debug", platforms: platforms, cacheBuilds: cacheBuilds), dependenciesToBuild: dependenciesToBuild)
					.flatten(.concat)
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
				try! FileManager.default.moveItem(at: checkout, to: tmpCheckout)
				// Without the checkout, it should still figure out it needs to build 2 and 3.
				let result = buildDependencyTest(platforms: [.macOS], cacheBuilds: false)
				expect(result) == macOSexpected
				try! FileManager.default.moveItem(at: tmpCheckout, to: checkout)
			}

			describe("createAndCheckVersionFiles") {
				func overwriteFramework(_ frameworkName: String, forPlatformName platformName: String, inDirectory buildDirectoryURL: URL) {
					let platformURL = buildDirectoryURL.appendingPathComponent(platformName, isDirectory: true)
					let frameworkURL = platformURL.appendingPathComponent("\(frameworkName).framework", isDirectory: false)
					let binaryURL = frameworkURL.appendingPathComponent("\(frameworkName)", isDirectory: false)

					let data = "junkdata".data(using: .utf8)!
					try! data.write(to: binaryURL, options: .atomic)
				}

				func overwriteSwiftVersion(_ frameworkName: String, forPlatformName platformName: String, inDirectory buildDirectoryURL: URL, withVersion version: String) {
					let platformURL = buildDirectoryURL.appendingPathComponent(platformName, isDirectory: true)
					let frameworkURL = platformURL.appendingPathComponent("\(frameworkName).framework", isDirectory: false)
					let swiftHeaderURL = frameworkURL.swiftHeaderURL()!

					let swiftVersionResult = swiftVersion().first()!
					expect(swiftVersionResult.error).to(beNil())

					var header = try! String(contentsOf: swiftHeaderURL)

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

					try! header.write(to: swiftHeaderURL, atomically: true, encoding: header.fastestEncoding)
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

					overwriteFramework("TestFramework3", forPlatformName: "Mac", inDirectory: buildDirectoryURL)

					let result2 = buildDependencyTest(platforms: [.macOS])
					expect(result2) == expected
				}

				it("should rebuild cached frameworks (and dependencies) whose version does not match the version file") {
					let expected = ["TestFramework3_Mac", "TestFramework2_Mac", "TestFramework1_Mac"]

					let result1 = buildDependencyTest(platforms: [.macOS])
					expect(result1) == expected

					let preludeVersionFileURL = buildDirectoryURL.appendingPathComponent(".TestFramework3.version", isDirectory: false)
					let preludeVersionFilePath = preludeVersionFileURL.path

					let json = try! String(contentsOf: preludeVersionFileURL, encoding: .utf8)
					let modifiedJson = json.replacingOccurrences(of: "\"commitish\" : \"v1.0\"", with: "\"commitish\" : \"v1.1\"")
					_ = try! modifiedJson.write(toFile: preludeVersionFilePath, atomically: true, encoding: .utf8)

					let result2 = buildDependencyTest(platforms: [.macOS])
					expect(result2) == expected
				}

				it("should rebuild cached frameworks (and dependencies) whose swift version does not match the local swift version") {
					let expected = ["TestFramework3_Mac", "TestFramework2_Mac", "TestFramework1_Mac"]

					let result1 = buildDependencyTest(platforms: [.macOS])
					expect(result1) == expected

					overwriteSwiftVersion("TestFramework3", forPlatformName: "Mac", inDirectory: buildDirectoryURL, withVersion: "1.0 (swiftlang-000.0.1 clang-000.0.0.1)")

					let result2 = buildDependencyTest(platforms: [.macOS])
					expect(result2) == expected
				}

				it("should not rebuild cached frameworks unnecessarily") {
					let expected = ["TestFramework3_Mac", "TestFramework2_Mac", "TestFramework1_Mac"]

					let result1 = buildDependencyTest(platforms: [.macOS])
					expect(result1) == expected

					overwriteFramework("TestFramework2", forPlatformName: "Mac", inDirectory: buildDirectoryURL)

					let result2 = buildDependencyTest(platforms: [.macOS])
					expect(result2) == ["TestFramework2_Mac", "TestFramework1_Mac"]
				}

				it("should rebuild a framework for all platforms even a cached framework is invalid for only a single platform") {
					let macOSexpected = ["TestFramework3_Mac", "TestFramework2_Mac", "TestFramework1_Mac"]
					let iOSExpected = ["TestFramework3_iOS", "TestFramework2_iOS", "TestFramework1_iOS"]

					let result1 = buildDependencyTest()
					expect(result1.filter { $0.contains("Mac") }) == macOSexpected
					expect(result1.filter { $0.contains("iOS") }) == iOSExpected
					expect(Set(result1)) == Set<String>(macOSexpected + iOSExpected)

					overwriteFramework("TestFramework1", forPlatformName: "Mac", inDirectory: buildDirectoryURL)

					let result2 = buildDependencyTest()
					expect(result2.filter { $0.contains("Mac") }) == ["TestFramework1_Mac"]
					expect(result2.filter { $0.contains("iOS") }) == ["TestFramework1_iOS"]
				}
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
				expect(dependencies?.keys.first?.name) == "Carthage"
			}

			it("should load a combined Cartfile when only a Cartfile.private is present") {
				let directoryURL = Bundle(for: type(of: self)).url(forResource: "CartfilePrivateOnly", withExtension: nil)!
				let result = Project(directoryURL: directoryURL).loadCombinedCartfile().single()
				expect(result).notTo(beNil())
				expect(result?.value).notTo(beNil())

				let dependencies = result?.value?.dependencies
				expect(dependencies?.count) == 1
				expect(dependencies?.keys.first?.name) == "Carthage"
			}

			it("should detect duplicate dependencies across Cartfile and Cartfile.private") {
				let directoryURL = Bundle(for: type(of: self)).url(forResource: "DuplicateDependencies", withExtension: nil)!
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
			let testDefinitionURL = Bundle(for: type(of: self)).url(forResource: "BinaryOnly/successful", withExtension: "json")!

			beforeEach {
				project = Project(directoryURL: URL(string: "file://fake")!)
			}

			it("should return definition") {
				let actualDefinition = project.downloadBinaryFrameworkDefinition(url: testDefinitionURL).first()?.value

				let expectedBinaryProject = BinaryProject(versions: [
					PinnedVersion("1.0"): URL(string: "https://my.domain.com/release/1.0.0/framework.zip")!,
					PinnedVersion("1.0.1"): URL(string: "https://my.domain.com/release/1.0.1/framework.zip")!,
				])
				expect(actualDefinition) == expectedBinaryProject
			}

			it("should return read failed if unable to download") {
				let actualError = project.downloadBinaryFrameworkDefinition(url: URL(string: "file:///thisfiledoesnotexist.json")!).first()?.error

				switch actualError {
				case .some(.readFailed):
					break

				default:
					fail("expected read failed error")
				}
			}

			it("should return an invalid binary JSON error if unable to parse file") {
				let invalidDependencyURL = Bundle(for: type(of: self)).url(forResource: "BinaryOnly/invalid", withExtension: "json")!

				let actualError = project.downloadBinaryFrameworkDefinition(url: invalidDependencyURL).first()?.error

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

				_ = project.downloadBinaryFrameworkDefinition(url: testDefinitionURL).first()

				expect(events) == [.downloadingBinaryFrameworkDefinition(.binary(testDefinitionURL), testDefinitionURL)]
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
