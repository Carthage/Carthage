//
//  XcodeSpec.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-11.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import Result
import Nimble
import Quick
import ReactiveCocoa
import ReactiveTask
import Tentacle

class XcodeSpec: QuickSpec {
	override func spec() {
		let directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("ReactiveCocoaLayout", withExtension: nil)!
		let projectURL = directoryURL.URLByAppendingPathComponent("ReactiveCocoaLayout.xcodeproj")
		let buildFolderURL = directoryURL.URLByAppendingPathComponent(CarthageBinariesFolderPath)
		let targetFolderURL = NSURL(fileURLWithPath: (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent(NSProcessInfo.processInfo().globallyUniqueString), isDirectory: true)

		beforeEach {
			_ = try? NSFileManager.defaultManager().removeItemAtURL(buildFolderURL)
			expect { try NSFileManager.defaultManager().createDirectoryAtPath(targetFolderURL.path!, withIntermediateDirectories: true, attributes: nil) }.notTo(throwError())
		}
		
		afterEach {
			_ = try? NSFileManager.defaultManager().removeItemAtURL(targetFolderURL)
		}
		
		describe("\(ProjectLocator.self)") {
			describe("sorting") {
				it("should put workspaces before projects") {
					let workspace = ProjectLocator.Workspace(NSURL(fileURLWithPath: "/Z.xcworkspace"))
					let project = ProjectLocator.ProjectFile(NSURL(fileURLWithPath: "/A.xcodeproj"))
					expect(workspace < project) == true
				}
				
				it("should fall back to lexicographical sorting") {
					let workspaceA = ProjectLocator.Workspace(NSURL(fileURLWithPath: "/A.xcworkspace"))
					let workspaceB = ProjectLocator.Workspace(NSURL(fileURLWithPath: "/B.xcworkspace"))
					expect(workspaceA < workspaceB) == true
					
					let projectA = ProjectLocator.ProjectFile(NSURL(fileURLWithPath: "/A.xcodeproj"))
					let projectB = ProjectLocator.ProjectFile(NSURL(fileURLWithPath: "/B.xcodeproj"))
					expect(projectA < projectB) == true
				}
				
				it("should put top-level directories first") {
					let top = ProjectLocator.ProjectFile(NSURL(fileURLWithPath: "/Z.xcodeproj"))
					let bottom = ProjectLocator.Workspace(NSURL(fileURLWithPath: "/A/A.xcodeproj"))
					expect(top < bottom) == true
				}
			}
		}

		describe("locateProjectsInDirectory:") {
			func relativePathsForProjectsInDirectory(directoryURL: NSURL) -> [String] {
				let result = locateProjectsInDirectory(directoryURL)
					.map { $0.fileURL.absoluteString.substringFromIndex(directoryURL.absoluteString.endIndex) }
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
				let _directoryURL = NSBundle(forClass: self.dynamicType).URLForResource(multipleSubprojects, withExtension: nil)!

				let relativePaths = relativePathsForProjectsInDirectory(_directoryURL)
				expect(relativePaths) == [ "SampleGitSubmodule.xcodeproj/" ]
			}
		}

		xit("should build for all platforms") {
			let dependencies = [
				ProjectIdentifier.GitHub(Repository(owner: "github", name: "Archimedes")),
				ProjectIdentifier.GitHub(Repository(owner: "ReactiveCocoa", name: "ReactiveCocoa")),
			]
			let version = PinnedVersion("0.1")

			for project in dependencies {
				let dependency = Dependency<PinnedVersion>(project: project, version: version)
				let result = buildDependencyProject(dependency, directoryURL, withConfiguration: "Debug")
					.flatten(.Concat)
					.ignoreTaskData()
					.on(next: { (project, scheme) in
						NSLog("Building scheme \"\(scheme)\" in \(project)")
					})
					.wait()

				expect(result.error).to(beNil())
			}

			let result = buildInDirectory(directoryURL, withConfiguration: "Debug")
				.flatten(.Concat)
				.ignoreTaskData()
				.on(next: { (project, scheme) in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error).to(beNil())

			// Verify that the build products exist at the top level.
			var projectNames = dependencies.map { project in project.name }
			projectNames.append("ReactiveCocoaLayout")

			for dependency in projectNames {
				let macPath = buildFolderURL.URLByAppendingPathComponent("Mac/\(dependency).framework").path!
				let macdSYMPath = (macPath as NSString).stringByAppendingPathExtension("dSYM")!
				let iOSPath = buildFolderURL.URLByAppendingPathComponent("iOS/\(dependency).framework").path!
				let iOSdSYMPath = (iOSPath as NSString).stringByAppendingPathExtension("dSYM")!

				for path in [ macPath, macdSYMPath, iOSPath, iOSdSYMPath ] {
					expect(path).to(beExistingDirectory())
				}
			}
			let frameworkFolderURL = buildFolderURL.URLByAppendingPathComponent("iOS/ReactiveCocoaLayout.framework")

			// Verify that the iOS framework is a universal binary for device
			// and simulator.
			let architectures = architecturesInPackage(frameworkFolderURL)
				.collect()
				.single()

			expect(architectures?.value).to(contain("i386", "armv7", "arm64"))

			// Verify that our dummy framework in the RCL iOS scheme built as
			// well.
			let auxiliaryFrameworkPath = buildFolderURL.URLByAppendingPathComponent("iOS/AuxiliaryFramework.framework").path!
			expect(auxiliaryFrameworkPath).to(beExistingDirectory())

			// Copy ReactiveCocoaLayout.framework to the temporary folder.
			let targetURL = targetFolderURL.URLByAppendingPathComponent("ReactiveCocoaLayout.framework", isDirectory: true)

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

			let modulesDirectoryURL = targetURL.URLByAppendingPathComponent("Modules", isDirectory: true)
			expect(NSFileManager.defaultManager().fileExistsAtPath(modulesDirectoryURL.path!)) == false

			var output: String = ""
			let codeSign = Task("/usr/bin/xcrun", arguments: [ "codesign", "--verify", "--verbose", targetURL.path! ])

			let codesignResult = launchTask(codeSign)
				.on(next: { taskEvent in
					switch taskEvent {
					case let .StandardError(data):
						output += NSString(data: data, encoding: NSStringEncoding(NSUTF8StringEncoding))! as String

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
			let _directoryURL = NSBundle(forClass: self.dynamicType).URLForResource(multipleSubprojects, withExtension: nil)!
			let _buildFolderURL = _directoryURL.URLByAppendingPathComponent(CarthageBinariesFolderPath)

			_ = try? NSFileManager.defaultManager().removeItemAtURL(_buildFolderURL)

			let result = buildInDirectory(_directoryURL, withConfiguration: "Debug")
				.flatten(.Concat)
				.ignoreTaskData()
				.on(next: { (project, scheme) in
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
				let path = _buildFolderURL.URLByAppendingPathComponent("\(platform)/\(framework).framework").path!
				expect(path).to(beExistingDirectory())
			}
		}

		it("should skip projects without shared dynamic framework schems") {
			let dependency = "SchemeDiscoverySampleForCarthage"
			let _directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("\(dependency)-0.2", withExtension: nil)!
			let _buildFolderURL = _directoryURL.URLByAppendingPathComponent(CarthageBinariesFolderPath)

			_ = try? NSFileManager.defaultManager().removeItemAtURL(_buildFolderURL)

			let result = buildInDirectory(_directoryURL, withConfiguration: "Debug")
				.flatten(.Concat)
				.ignoreTaskData()
				.on(next: { (project, scheme) in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error).to(beNil())

			let macPath = _buildFolderURL.URLByAppendingPathComponent("Mac/\(dependency).framework").path!
			let iOSPath = _buildFolderURL.URLByAppendingPathComponent("iOS/\(dependency).framework").path!

			for path in [ macPath, iOSPath ] {
				expect(path).to(beExistingDirectory())
			}
		}

		it("should error out with .NoSharedFrameworkSchemes if there is no shared framework schemes") {
			let _directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("Swell-0.5.0", withExtension: nil)!
			let _buildFolderURL = _directoryURL.URLByAppendingPathComponent(CarthageBinariesFolderPath)

			_ = try? NSFileManager.defaultManager().removeItemAtURL(_buildFolderURL)

			let result = buildInDirectory(_directoryURL, withConfiguration: "Debug")
				.flatten(.Concat)
				.ignoreTaskData()
				.on(next: { (project, scheme) in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error).notTo(beNil())

			let expectedError: Bool
			if case .NoSharedFrameworkSchemes? = result.error {
				expectedError = true
			} else {
				expectedError = false
			}

			expect(expectedError) == true
		}

		//x
		xit("should build for one platform") {
			let project = ProjectIdentifier.GitHub(Repository(owner: "github", name: "Archimedes"))
			let version = PinnedVersion("0.1")
			let dependency = Dependency<PinnedVersion>(project: project, version: version)
			let result = buildDependencyProject(dependency, directoryURL, withConfiguration: "Debug", platforms: [ .Mac ])
				.flatten(.Concat)
				.ignoreTaskData()
				.on(next: { (project, scheme) in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error).to(beNil())

			// Verify that the build product exists at the top level.
			let path = buildFolderURL.URLByAppendingPathComponent("Mac/\(project.name).framework").path!
			expect(path).to(beExistingDirectory())

			// Verify that the other platform wasn't built.
			let incorrectPath = buildFolderURL.URLByAppendingPathComponent("iOS/\(project.name).framework").path!
			expect(NSFileManager.defaultManager().fileExistsAtPath(incorrectPath, isDirectory: nil)) == false
		}

		xit("should build for multiple platforms") {
			let project = ProjectIdentifier.GitHub(Repository(owner: "github", name: "Archimedes"))
			let version = PinnedVersion("0.1")
			let dependency = Dependency<PinnedVersion>(project: project, version: version)

			let result = buildDependencyProject(dependency, directoryURL, withConfiguration: "Debug", platforms: [ .Mac, .iOS ])
				.flatten(.Concat)
				.ignoreTaskData()
				.on(next: { (project, scheme) in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error).to(beNil())

			// Verify that the build products of all specified platforms exist 
			// at the top level.
			let macPath = buildFolderURL.URLByAppendingPathComponent("Mac/\(project.name).framework").path!
			let iosPath = buildFolderURL.URLByAppendingPathComponent("iOS/\(project.name).framework").path!

			for path in [ macPath, iosPath ] {
				expect(path).to(beExistingDirectory())
			}
		}

		it("should locate the project") {
			let result = locateProjectsInDirectory(directoryURL).first()
			expect(result).notTo(beNil())
			expect(result?.error).to(beNil())
			expect(result?.value) == .ProjectFile(projectURL)
		}

		it("should locate the project from the parent directory") {
			let result = locateProjectsInDirectory(directoryURL.URLByDeletingLastPathComponent!).collect().first()
			expect(result).notTo(beNil())
			expect(result?.error).to(beNil())
			expect(result?.value).to(contain(.ProjectFile(projectURL)))
		}
		
		it("should not locate the project from a directory not containing it") {
			let result = locateProjectsInDirectory(directoryURL.URLByAppendingPathComponent("ReactiveCocoaLayout")).first()
			expect(result).to(beNil())
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
		let exists = NSFileManager.defaultManager().fileExistsAtPath(path, isDirectory: &isDirectory)

		if !exists {
			failureMessage.postfixMessage += ", but does not exist"
		} else if !isDirectory {
			failureMessage.postfixMessage += ", but is not a directory"
		}

		return exists && isDirectory
	}
}
