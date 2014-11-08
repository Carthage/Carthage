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

class XcodeSpec: QuickSpec {
	override func spec() {
		let directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("TestFramework", withExtension: nil, subdirectory: "fixtures")!
		let buildFolderURL = directoryURL.URLByAppendingPathComponent(CarthageBinariesFolderName)

		beforeEach {
			NSFileManager.defaultManager().removeItemAtURL(buildFolderURL, error: nil)
			return ()
		}

		it("should build for all platforms") {
			let result = buildInDirectory(directoryURL, withConfiguration: "Debug").wait()
			expect(result.error()).to(beNil())

			let macURL = buildFolderURL.URLByAppendingPathComponent("Mac/TestFramework.framework/TestFramework")
			var isDirectory: ObjCBool = false
			expect(NSFileManager.defaultManager().fileExistsAtPath(macURL.path!, isDirectory: &isDirectory)).to(beTruthy())
			expect(isDirectory).to(beFalsy())

			let iOSURL = buildFolderURL.URLByAppendingPathComponent("iOS/TestFramework.framework/TestFramework")
			expect(NSFileManager.defaultManager().fileExistsAtPath(iOSURL.path!, isDirectory: &isDirectory)).to(beTruthy())
			expect(isDirectory).to(beFalsy())

			// Verify that the iOS framework is a universal binary for device
			// and simulator.
			let output = launchTask(TaskDescription(launchPath: "/usr/bin/otool", arguments: [ "-fv", iOSURL.path! ]))
				.map { NSString(data: $0, encoding: NSStringEncoding(NSUTF8StringEncoding))! }
				.first()
				.value()!

			expect(output).to(contain("architecture i386"))
			expect(output).to(contain("architecture armv7"))
			expect(output).to(contain("architecture arm64"))
		}

		it("should locate the project") {
			let result = locateProjectsInDirectory(directoryURL).first()
			expect(result.error()).to(beNil())

			let locator = result.value()!
			let expectedURL = directoryURL.URLByAppendingPathComponent("TestFramework.xcodeproj")
			expect(locator).to(equal(ProjectLocator.ProjectFile(expectedURL)))
		}

		it("should locate the project from the parent directory") {
			let result = locateProjectsInDirectory(directoryURL.URLByDeletingLastPathComponent!).first()
			expect(result.error()).to(beNil())

			let locator = result.value()!
			let expectedURL = directoryURL.URLByAppendingPathComponent("TestFramework.xcodeproj")
			expect(locator).to(equal(ProjectLocator.ProjectFile(expectedURL)))
		}

		it("should not locate the project from a directory not containing it") {
			let result = locateProjectsInDirectory(directoryURL.URLByAppendingPathComponent("TestFramework")).wait()
			expect(result.isSuccess()).to(beFalsy())
		}
	}
}
