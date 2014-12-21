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
		let projectURL = directoryURL.URLByAppendingPathComponent("ReactiveCocoaLayout.xcodeproj")
		let buildFolderURL = directoryURL.URLByAppendingPathComponent(CarthageBinariesFolderPath)

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

			for dependency in projectNames {
				let macPath = buildFolderURL.URLByAppendingPathComponent("Mac/\(dependency).framework").path!
				let iOSPath = buildFolderURL.URLByAppendingPathComponent("iOS/\(dependency).framework").path!

				var isDirectory: ObjCBool = false
				expect(NSFileManager.defaultManager().fileExistsAtPath(macPath, isDirectory: &isDirectory)).to(beTruthy())
				expect(isDirectory).to(beTruthy())

				expect(NSFileManager.defaultManager().fileExistsAtPath(iOSPath, isDirectory: &isDirectory)).to(beTruthy())
				expect(isDirectory).to(beTruthy())
			}
	
			// Verify that the iOS framework is a universal binary for device
			// and simulator.
			let otoolResult = launchTask(TaskDescription(launchPath: "/usr/bin/xcrun", arguments: [ "otool", "-fv", buildFolderURL.URLByAppendingPathComponent("iOS/ReactiveCocoaLayout.framework/ReactiveCocoaLayout").path! ]))
				.map { NSString(data: $0, encoding: NSStringEncoding(NSUTF8StringEncoding))! }
				.first()
			
			expect(otoolResult.error()).to(beNil())
			expect(otoolResult.value()).to(contain("architecture i386"))
			expect(otoolResult.value()).to(contain("architecture armv7"))
			expect(otoolResult.value()).to(contain("architecture arm64"))

			// Verify that our dummy framework in the RCL iOS scheme built as
			// well.
			let auxiliaryFrameworkPath = buildFolderURL.URLByAppendingPathComponent("iOS/AuxiliaryFramework.framework").path!
			var isDirectory: ObjCBool = false
			expect(NSFileManager.defaultManager().fileExistsAtPath(auxiliaryFrameworkPath, isDirectory: &isDirectory)).to(beTruthy())
			expect(isDirectory).to(beTruthy())
		}

		it("should locate the project") {
			let result = locateProjectsInDirectory(directoryURL).first()
			expect(result.error()).to(beNil())

			let locator = result.value()!
			expect(locator).to(equal(ProjectLocator.ProjectFile(projectURL)))
		}

		it("should locate the project from the parent directory") {
			let result = locateProjectsInDirectory(directoryURL.URLByDeletingLastPathComponent!).first()
			expect(result.error()).to(beNil())

			let locator = result.value()!
			expect(locator).to(equal(ProjectLocator.ProjectFile(projectURL)))
		}

		it("should not locate the project from a directory not containing it") {
			let result = locateProjectsInDirectory(directoryURL.URLByAppendingPathComponent("ReactiveCocoaLayout")).first()
			expect(result.value()).to(beNil())
		}
	}
}
