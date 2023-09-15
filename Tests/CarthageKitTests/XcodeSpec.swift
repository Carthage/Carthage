@testable import CarthageKit
import Foundation
import Result
import Nimble
import Quick
import ReactiveSwift
import ReactiveTask
import Tentacle
import XCDBLD

class XcodeSpec: QuickSpec {
	override func spec() {
		// The fixture is maintained at https://github.com/ikesyo/carthage-fixtures-ReactiveCocoaLayout
		let directoryURL = Bundle(for: type(of: self)).url(forResource: "carthage-fixtures-ReactiveCocoaLayout-master", withExtension: nil)!
		let projectURL = directoryURL.appendingPathComponent("ReactiveCocoaLayout.xcodeproj")
		let buildFolderURL = directoryURL.appendingPathComponent(Constants.binariesFolderPath)
		let targetFolderURL = URL(
			fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString),
			isDirectory: true
		)

		beforeEach {
			_ = try? FileManager.default.removeItem(at: buildFolderURL)
			expect { try FileManager.default.createDirectory(atPath: targetFolderURL.path, withIntermediateDirectories: true) }.notTo(throwError())
		}

		afterEach {
			_ = try? FileManager.default.removeItem(at: targetFolderURL)
		}

		describe("determineSwiftInformation:") {
			let currentSwiftVersion = swiftVersion().single()?.value
			#if !SWIFT_PACKAGE
			let testSwiftFramework = "Quick.framework"
			let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
			let testSwiftFrameworkURL = currentDirectory.appendingPathComponent(testSwiftFramework)
			#endif

			#if !SWIFT_PACKAGE
			it("should determine that a Swift framework is a Swift framework") {
				expect(isSwiftFramework(testSwiftFrameworkURL)) == true
			}
			#endif

			it("should determine that an ObjC framework is not a Swift framework") {
				let frameworkURL = Bundle(for: type(of: self)).url(forResource: "FakeOldObjc.framework", withExtension: nil)!
				expect(isSwiftFramework(frameworkURL)) == false
			}

			it("should determine a value for the local swift version") {
				expect(currentSwiftVersion?.isEmpty) == false
			}

			#if !SWIFT_PACKAGE
			it("should determine a framework's Swift version") {
				let result = frameworkSwiftVersion(testSwiftFrameworkURL).single()

				expect(FileManager.default.fileExists(atPath: testSwiftFrameworkURL.path)) == true
				expect(result?.value) == currentSwiftVersion
			}

			it("should determine a dSYM's Swift version") {

				let dSYMURL = testSwiftFrameworkURL.appendingPathExtension("dSYM")
				expect(FileManager.default.fileExists(atPath: dSYMURL.path)) == true

				let result = dSYMSwiftVersion(dSYMURL).single()
				expect(result?.value) == currentSwiftVersion
			}
			#endif

			it("should determine a framework's Swift version excluding an effective version") {
				let frameworkURL = Bundle(for: type(of: self)).url(forResource: "FakeSwift.framework", withExtension: nil)!
				let result = frameworkSwiftVersion(frameworkURL).single()

				expect(result?.value) == "4.0 (swiftlang-900.0.43 clang-900.0.22.8)"
			}

			#if !SWIFT_PACKAGE
			it("should determine when a Swift framework is compatible") {
				let result = checkSwiftFrameworkCompatibility(testSwiftFrameworkURL, usingToolchain: nil).single()

				expect(result?.value) == testSwiftFrameworkURL
			}
			#endif

			it("should determine when a Swift framework is incompatible") {
				let frameworkURL = Bundle(for: type(of: self)).url(forResource: "FakeOldSwift.framework", withExtension: nil)!
				let result = checkSwiftFrameworkCompatibility(frameworkURL, usingToolchain: nil).single()

				expect(result?.value).to(beNil())
				expect(result?.error) == .incompatibleFrameworkSwiftVersions(local: currentSwiftVersion ?? "", framework: "0.0.0 (swiftlang-800.0.63 clang-800.0.42.1)")
			}

			it("should determine a framework's Swift version for OSS toolchains from Swift.org") {
				let frameworkURL = Bundle(for: type(of: self)).url(forResource: "FakeOSSSwift.framework", withExtension: nil)!
				let result = frameworkSwiftVersion(frameworkURL).single()

				expect(result?.value) == "4.1-dev (LLVM 0fcc19c0d8, Clang 1696f82ad2, Swift 691139445e)"
			}

			it("should determine when a module-stable Swift framework is incompatible") {
				let localSwiftVersion = "5.0 (swiftlang-1001.0.69.5 clang-1001.0.46.3)"
				let frameworkVersion = "5.1.2 (swiftlang-1100.0.278 clang-1100.0.33.9)"
				let frameworkURL = Bundle(for: type(of: self)).url(forResource: "ModuleStableBuiltWithSwift5.1.2.framework", withExtension: nil)!
				let result = isModuleStableAPI(localSwiftVersion, frameworkVersion, frameworkURL)

				expect(result).to(beFalse())
			}

			it("should determine when a non-module-stable Swift framework is incompatible") {
				let localSwiftVersion = "5.1 (swiftlang-1100.0.270.13 clang-1100.0.33.7)"
				let frameworkVersion = "5.1.2 (swiftlang-1100.0.278 clang-1100.0.33.9)"
				let frameworkURL = Bundle(for: type(of: self)).url(forResource: "NonModuleStableBuiltWithSwift5.1.2.framework", withExtension: nil)!
				let result = isModuleStableAPI(localSwiftVersion, frameworkVersion, frameworkURL)

				expect(result).to(beFalse())
			}

			it("should determine when a module-stable Swift framework is compatible") {
				let localSwiftVersion = "5.1 (swiftlang-1100.0.270.13 clang-1100.0.33.7)"
				let frameworkVersion = "5.1.2 (swiftlang-1100.0.278 clang-1100.0.33.9)"
				let frameworkURL = Bundle(for: type(of: self)).url(forResource: "ModuleStableBuiltWithSwift5.1.2.framework", withExtension: nil)!
				let result = isModuleStableAPI(localSwiftVersion, frameworkVersion, frameworkURL)

				expect(result).to(beTrue())
			}
		}

		describe("locateProjectsInDirectory:") {
			func relativePathsForProjectsInDirectory(_ directoryURL: URL) -> [String] {
				let result = ProjectLocator
					.locate(in: directoryURL)
					.map { String($0.fileURL.absoluteString[directoryURL.absoluteString.endIndex...]) }
					.collect()
					.first()
				expect(result?.error).to(beNil())
				return result?.value ?? []
			}

			it("should not find anything in the Carthage Subdirectory") {
				let relativePaths = relativePathsForProjectsInDirectory(directoryURL)
				expect(relativePaths).toNot(beEmpty())
				let pathsStartingWithCarthage = relativePaths.filter { $0.hasPrefix("\(Constants.checkoutsFolderPath)/") }
				expect(pathsStartingWithCarthage).to(beEmpty())
			}

			it("should not find anything that's listed as a git submodule") {
				let multipleSubprojects = "SampleGitSubmodule"
				let _directoryURL = Bundle(for: type(of: self)).url(forResource: multipleSubprojects, withExtension: nil)!

				let relativePaths = relativePathsForProjectsInDirectory(_directoryURL)
				expect(relativePaths) == [ "SampleGitSubmodule.xcodeproj/" ]
			}
		}

		it("should build for all platforms") {
			let dependencies = [
				Dependency.gitHub(.dotCom, Repository(owner: "github", name: "Archimedes")),
				Dependency.gitHub(.dotCom, Repository(owner: "ReactiveCocoa", name: "ReactiveCocoa")),
			]
			let version = PinnedVersion("0.1")

			for dependency in dependencies {
				let result = build(dependency: dependency, version: version, directoryURL, withOptions: BuildOptions(configuration: "Debug"))
					.ignoreTaskData()
					.on(value: { project, scheme in // swiftlint:disable:this end_closure
						NSLog("Building scheme \"\(scheme)\" in \(project)")
					})
					.wait()

				expect(result.error).to(beNil())
			}

			let result = buildInDirectory(directoryURL, withOptions: BuildOptions(configuration: "Debug"), rootDirectoryURL: directoryURL)
				.ignoreTaskData()
				.on(value: { project, scheme in // swiftlint:disable:this closure_params_parantheses
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error).to(beNil())

			// Verify that the build products exist at the top level.
			var dependencyNames = dependencies.map { dependency in dependency.name }
			dependencyNames.append("ReactiveCocoaLayout")

			for dependency in dependencyNames {
				let macPath = buildFolderURL.appendingPathComponent("Mac/\(dependency).framework").path
				let macdSYMPath = (macPath as NSString).appendingPathExtension("dSYM")!
				let iOSPath = buildFolderURL.appendingPathComponent("iOS/\(dependency).framework").path
				let iOSdSYMPath = (iOSPath as NSString).appendingPathExtension("dSYM")!

				for path in [ macPath, macdSYMPath, iOSPath, iOSdSYMPath ] {
					expect(path).to(beExistingDirectory())
				}
			}
			let frameworkFolderURL = buildFolderURL.appendingPathComponent("iOS/ReactiveCocoaLayout.framework")

			// Verify that the iOS framework is a universal binary for device
			// and simulator.
			let architectures = architecturesInPackage(frameworkFolderURL)
				.single()

			expect(architectures?.value).to(contain("i386", "armv7", "arm64"))

			// Verify that our dummy framework in the RCL iOS scheme built as
			// well.
			let auxiliaryFrameworkPath = buildFolderURL.appendingPathComponent("iOS/AuxiliaryFramework.framework").path
			expect(auxiliaryFrameworkPath).to(beExistingDirectory())

			// Copy ReactiveCocoaLayout.framework to the temporary folder.
			let targetURL = targetFolderURL.appendingPathComponent("ReactiveCocoaLayout.framework", isDirectory: true)

			let resultURL = copyProduct(frameworkFolderURL, targetURL).single()
			expect(resultURL?.value) == targetURL
			expect(targetURL.path).to(beExistingDirectory())

			let strippingResult = stripFramework(targetURL, keepingArchitectures: [ "armv7", "arm64" ], strippingDebugSymbols: true, codesigningIdentity: "-").wait()
			expect(strippingResult.value).notTo(beNil())

			let strippedArchitectures = architecturesInPackage(targetURL)
				.single()

			expect(strippedArchitectures?.value).notTo(contain("i386"))
			expect(strippedArchitectures?.value).to(contain("armv7", "arm64"))

			/// Check whether the resulting framework contains debug symbols
			/// There are many suggestions on how to do this but no one single
			/// accepted way. This seems to work best:
			/// https://lists.apple.com/archives/unix-porting/2006/Feb/msg00021.html
			let hasDebugSymbols = SignalProducer<URL, CarthageError> { () -> Result<URL, CarthageError> in binaryURL(targetURL) }
				.flatMap(.merge) { binaryURL -> SignalProducer<Bool, CarthageError> in
					let nmTask = Task("/usr/bin/xcrun", arguments: [ "nm", "-ap", binaryURL.path])
					return nmTask.launch()
						.ignoreTaskData()
						.mapError(CarthageError.taskError)
						.map { String(data: $0, encoding: .utf8) ?? "" }
						.flatMap(.merge) { output -> SignalProducer<Bool, NoError> in
							return SignalProducer(value: output.contains("SO "))
					}
			}.single()

			expect(hasDebugSymbols?.value).to(equal(false))

			let modulesDirectoryURL = targetURL.appendingPathComponent("Modules", isDirectory: true)
			expect(FileManager.default.fileExists(atPath: modulesDirectoryURL.path)) == false

			var output: String = ""
			let codeSign = Task("/usr/bin/xcrun", arguments: [ "codesign", "--verify", "--verbose", targetURL.path ])

			let codesignResult = codeSign.launch()
				.on(value: { taskEvent in
					switch taskEvent {
					case let .standardError(data):
						output += String(data: data, encoding: .utf8)!

					default:
						break
					}
				})
				.wait()

			expect(codesignResult.value).notTo(beNil())
			expect(output).to(contain("satisfies its Designated Requirement"))
		}

		it("should build all subprojects for all platforms by default") {
			let multipleSubprojects = "SampleMultipleSubprojects"
			let _directoryURL = Bundle(for: type(of: self)).url(forResource: multipleSubprojects, withExtension: nil)!

			let result = buildInDirectory(_directoryURL, withOptions: BuildOptions(configuration: "Debug"), rootDirectoryURL: directoryURL)
				.ignoreTaskData()
				.on(value: { project, scheme in // swiftlint:disable:this end_closure
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error).to(beNil())

			let expectedPlatformsFrameworks = [
				("iOS", "SampleiOSFramework"),
				("Mac", "SampleMacFramework"),
				("tvOS", "SampleTVFramework"),
				("watchOS", "SampleWatchFramework"),
			]

			for (platform, framework) in expectedPlatformsFrameworks {
				let path = buildFolderURL.appendingPathComponent("\(platform)/\(framework).framework").path
				expect(path).to(beExistingDirectory())
			}
		}

		it("should skip projects without shared framework schems") {
			let dependency = "SchemeDiscoverySampleForCarthage"
			let _directoryURL = Bundle(for: type(of: self)).url(forResource: "\(dependency)-0.2", withExtension: nil)!

			let result = buildInDirectory(_directoryURL, withOptions: BuildOptions(configuration: "Debug"), rootDirectoryURL: directoryURL)
				.ignoreTaskData()
				.on(value: { project, scheme in // swiftlint:disable:this end_closure
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error).to(beNil())

			let macPath = buildFolderURL.appendingPathComponent("Mac/\(dependency).framework").path
			let iOSPath = buildFolderURL.appendingPathComponent("iOS/\(dependency).framework").path

			for path in [ macPath, iOSPath ] {
				expect(path).to(beExistingDirectory())
			}
		}

		it("should not copy build products from nested dependencies produced by workspace") {
			let _directoryURL = Bundle(for: type(of: self)).url(forResource: "WorkspaceWithDependency", withExtension: nil)!

			let result = buildInDirectory(_directoryURL, withOptions: BuildOptions(configuration: "Debug", platforms: [.macOS]), rootDirectoryURL: directoryURL)
				.ignoreTaskData()
				.on(value: { project, scheme in // swiftlint:disable:this end_closure
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()
			expect(result.error).to(beNil())

			let framework1Path = buildFolderURL.appendingPathComponent("Mac/TestFramework1.framework").path
			let framework2Path = buildFolderURL.appendingPathComponent("Mac/TestFramework2.framework").path

			expect(framework1Path).to(beExistingDirectory())
			expect(framework2Path).notTo(beExistingDirectory())
		}

		it("should error out with .noSharedFrameworkSchemes if there is no shared framework schemes") {
			let _directoryURL = Bundle(for: type(of: self)).url(forResource: "Swell-0.5.0", withExtension: nil)!

			let result = buildInDirectory(_directoryURL, withOptions: BuildOptions(configuration: "Debug", platforms: [.macOS]), rootDirectoryURL: directoryURL)
				.ignoreTaskData()
				.on(value: { project, scheme in // swiftlint:disable:this end_closure
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error).notTo(beNil())

			let isExpectedError: Bool
			if case .noSharedFrameworkSchemes? = result.error {
				isExpectedError = true
			} else {
				isExpectedError = false
			}

			expect(isExpectedError) == true
			expect(result.error?.description) == "Dependency \"Swell-0.5.0\" has no shared framework schemes for any of the platforms: Mac"
		}

		it("should build for one platform") {
			let dependency = Dependency.gitHub(.dotCom, Repository(owner: "github", name: "Archimedes"))
			let version = PinnedVersion("0.1")
			let result = build(dependency: dependency, version: version, directoryURL, withOptions: BuildOptions(configuration: "Debug", platforms: [ .macOS ]))
				.ignoreTaskData()
				.on(value: { project, scheme in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error).to(beNil())

			// Verify that the build product exists at the top level.
			let path = buildFolderURL.appendingPathComponent("Mac/\(dependency.name).framework").path
			expect(path).to(beExistingDirectory())

			// Verify that the version file exists.
			let versionFileURL = URL(fileURLWithPath: buildFolderURL.appendingPathComponent(".Archimedes.version").path)
			let versionFile = VersionFile(url: versionFileURL)
			expect(versionFile).notTo(beNil())
			
			// Verify that the other platform wasn't built.
			let incorrectPath = buildFolderURL.appendingPathComponent("iOS/\(dependency.name).framework").path
			expect(FileManager.default.fileExists(atPath: incorrectPath, isDirectory: nil)) == false
		}

		it("should build for multiple platforms") {
			let dependency = Dependency.gitHub(.dotCom, Repository(owner: "github", name: "Archimedes"))
			let version = PinnedVersion("0.1")
			let result = build(dependency: dependency, version: version, directoryURL, withOptions: BuildOptions(configuration: "Debug", platforms: [ .macOS, .iOS ]))
				.ignoreTaskData()
				.on(value: { project, scheme in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error).to(beNil())

			// Verify that the build products of all specified platforms exist
			// at the top level.
			let macPath = buildFolderURL.appendingPathComponent("Mac/\(dependency.name).framework").path
			let iosPath = buildFolderURL.appendingPathComponent("iOS/\(dependency.name).framework").path

			for path in [ macPath, iosPath ] {
				expect(path).to(beExistingDirectory())
			}
		}

		it("should locate the project") {
			let result = ProjectLocator.locate(in: directoryURL).first()
			expect(result).notTo(beNil())
			expect(result?.error).to(beNil())
			expect(result?.value) == .projectFile(projectURL)
		}

		it("should locate the project from the parent directory") {
			let result = ProjectLocator.locate(in: directoryURL.deletingLastPathComponent()).collect().first()
			expect(result).notTo(beNil())
			expect(result?.error).to(beNil())
			expect(result?.value).to(contain(.projectFile(projectURL)))
		}

		it("should not locate the project from a directory not containing it") {
			let result = ProjectLocator.locate(in: directoryURL.appendingPathComponent("ReactiveCocoaLayout")).first()
			expect(result).to(beNil())
		}

		it("should build static library and place result to subdirectory") {
			let _directoryURL = Bundle(for: type(of: self)).url(forResource: "DynamicAndStatic", withExtension: nil)!
			let _buildFolderURL = _directoryURL.appendingPathComponent(Constants.binariesFolderPath)

			_ = try? FileManager.default.removeItem(at: _buildFolderURL)

			let result = buildInDirectory(_directoryURL, withOptions: BuildOptions(configuration: "Debug",
																				   platforms: [.iOS],
																				   derivedDataPath: Constants.Dependency.derivedDataURL.appendingPathComponent("TestFramework-o2nfjkdsajhwenrjle").path), rootDirectoryURL: directoryURL)
				.ignoreTaskData()
				.on(value: { project, scheme in // swiftlint:disable:this end_closure
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()
			expect(result.error).to(beNil())

			let frameworkDynamicURL = buildFolderURL.appendingPathComponent("iOS/TestFramework.framework")
			let frameworkStaticURL = buildFolderURL.appendingPathComponent("iOS/Static/TestFramework.framework")

			let frameworkDynamicPackagePath = frameworkDynamicURL.appendingPathComponent("TestFramework").path
			let frameworkStaticPackagePath = frameworkStaticURL.appendingPathComponent("TestFramework").path

			expect(frameworkDynamicURL.path).to(beExistingDirectory())
			expect(frameworkStaticURL.path).to(beExistingDirectory())
			expect(frameworkDynamicPackagePath).to(beFramework(ofType: .dynamic))
			expect(frameworkStaticPackagePath).to(beFramework(ofType: .static))

			let result2 = buildInDirectory(_directoryURL, withOptions: BuildOptions(configuration: "Debug",
																					platforms: [.iOS],
																					derivedDataPath: Constants.Dependency.derivedDataURL.appendingPathComponent("TestFramework-o2nfjkdsajhwenrjle").path), rootDirectoryURL: directoryURL)
				.ignoreTaskData()
				.on(value: { project, scheme in // swiftlint:disable:this end_closure
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()
			expect(result2.error).to(beNil())
			expect(frameworkDynamicPackagePath).to(stillBeFramework(ofType: .dynamic))
			expect(frameworkStaticPackagePath).to(stillBeFramework(ofType: .static))
		}
	}
}

// MARK: Matcher

internal func stillBeFramework(ofType: FrameworkType) -> Nimble.Predicate<String> {
	return beFramework(ofType: ofType)
}

internal func beFramework(ofType: FrameworkType) -> Nimble.Predicate<String> {
	return Predicate { actualExpression in
		var message = "exist and be a \(ofType == .static ? "static" : "dynamic") type"
		let actualPath = try actualExpression.evaluate()

		guard let path = actualPath else {
			return PredicateResult(status: .fail, message: .expectedActualValueTo(message))
		}

		var stringOutput: String!

		let result = Task("/usr/bin/xcrun", arguments: ["file", path])
			.launch()
			.ignoreTaskData()
			.on(value: { data in
				stringOutput = String(data: data, encoding: .utf8)
			})
			.wait()

		expect(result.error).to(beNil())

		let resultBool: Bool
		if ofType == .static {
			resultBool = stringOutput.contains("current ar archive") && !stringOutput.contains("dynamically linked shared library")
		} else {
			resultBool = !stringOutput.contains("current ar archive") && stringOutput.contains("dynamically linked shared library")
		}

		if !resultBool {
			message += ", got \(stringOutput!)"
		}

		return PredicateResult(
			bool: resultBool,
			message: .expectedActualValueTo(message)
		)
	}
}

internal func beExistingDirectory() -> Nimble.Predicate<String> {
	return Predicate { actualExpression in
		var message = "exist and be a directory"
		let actualPath = try actualExpression.evaluate()

		guard let path = actualPath else {
			return PredicateResult(status: .fail, message: .expectedActualValueTo(message))
		}

		var isDirectory: ObjCBool = false
		let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)

		if !exists {
			message += ", but does not exist"
		} else if !isDirectory.boolValue {
			message += ", but is not a directory"
		}

		return PredicateResult(
			bool: exists && isDirectory.boolValue,
			message: .expectedActualValueTo(message)
		)
	}
}

internal func beRelativeSymlinkToDirectory(_ directory: URL) -> Nimble.Predicate<URL> {
	return Predicate { actualExpression in
		let message = "be a relative symlink to \(directory)"
		let actualURL = try actualExpression.evaluate()

		guard var url = actualURL else {
			return PredicateResult(status: .fail, message: .expectedActualValueTo(message))
		}

		var isSymlink: Bool = false
		do {
			url.removeCachedResourceValue(forKey: .isSymbolicLinkKey)
			isSymlink = try url.resourceValues(forKeys: [ .isSymbolicLinkKey ]).isSymbolicLink ?? false
		} catch {}

		guard isSymlink else {
			return PredicateResult(
				status: .fail,
				message: .expectedActualValueTo(message + ", but is not a symlink")
			)
		}

		let destination = try! FileManager.default.destinationOfSymbolicLink(atPath: url.path) // swiftlint:disable:this force_try

		guard !(destination as NSString).isAbsolutePath else {
			return PredicateResult(
				status: .fail,
				message: .expectedActualValueTo(message + ", but is not a relative symlink")
			)
		}

		let standardDestination = url.resolvingSymlinksInPath().standardizedFileURL
		let desiredDestination = directory.standardizedFileURL

		let urlsEqual = standardDestination == desiredDestination
		let expectationMessage: ExpectationMessage = urlsEqual
			? .expectedActualValueTo(message)
			: .expectedActualValueTo(message + ", but does not point to the correct destination. Instead it points to \(standardDestination)")
		return PredicateResult(bool: urlsEqual, message: expectationMessage)
	}
}
