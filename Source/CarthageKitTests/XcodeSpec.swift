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

class XcodeSpec: QuickSpec {
	override func spec() {
		let directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("ReactiveCocoaLayout", withExtension: nil)!
		let projectURL = directoryURL.URLByAppendingPathComponent("ReactiveCocoaLayout.xcodeproj")
		let buildFolderURL = directoryURL.URLByAppendingPathComponent(CarthageBinariesFolderPath)
		let targetFolderURL = NSURL(fileURLWithPath: (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent(NSProcessInfo.processInfo().globallyUniqueString), isDirectory: true)

		beforeEach {
			_ = try? NSFileManager.defaultManager().removeItemAtURL(buildFolderURL)

			expect { try NSFileManager.defaultManager().createDirectoryAtPath(targetFolderURL.path!, withIntermediateDirectories: true, attributes: nil) }.notTo(throwError())
			return
		}
		
		afterEach {
			_ = try? NSFileManager.defaultManager().removeItemAtURL(targetFolderURL)
			return
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
				let pathsStartingWithCarthage = relativePaths.filter { $0.hasPrefix("Carthage/") }
				expect(pathsStartingWithCarthage).to(beEmpty())
			}

			it("should not find anything that's listed as a git submodule") {
				let multipleSubprojects = "SampleGitSubmodule"
				let _directoryURL = NSBundle(forClass: self.dynamicType).URLForResource(multipleSubprojects, withExtension: nil)!

				let relativePaths = relativePathsForProjectsInDirectory(_directoryURL)
				expect(relativePaths) == [ "SampleGitSubmodule.xcodeproj/" ]
			}
		}

		it("should build for all platforms") {
			let dependencies = [
				ProjectIdentifier.GitHub(GitHubRepository(owner: "github", name: "Archimedes")),
				ProjectIdentifier.GitHub(GitHubRepository(owner: "ReactiveCocoa", name: "ReactiveCocoa")),
			]

			for project in dependencies {
				let result = buildDependencyProject(project, directoryURL, withConfiguration: "Debug")
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

				var isDirectory: ObjCBool = false
				expect(NSFileManager.defaultManager().fileExistsAtPath(macPath, isDirectory: &isDirectory)) == true
				expect(isDirectory) == true

				expect(NSFileManager.defaultManager().fileExistsAtPath(macdSYMPath, isDirectory: &isDirectory)) == true
				expect(isDirectory) == true

				expect(NSFileManager.defaultManager().fileExistsAtPath(iOSPath, isDirectory: &isDirectory)) == true
				expect(isDirectory) == true

				expect(NSFileManager.defaultManager().fileExistsAtPath(iOSdSYMPath, isDirectory: &isDirectory)) == true
				expect(isDirectory) == true
			}
			let frameworkFolderURL = buildFolderURL.URLByAppendingPathComponent("iOS/ReactiveCocoaLayout.framework")

			// Verify that the iOS framework is a universal binary for device
			// and simulator.
			let architectures = architecturesInPackage(frameworkFolderURL)
				.collect()
				.single()

			expect(architectures?.value).to(contain("i386"))
			expect(architectures?.value).to(contain("armv7"))
			expect(architectures?.value).to(contain("arm64"))

			// Verify that our dummy framework in the RCL iOS scheme built as
			// well.
			let auxiliaryFrameworkPath = buildFolderURL.URLByAppendingPathComponent("iOS/AuxiliaryFramework.framework").path!
			var isDirectory: ObjCBool = false
			expect(NSFileManager.defaultManager().fileExistsAtPath(auxiliaryFrameworkPath, isDirectory: &isDirectory)) == true
			expect(isDirectory) == true

			// Copy ReactiveCocoaLayout.framework to the temporary folder.
			let targetURL = targetFolderURL.URLByAppendingPathComponent("ReactiveCocoaLayout.framework", isDirectory: true)

			let resultURL = copyProduct(frameworkFolderURL, targetURL).single()
			expect(resultURL?.value) == targetURL

			expect(NSFileManager.defaultManager().fileExistsAtPath(targetURL.path!, isDirectory: &isDirectory)) == true
			expect(isDirectory) == true

			let strippingResult = stripFramework(targetURL, keepingArchitectures: [ "armv7" , "arm64" ], codesigningIdentity: "-").wait()
			expect(strippingResult.value).notTo(beNil())
			
			let strippedArchitectures = architecturesInPackage(targetURL)
				.collect()
				.single()
			
			expect(strippedArchitectures?.value).notTo(contain("i386"))
			expect(strippedArchitectures?.value).to(contain("armv7"))
			expect(strippedArchitectures?.value).to(contain("arm64"))

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
				var isDirectory: ObjCBool = false

				let path = _buildFolderURL.URLByAppendingPathComponent("\(platform)/\(framework).framework").path!

				let fileExists = NSFileManager.defaultManager().fileExistsAtPath(path, isDirectory: &isDirectory)
				expect(fileExists) == true
				if fileExists {
					expect(isDirectory) == true
				} else {
					print("failed to build \(platform)/\(framework).framework")
				}
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

			var isDirectory: ObjCBool = false
			expect(NSFileManager.defaultManager().fileExistsAtPath(macPath, isDirectory: &isDirectory)) == true
			expect(isDirectory) == true

			expect(NSFileManager.defaultManager().fileExistsAtPath(iOSPath, isDirectory: &isDirectory)) == true
			expect(isDirectory) == true
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
			switch result.error {
			case .Some(.NoSharedFrameworkSchemes):
				expectedError = true

			default:
				expectedError = false
			}

			expect(expectedError) == true
		}

		it("should build for one platform") {
			let project = ProjectIdentifier.GitHub(GitHubRepository(owner: "github", name: "Archimedes"))
			let result = buildDependencyProject(project, directoryURL, withConfiguration: "Debug", platforms: [ .Mac ])
				.flatten(.Concat)
				.ignoreTaskData()
				.on(next: { (project, scheme) in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error).to(beNil())

			// Verify that the build product exists at the top level.
			let path = buildFolderURL.URLByAppendingPathComponent("Mac/\(project.name).framework").path!
			var isDirectory: ObjCBool = false
			expect(NSFileManager.defaultManager().fileExistsAtPath(path, isDirectory: &isDirectory)) == true
			expect(isDirectory) == true

			// Verify that the other platform wasn't built.
			let incorrectPath = buildFolderURL.URLByAppendingPathComponent("iOS/\(project.name).framework").path!
			expect(NSFileManager.defaultManager().fileExistsAtPath(incorrectPath, isDirectory: nil)) == false
		}

		it("should build for multiple platforms") {
			let project = ProjectIdentifier.GitHub(GitHubRepository(owner: "github", name: "Archimedes"))
			let result = buildDependencyProject(project, directoryURL, withConfiguration: "Debug", platforms: [ .Mac, .iOS ])
				.flatten(.Concat)
				.ignoreTaskData()
				.on(next: { (project, scheme) in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error).to(beNil())

			var isDirectory: ObjCBool = false

			// Verify that the one build product exists at the top level.
			let macPath = buildFolderURL.URLByAppendingPathComponent("Mac/\(project.name).framework").path!
			expect(NSFileManager.defaultManager().fileExistsAtPath(macPath, isDirectory: &isDirectory)) == true
			expect(isDirectory) == true

			// Verify that the other build product exists at the top level.
			let iosPath = buildFolderURL.URLByAppendingPathComponent("iOS/\(project.name).framework").path!
			expect(NSFileManager.defaultManager().fileExistsAtPath(iosPath, isDirectory: &isDirectory)) == true
			expect(isDirectory) == true
		}

		it("should locate the project") {
			let result = locateProjectsInDirectory(directoryURL).first()
			expect(result).notTo(beNil())
			expect(result?.error).to(beNil())

			let locator = result?.value!
			expect(locator) == ProjectLocator.ProjectFile(projectURL)
		}

		it("should locate the project from the parent directory") {
			let result = locateProjectsInDirectory(directoryURL.URLByDeletingLastPathComponent!).collect().first()
			expect(result).notTo(beNil())
			expect(result?.error).to(beNil())

			let locators = result?.value!
			expect(locators).to(contain(ProjectLocator.ProjectFile(projectURL)))
		}

		it("should not locate the project from a directory not containing it") {
			let result = locateProjectsInDirectory(directoryURL.URLByAppendingPathComponent("ReactiveCocoaLayout")).first()
			expect(result).to(beNil())
		}

	}
}

// MARK: Helpers

extension ObjCBool: Equatable {}

public func == (lhs: ObjCBool, rhs: ObjCBool) -> Bool {
	return lhs.boolValue == rhs.boolValue
}
