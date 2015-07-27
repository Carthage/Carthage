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
		let targetFolderURL = NSURL(fileURLWithPath: NSTemporaryDirectory().stringByAppendingPathComponent(NSProcessInfo.processInfo().globallyUniqueString), isDirectory: true)!

		beforeEach {
			NSFileManager.defaultManager().removeItemAtURL(buildFolderURL, error: nil)

			expect(NSFileManager.defaultManager().createDirectoryAtPath(targetFolderURL.path!, withIntermediateDirectories: true, attributes: nil, error: nil)).to(beTruthy())
			return
		}
		
		afterEach {
			NSFileManager.defaultManager().removeItemAtURL(targetFolderURL, error: nil)
			return
		}

		it("should build for all platforms") {
			let machineHasiOSIdentity = iOSSigningIdentitiesConfigured()
			expect(machineHasiOSIdentity).to(equal(true))

			let dependencies = [
				ProjectIdentifier.GitHub(GitHubRepository(owner: "github", name: "Archimedes")),
				ProjectIdentifier.GitHub(GitHubRepository(owner: "ReactiveCocoa", name: "ReactiveCocoa")),
			]

			for project in dependencies {
				let result = buildDependencyProject(project, directoryURL, withConfiguration: "Debug")
					|> flatten(.Concat)
					|> ignoreTaskData
					|> on(next: { (project, scheme) in
						NSLog("Building scheme \"\(scheme)\" in \(project)")
					})
					|> wait

				expect(result.error).to(beNil())
			}

			let result = buildInDirectory(directoryURL, withConfiguration: "Debug")
				|> flatten(.Concat)
				|> ignoreTaskData
				|> on(next: { (project, scheme) in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				|> wait

			expect(result.error).to(beNil())

			// Verify that the build products exist at the top level.
			var projectNames = dependencies.map { project in project.name }
			projectNames.append("ReactiveCocoaLayout")

			for dependency in projectNames {
				let macPath = buildFolderURL.URLByAppendingPathComponent("Mac/\(dependency).framework").path!
				let macdSYMPath = macPath.stringByAppendingPathExtension("dSYM")!
				let iOSPath = buildFolderURL.URLByAppendingPathComponent("iOS/\(dependency).framework").path!
				let iOSdSYMPath = iOSPath.stringByAppendingPathExtension("dSYM")!

				var isDirectory: ObjCBool = false
				expect(NSFileManager.defaultManager().fileExistsAtPath(macPath, isDirectory: &isDirectory)).to(beTruthy())
				expect(isDirectory).to(beTruthy())

				expect(NSFileManager.defaultManager().fileExistsAtPath(macdSYMPath, isDirectory: &isDirectory)).to(beTruthy())
				expect(isDirectory).to(beTruthy())

				expect(NSFileManager.defaultManager().fileExistsAtPath(iOSPath, isDirectory: &isDirectory)).to(beTruthy())
				expect(isDirectory).to(beTruthy())

				expect(NSFileManager.defaultManager().fileExistsAtPath(iOSdSYMPath, isDirectory: &isDirectory)).to(beTruthy())
				expect(isDirectory).to(beTruthy())
			}
			let frameworkFolderURL = buildFolderURL.URLByAppendingPathComponent("iOS/ReactiveCocoaLayout.framework")

			// Verify that the iOS framework is a universal binary for device
			// and simulator.
			let architectures = architecturesInFramework(frameworkFolderURL)
				|> collect
				|> single

			expect(architectures?.value).to(contain("i386"))
			if machineHasiOSIdentity {
				expect(architectures?.value).to(contain("armv7"))
				expect(architectures?.value).to(contain("arm64"))
			}

			// Verify that our dummy framework in the RCL iOS scheme built as
			// well.
			let auxiliaryFrameworkPath = buildFolderURL.URLByAppendingPathComponent("iOS/AuxiliaryFramework.framework").path!
			var isDirectory: ObjCBool = false
			expect(NSFileManager.defaultManager().fileExistsAtPath(auxiliaryFrameworkPath, isDirectory: &isDirectory)).to(beTruthy())
			expect(isDirectory).to(beTruthy())

			// Copy ReactiveCocoaLayout.framework to the temporary folder.
			let targetURL = targetFolderURL.URLByAppendingPathComponent("ReactiveCocoaLayout.framework", isDirectory: true)

			let resultURL = copyFramework(frameworkFolderURL, targetURL) |> single
			expect(resultURL?.value).to(equal(targetURL))

			expect(NSFileManager.defaultManager().fileExistsAtPath(targetURL.path!, isDirectory: &isDirectory)).to(beTruthy())
			expect(isDirectory).to(beTruthy())

			if machineHasiOSIdentity {
				let strippingResult = stripFramework(targetURL, keepingArchitectures: [ "armv7" , "arm64" ], codesigningIdentity: "-") |> wait
				expect(strippingResult.value).notTo(beNil())
				
				let strippedArchitectures = architecturesInFramework(targetURL)
					|> collect
					|> single
				
				expect(strippedArchitectures?.value).notTo(contain("i386"))
				expect(strippedArchitectures?.value).to(contain("armv7"))
				expect(strippedArchitectures?.value).to(contain("arm64"))
				
				var output: String = ""
				let codeSign = TaskDescription(launchPath: "/usr/bin/xcrun", arguments: [ "codesign", "--verify", "--verbose", targetURL.path! ])
				
				let codesignResult = launchTask(codeSign)
					|> on(next: { taskEvent in
						switch taskEvent {
						case let .StandardError(data):
							output += NSString(data: data, encoding: NSStringEncoding(NSUTF8StringEncoding))! as String
							
						default:
							break
						}
					})
					|> wait
				
				expect(codesignResult.value).notTo(beNil())
				expect(output).to(contain("satisfies its Designated Requirement"))
			}
		}

		it("should skip projects without shared dynamic framework schems") {
			let dependency = "SwiftyJSON"
			let _directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("\(dependency)-2.2.0", withExtension: nil)!
			let _buildFolderURL = _directoryURL.URLByAppendingPathComponent(CarthageBinariesFolderPath)

			NSFileManager.defaultManager().removeItemAtURL(_buildFolderURL, error: nil)

			let result = buildInDirectory(_directoryURL, withConfiguration: "Debug")
				|> flatten(.Concat)
				|> ignoreTaskData
				|> on(next: { (project, scheme) in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				|> wait

			expect(result.error).to(beNil())

			let macPath = _buildFolderURL.URLByAppendingPathComponent("Mac/\(dependency).framework").path!
			let iOSPath = _buildFolderURL.URLByAppendingPathComponent("iOS/\(dependency).framework").path!

			var isDirectory: ObjCBool = false
			expect(NSFileManager.defaultManager().fileExistsAtPath(macPath, isDirectory: &isDirectory)).to(beTruthy())
			expect(isDirectory).to(beTruthy())

			expect(NSFileManager.defaultManager().fileExistsAtPath(iOSPath, isDirectory: &isDirectory)).to(beTruthy())
			expect(isDirectory).to(beTruthy())
		}

		it("should error out with .NoSharedFrameworkSchemes if there is no shared framework schemes") {
			let _directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("Swell-0.5.0", withExtension: nil)!
			let _buildFolderURL = _directoryURL.URLByAppendingPathComponent(CarthageBinariesFolderPath)

			NSFileManager.defaultManager().removeItemAtURL(_buildFolderURL, error: nil)

			let result = buildInDirectory(_directoryURL, withConfiguration: "Debug")
				|> flatten(.Concat)
				|> ignoreTaskData
				|> on(next: { (project, scheme) in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				|> wait

			expect(result.error).notTo(beNil())

			let expectedError: Bool
			switch result.error {
			case .Some(.NoSharedFrameworkSchemes):
				expectedError = true

			default:
				expectedError = false
			}

			expect(expectedError).to(beTruthy())
		}

		it("should build for one platform") {
			let project = ProjectIdentifier.GitHub(GitHubRepository(owner: "github", name: "Archimedes"))
			let result = buildDependencyProject(project, directoryURL, withConfiguration: "Debug", platform: .Mac)
				|> flatten(.Concat)
				|> ignoreTaskData
				|> on(next: { (project, scheme) in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				|> wait

			expect(result.error).to(beNil())

			// Verify that the build product exists at the top level.
			let path = buildFolderURL.URLByAppendingPathComponent("Mac/\(project.name).framework").path!
			var isDirectory: ObjCBool = false
			expect(NSFileManager.defaultManager().fileExistsAtPath(path, isDirectory: &isDirectory)).to(beTruthy())
			expect(isDirectory).to(beTruthy())

			// Verify that the other platform wasn't built.
			let incorrectPath = buildFolderURL.URLByAppendingPathComponent("iOS/\(project.name).framework").path!
			expect(NSFileManager.defaultManager().fileExistsAtPath(incorrectPath, isDirectory: nil)).to(beFalsy())
		}

		it("should locate the project") {
			let result = locateProjectsInDirectory(directoryURL) |> first
			expect(result).notTo(beNil())
			expect(result?.error).to(beNil())

			let locator = result?.value!
			expect(locator).to(equal(ProjectLocator.ProjectFile(projectURL)))
		}

		it("should locate the project from the parent directory") {
			let result = locateProjectsInDirectory(directoryURL.URLByDeletingLastPathComponent!) |> collect |> first
			expect(result).notTo(beNil())
			expect(result?.error).to(beNil())

			let locators = result?.value!
			expect(locators).to(contain(ProjectLocator.ProjectFile(projectURL)))
		}

		it("should not locate the project from a directory not containing it") {
			let result = locateProjectsInDirectory(directoryURL.URLByAppendingPathComponent("ReactiveCocoaLayout")) |> first
			expect(result).to(beNil())
		}
		
		it("should parse signing identities correctly") {
			
			var i = 0
			
			let inputLines = [
				"  1) 4E8D512C8480FAC679947D6E50190AE9BAB3E825 \"3rd Party Mac Developer Application: Some Developer (DUCNFCN445)\"",
				"  2) 8B0EBBAE7E7230BB6AF5D69CA09B769663BC844D \"Mac Developer: Developer Name (AUCNACN346)\"",
				"  3) 4E8D512C8480AAC67995D69CA09B769663BC844D \"iPhone Developer: App Developer (VZAPFCN445)\"",
				"  4) 65E24CDAF5B3E1E1480818CA4656210871214337 \"Developer ID Application: Development, Inc. (DSVNEZN954)\"",
				"     4 valid identities found"
			]
			
			let expectedOutput = [
				CodeSigningIdentity(
					IDHash: "4E8D512C8480FAC679947D6E50190AE9BAB3E825",
					IdentityType: "3rd Party Mac Developer Application",
					DeveloperName: "Some Developer",
					DeveloperID: "DUCNFCN445"
				),
				CodeSigningIdentity(
					IDHash: "8B0EBBAE7E7230BB6AF5D69CA09B769663BC844D",
					IdentityType: "Mac Developer",
					DeveloperName: "Developer Name",
					DeveloperID: "AUCNACN346"
				),
				CodeSigningIdentity(
					IDHash: "4E8D512C8480AAC67995D69CA09B769663BC844D",
					IdentityType: "iPhone Developer",
					DeveloperName: "App Developer",
					DeveloperID: "VZAPFCN445"
				),
				CodeSigningIdentity(
					IDHash: "65E24CDAF5B3E1E1480818CA4656210871214337",
					IdentityType: "Developer ID Application",
					DeveloperName: "Development, Inc.",
					DeveloperID: "DSVNEZN954"
				)
			]
			
			let result = parseSecuritySigningIdentities(securityIdentities: SignalProducer<String, CarthageError>(values: inputLines))
				|> on(next: { returnedValue in
					expect(returnedValue).to(equal(expectedOutput[i++]))
				})
				|> wait

			expect(result).notTo(beNil())
			
			// Verify that the checks above have run
			expect(i) > 0
		}
		
		it("should detect iPhone signing identities when present") {
			
			let result = iOSSigningIdentitiesConfigured(identities: SignalProducer<CodeSigningIdentity, CarthageError>(values: [
				CodeSigningIdentity(
					IDHash: "4E8D512C8480FAC679947D6E50190AE9BAB3E825",
					IdentityType: "3rd Party Mac Developer Application",
					DeveloperName: "Some Developer",
					DeveloperID: "DUCNFCN445"
				),
				CodeSigningIdentity(
					IDHash: "8B0EBBAE7E7230BB6AF5D69CA09B769663BC844D",
					IdentityType: "Mac Developer",
					DeveloperName: "Developer Name",
					DeveloperID: "AUCNACN346"
				),
				CodeSigningIdentity(
					IDHash: "4E8D512C8480AAC67995D69CA09B769663BC844D",
					IdentityType: "iPhone Developer",
					DeveloperName: "App Developer",
					DeveloperID: "VZAPFCN445"
				),
				CodeSigningIdentity(
					IDHash: "65E24CDAF5B3E1E1480818CA4656210871214337",
					IdentityType: "Developer ID Application",
					DeveloperName: "Development, Inc.",
					DeveloperID: "DSVNEZN954"
				)
				]))
			
			expect(result).to(equal(true))
		}
		
		it("should detect iOS signing identities when present (future compatibility)") {
			
			let result = iOSSigningIdentitiesConfigured(identities: SignalProducer<CodeSigningIdentity, CarthageError>(values: [
				CodeSigningIdentity(
					IDHash: "4E8D512C8480FAC679947D6E50190AE9BAB3E825",
					IdentityType: "3rd Party Mac Developer Application",
					DeveloperName: "Some Developer",
					DeveloperID: "DUCNFCN445"
				),
				CodeSigningIdentity(
					IDHash: "8B0EBBAE7E7230BB6AF5D69CA09B769663BC844D",
					IdentityType: "Mac Developer",
					DeveloperName: "Developer Name",
					DeveloperID: "AUCNACN346"
				),
				CodeSigningIdentity(
					IDHash: "4E8D512C8480AAC67995D69CA09B769663BC844D",
					IdentityType: "iOS Developer",
					DeveloperName: "App Developer",
					DeveloperID: "VZAPFCN445"
				),
				CodeSigningIdentity(
					IDHash: "65E24CDAF5B3E1E1480818CA4656210871214337",
					IdentityType: "Developer ID Application",
					DeveloperName: "Development, Inc.",
					DeveloperID: "DSVNEZN954"
				)
				]))
			
			expect(result).to(equal(true))
		}
		
		it("should detect when no iPhone or iOS signing identities when present") {
			
			let result = iOSSigningIdentitiesConfigured(identities: SignalProducer<CodeSigningIdentity, CarthageError>(values: [
				CodeSigningIdentity(
					IDHash: "4E8D512C8480FAC679947D6E50190AE9BAB3E825",
					IdentityType: "3rd Party Mac Developer Application",
					DeveloperName: "Some Developer",
					DeveloperID: "DUCNFCN445"
				),
				CodeSigningIdentity(
					IDHash: "8B0EBBAE7E7230BB6AF5D69CA09B769663BC844D",
					IdentityType: "Mac Developer",
					DeveloperName: "Developer Name",
					DeveloperID: "AUCNACN346"
				),
				CodeSigningIdentity(
					IDHash: "65E24CDAF5B3E1E1480818CA4656210871214337",
					IdentityType: "Developer ID Application",
					DeveloperName: "Development, Inc.",
					DeveloperID: "DSVNEZN954"
				)
				]))
			
			expect(result).to(equal(false))
		}
	}
}
