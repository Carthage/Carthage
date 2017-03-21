//
//  XcodeSpec.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-11.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

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
	static let currentSwiftVersion = "3.0.2"

	override func spec() {
		// The fixture is maintained at https://github.com/ikesyo/carthage-fixtures-ReactiveCocoaLayout
		let directoryURL = Bundle(for: type(of: self)).url(forResource: "carthage-fixtures-ReactiveCocoaLayout-master", withExtension: nil)!
		let projectURL = directoryURL.appendingPathComponent("ReactiveCocoaLayout.xcodeproj")
		let buildFolderURL = directoryURL.appendingPathComponent(CarthageBinariesFolderPath)
		let targetFolderURL = URL(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString), isDirectory: true)

		beforeEach {
			_ = try? FileManager.default.removeItem(at: buildFolderURL)
			expect { try FileManager.default.createDirectory(atPath: targetFolderURL.path, withIntermediateDirectories: true) }.notTo(throwError())
		}
		
		afterEach {
			_ = try? FileManager.default.removeItem(at: targetFolderURL)
		}

		describe("determingSwiftInformation") {
			let testSwiftFramework = "Quick.framework"
			let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
			let testSwiftFrameworkURL = currentDirectory.appendingPathComponent(testSwiftFramework)

			it("should determine that a Swift framework is a Swift framework") {
				let result = isSwiftFramework(testSwiftFrameworkURL).single()

				expect(result?.value) == true
			}

			it("should determine that an ObjC framework is not a Swift framework") {
				let frameworkURL = Bundle(for: type(of: self)).url(forResource: "FakeOldObjc.framework", withExtension: nil)!
				let result = isSwiftFramework(frameworkURL).single()

				expect(result?.value) == false
			}

			it("determines the local Swift version") {
				let result = swiftVersion.single()
				expect(result?.value) == XcodeSpec.currentSwiftVersion
			}

			it("should determine a framework's Swift version") {
				let result = frameworkSwiftVersion(testSwiftFrameworkURL).single()

				expect(result?.value) == XcodeSpec.currentSwiftVersion
			}

			it("should determine when a Swift framework is compatible") {
				let result = checkSwiftFrameworkCompatibility(testSwiftFrameworkURL).single()

				expect(result?.value) == testSwiftFrameworkURL
			}

			it("should determine when a Swift framework is incompatible") {
				let frameworkURL = Bundle(for: type(of: self)).url(forResource: "FakeOldSwift.framework", withExtension: nil)!
				let result = checkSwiftFrameworkCompatibility(frameworkURL).single()

				expect(result?.value).to(beNil())
				expect(result?.error) == .incompatibleFrameworkSwiftVersions(local: XcodeSpec.currentSwiftVersion, framework: "0.0.0")
			}
		}

		describe("locateProjectsInDirectory:") {
			func relativePathsForProjectsInDirectory(_ directoryURL: URL) -> [String] {
				let result = ProjectLocator
					.locate(in: directoryURL)
					.map { $0.fileURL.absoluteString.substring(from: directoryURL.absoluteString.endIndex) }
					.collect()
					.first()
				expect(result?.error).to(beNil())
				return result?.value ?? []
			}

			it("should not find anything in the Carthage Subdirectory") {
				let relativePaths = relativePathsForProjectsInDirectory(directoryURL)
				expect(relativePaths).toNot(beEmpty())
				let pathsStartingWithCarthage = relativePaths.filter { $0.hasPrefix("\(CarthageProjectCheckoutsPath)/") }
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
				ProjectIdentifier.gitHub(Repository(owner: "github", name: "Archimedes")),
				ProjectIdentifier.gitHub(Repository(owner: "ReactiveCocoa", name: "ReactiveCocoa")),
			]
			let version = PinnedVersion("0.1")

			for project in dependencies {
				let dependency = Dependency<PinnedVersion>(project: project, version: version)
				let result = buildDependencyProject(dependency, directoryURL, withOptions: BuildOptions(configuration: "Debug"))
					.flatten(.concat)
					.ignoreTaskData()
					.on(value: { (project, scheme) in
						NSLog("Building scheme \"\(scheme)\" in \(project)")
					})
					.wait()

				expect(result.error).to(beNil())
			}

			let result = buildInDirectory(directoryURL, withOptions: BuildOptions(configuration: "Debug"))
				.ignoreTaskData()
				.on(value: { (project, scheme) in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error).to(beNil())

			// Verify that the build products exist at the top level.
			var projectNames = dependencies.map { project in project.name }
			projectNames.append("ReactiveCocoaLayout")

			for dependency in projectNames {
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
				.collect()
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

			let strippingResult = stripFramework(targetURL, keepingArchitectures: [ "armv7" , "arm64" ], codesigningIdentity: "-").wait()
			expect(strippingResult.value).notTo(beNil())
			
			let strippedArchitectures = architecturesInPackage(targetURL)
				.collect()
				.single()
			
			expect(strippedArchitectures?.value).notTo(contain("i386"))
			expect(strippedArchitectures?.value).to(contain("armv7", "arm64"))

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
			let _buildFolderURL = _directoryURL.appendingPathComponent(CarthageBinariesFolderPath)

			_ = try? FileManager.default.removeItem(at: _buildFolderURL)

			let result = buildInDirectory(_directoryURL, withOptions: BuildOptions(configuration: "Debug"))
				.ignoreTaskData()
				.on(value: { (project, scheme) in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error).to(beNil())

			let expectedPlatformsFrameworks = [
				("iOS", "SampleiOSFramework"),
				("Mac", "SampleMacFramework"),
				("tvOS", "SampleTVFramework"),
				("watchOS", "SampleWatchFramework")
			]

			for (platform, framework) in expectedPlatformsFrameworks {
				let path = _buildFolderURL.appendingPathComponent("\(platform)/\(framework).framework").path
				expect(path).to(beExistingDirectory())
			}
		}

		it("should skip projects without shared dynamic framework schems") {
			let dependency = "SchemeDiscoverySampleForCarthage"
			let _directoryURL = Bundle(for: type(of: self)).url(forResource: "\(dependency)-0.2", withExtension: nil)!
			let _buildFolderURL = _directoryURL.appendingPathComponent(CarthageBinariesFolderPath)

			_ = try? FileManager.default.removeItem(at: _buildFolderURL)

			let result = buildInDirectory(_directoryURL, withOptions: BuildOptions(configuration: "Debug"))
				.ignoreTaskData()
				.on(value: { (project, scheme) in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error).to(beNil())

			let macPath = _buildFolderURL.appendingPathComponent("Mac/\(dependency).framework").path
			let iOSPath = _buildFolderURL.appendingPathComponent("iOS/\(dependency).framework").path

			for path in [ macPath, iOSPath ] {
				expect(path).to(beExistingDirectory())
			}
		}

		it("should not copy build products from nested dependencies produced by workspace") {
			let _directoryURL = Bundle(for: type(of: self)).url(forResource: "WorkspaceWithDependency", withExtension: nil)!
			let _buildFolderURL = _directoryURL.appendingPathComponent(CarthageBinariesFolderPath)

			_ = try? FileManager.default.removeItem(at: _buildFolderURL)

			let result = buildInDirectory(_directoryURL, withOptions: BuildOptions(configuration: "Debug", platforms: [.macOS]))
				.ignoreTaskData()
				.on(value: { (project, scheme) in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()
			expect(result.error).to(beNil())

			let framework1Path = _buildFolderURL.appendingPathComponent("Mac/TestFramework1.framework").path
			let framework2Path = _buildFolderURL.appendingPathComponent("Mac/TestFramework2.framework").path

			expect(framework1Path).to(beExistingDirectory())
			expect(framework2Path).notTo(beExistingDirectory())
		}

		it("should error out with .noSharedFrameworkSchemes if there is no shared framework schemes") {
			let _directoryURL = Bundle(for: type(of: self)).url(forResource: "Swell-0.5.0", withExtension: nil)!
			let _buildFolderURL = _directoryURL.appendingPathComponent(CarthageBinariesFolderPath)

			_ = try? FileManager.default.removeItem(at: _buildFolderURL)

			let result = buildInDirectory(_directoryURL, withOptions: BuildOptions(configuration: "Debug"))
				.ignoreTaskData()
				.on(value: { (project, scheme) in
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
		}

		it("should build for one platform") {
			let project = ProjectIdentifier.gitHub(Repository(owner: "github", name: "Archimedes"))
			let version = PinnedVersion("0.1")
			let dependency = Dependency<PinnedVersion>(project: project, version: version)
			let result = buildDependencyProject(dependency, directoryURL, withOptions: BuildOptions(configuration: "Debug", platforms: [ .macOS ]))
				.flatten(.concat)
				.ignoreTaskData()
				.on(value: { (project, scheme) in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error).to(beNil())

			// Verify that the build product exists at the top level.
			let path = buildFolderURL.appendingPathComponent("Mac/\(project.name).framework").path
			expect(path).to(beExistingDirectory())

			// Verify that the other platform wasn't built.
			let incorrectPath = buildFolderURL.appendingPathComponent("iOS/\(project.name).framework").path
			expect(FileManager.default.fileExists(atPath: incorrectPath, isDirectory: nil)) == false
		}

		it("should build for multiple platforms") {
			let project = ProjectIdentifier.gitHub(Repository(owner: "github", name: "Archimedes"))
			let version = PinnedVersion("0.1")
			let dependency = Dependency<PinnedVersion>(project: project, version: version)
			let result = buildDependencyProject(dependency, directoryURL, withOptions: BuildOptions(configuration: "Debug", platforms: [ .macOS, .iOS ]))
				.flatten(.concat)
				.ignoreTaskData()
				.on(value: { (project, scheme) in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error).to(beNil())

			// Verify that the build products of all specified platforms exist 
			// at the top level.
			let macPath = buildFolderURL.appendingPathComponent("Mac/\(project.name).framework").path
			let iosPath = buildFolderURL.appendingPathComponent("iOS/\(project.name).framework").path

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

		it("should symlink the build directory") {
			let project = ProjectIdentifier.gitHub(Repository(owner: "github", name: "Archimedes"))
			let version = PinnedVersion("0.1")
			let dependency = Dependency<PinnedVersion>(project: project, version: version)

			let dependencyURL =	directoryURL.appendingPathComponent(dependency.project.relativePath)
			// Build
			let buildURL = directoryURL.appendingPathComponent(CarthageBinariesFolderPath)
			let dependencyBuildURL = dependencyURL.appendingPathComponent(CarthageBinariesFolderPath)

			let result = buildDependencyProject(dependency, directoryURL, withOptions: BuildOptions(configuration: "Debug"))
				.flatten(.concat)
				.ignoreTaskData()
				.on(value: { (project, scheme) in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error).to(beNil())

			expect(dependencyBuildURL).to(beRelativeSymlinkToDirectory(buildURL))
		}

	}
}

// MARK: Matcher

internal func beExistingDirectory() -> MatcherFunc<String> {
	return MatcherFunc { actualExpression, failureMessage in
		failureMessage.postfixMessage = "exist and be a directory"
		let actualPath = try actualExpression.evaluate()

		guard let path = actualPath else {
			return false
		}

		var isDirectory: ObjCBool = false
		let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)

		if !exists {
			failureMessage.postfixMessage += ", but does not exist"
		} else if !isDirectory.boolValue {
			failureMessage.postfixMessage += ", but is not a directory"
		}

		return exists && isDirectory.boolValue
	}
}

internal func beRelativeSymlinkToDirectory(_ directory: URL) -> MatcherFunc<URL> {
	return MatcherFunc { actualExpression, failureMessage in
		failureMessage.postfixMessage = "be a relative symlink to \(directory)"
		let actualURL = try actualExpression.evaluate()

		guard var url = actualURL else {
			return false
		}
		var isSymlink: Bool = false
		do {
			url.removeCachedResourceValue(forKey: .isSymbolicLinkKey)
			isSymlink = try url.resourceValues(forKeys: [ .isSymbolicLinkKey ]).isSymbolicLink ?? false
		} catch {}

		guard isSymlink else {
			failureMessage.postfixMessage += ", but is not a symlink"
			return false
		}

		let destination = try! FileManager.default.destinationOfSymbolicLink(atPath: url.path)

		guard !(destination as NSString).isAbsolutePath else {
			failureMessage.postfixMessage += ", but is not a relative symlink"
			return false
		}

		let standardDestination = url.resolvingSymlinksInPath().standardizedFileURL
		let desiredDestination = directory.standardizedFileURL

		let urlsEqual = standardDestination == desiredDestination

		if !urlsEqual {
			failureMessage.postfixMessage += ", but does not point to the correct destination. Instead it points to \(standardDestination)"
		}

		return urlsEqual
	}
}
