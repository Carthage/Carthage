//
//  XcodeSpec.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-11.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import LlamaKit
import Nimble
import Quick
import ReactiveCocoa
import ReactiveTask

class XcodeSpec: QuickSpec {
	override func spec() {
		let directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("ReactiveCocoaLayout", withExtension: nil)!
		let workspaceURL = directoryURL.URLByAppendingPathComponent("ReactiveCocoaLayout.xcworkspace")
		let buildFolderURL = directoryURL.URLByAppendingPathComponent(CarthageBinariesFolderName)

		beforeEach {
			NSFileManager.defaultManager().removeItemAtURL(buildFolderURL, error: nil)
			return ()
		}

		it("should build for all platforms") {
			let dependencies = [
				ProjectIdentifier.GitHub(GitHubRepository(owner: "github", name: "Archimedes")),
				ProjectIdentifier.GitHub(GitHubRepository(owner: "ReactiveCocoa", name: "ReactiveCocoa")),
			]

			for project in dependencies {
				let (outputSignal, schemeSignals) = buildDependencyProject(project, directoryURL, withConfiguration: "Debug")
				let result = schemeSignals
					.concat(identity)
					.on(next: { (project, scheme) in
						NSLog("Building scheme \"\(scheme)\" in \(project)")
					})
					.wait()

				expect(result.error()).to(beNil())
			}

			let (outputSignal, schemeSignals) = buildInDirectory(directoryURL, withConfiguration: "Debug")
			let result = schemeSignals
				.concat(identity)
				.on(next: { (project, scheme) in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error()).to(beNil())

			// Verify that the build products exist at the top level.
			var projectNames = dependencies.map { project in project.name }
			projectNames.append("ReactiveCocoaLayout")

			func buildDirectoryURLPath(pathComponent: String) -> String {
				let path: String! = buildFolderURL.URLByAppendingPathComponent(pathComponent).path
				expect(path).notTo(beNil())
				return path
			}

			for dependency in projectNames {
				let macPath = buildDirectoryURLPath("Mac/\(dependency).framework")
				let iOSPath = buildDirectoryURLPath("iOS/\(dependency).framework")

				var isDirectory: ObjCBool = false
				expect(NSFileManager.defaultManager().fileExistsAtPath(macPath, isDirectory: &isDirectory)).to(beTruthy())
				expect(isDirectory).to(beTruthy())

				expect(NSFileManager.defaultManager().fileExistsAtPath(iOSPath, isDirectory: &isDirectory)).to(beTruthy())
				expect(isDirectory).to(beTruthy())
			}

			// Verify that the iOS framework is a universal binary for device
			// and simulator.
			func otool(arguments: String...) -> ColdSignal<NSData> {
				return launchTask(TaskDescription(launchPath: "/usr/bin/otool", arguments: arguments))
			}

			let otoolResult = otool("-fv", buildDirectoryURLPath("iOS/ReactiveCocoaLayout.framework/ReactiveCocoaLayout")).first()
			switch otoolResult {
			case .Success(let data):
				let output = NSString(data: data.unbox, encoding: NSStringEncoding(NSUTF8StringEncoding))
				if let output = output {
					expect(output).to(contain("architecture i386"))
					expect(output).to(contain("architecture armv7"))
					expect(output).to(contain("architecture arm64"))
				} else { expect(output).notTo(beNil()) }
			case .Failure(let failure):
				expect(otoolResult).verify(otoolResult.isSuccess(), failure.description)
			}

			// Verify that our dummy framework in the RCL iOS scheme built as
			// well.
			let auxiliaryFrameworkPath = buildDirectoryURLPath("iOS/AuxiliaryFramework.framework")
			var isDirectory: ObjCBool = false
			expect(NSFileManager.defaultManager().fileExistsAtPath(auxiliaryFrameworkPath, isDirectory: &isDirectory)).to(beTruthy())
			expect(isDirectory).to(beTruthy())
		}

		it("should locate the workspace") {
			let result = locateProjectsInDirectory(directoryURL).first()
			expect(result.error()).to(beNil())

			let locator = result.value()!
			expect(locator).to(equal(ProjectLocator.Workspace(workspaceURL)))
		}

		it("should locate the project from the parent directory") {
			let result = locateProjectsInDirectory(directoryURL.URLByDeletingLastPathComponent!).first()
			expect(result.error()).to(beNil())

			let locator = result.value()!
			expect(locator).to(equal(ProjectLocator.Workspace(workspaceURL)))
		}

		it("should not locate the project from a directory not containing it") {
			let result = locateProjectsInDirectory(directoryURL.URLByAppendingPathComponent("ReactiveCocoaLayout")).first()
			expect(result.value()).to(beNil())
		}
	}
}
