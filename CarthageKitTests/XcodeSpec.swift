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
		let directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("ReactiveCocoaLayout", withExtension: nil)!
		let workspaceURL = directoryURL.URLByAppendingPathComponent("ReactiveCocoaLayout.xcworkspace")
		let buildFolderURL = directoryURL.URLByAppendingPathComponent(CarthageBinariesFolderName)

		beforeEach {
			NSFileManager.defaultManager().removeItemAtURL(buildFolderURL, error: nil)
			return ()
		}

		it("should build for all platforms") {
			var macURL: NSURL!
			var iOSURL: NSURL!

			let result = buildInDirectory(directoryURL, withConfiguration: "Debug")
				.on(next: { productURL in
					expect(productURL.lastPathComponent).to(equal("ReactiveCocoaLayout.framework"))

					if contains(productURL.pathComponents as [String], "Mac") {
						macURL = productURL
					} else if contains(productURL.pathComponents as [String], "iOS") {
						iOSURL = productURL
					}
				})
				.wait()

			expect(result.error()).to(beNil())

			expect(macURL).notTo(beNil())
			expect(iOSURL).notTo(beNil())

			var isDirectory: ObjCBool = false
			expect(NSFileManager.defaultManager().fileExistsAtPath(macURL.path!, isDirectory: &isDirectory)).to(beTruthy())
			expect(isDirectory).to(beTruthy())

			expect(NSFileManager.defaultManager().fileExistsAtPath(iOSURL.path!, isDirectory: &isDirectory)).to(beTruthy())
			expect(isDirectory).to(beTruthy())

			// Verify that the iOS framework is a universal binary for device
			// and simulator.
			let output = launchTask(TaskDescription(launchPath: "/usr/bin/otool", arguments: [ "-fv", iOSURL.URLByAppendingPathComponent("ReactiveCocoaLayout").path! ]))
				.map { NSString(data: $0, encoding: NSStringEncoding(NSUTF8StringEncoding))! }
				.first()
				.value()!

			expect(output).to(contain("architecture i386"))
			expect(output).to(contain("architecture armv7"))
			expect(output).to(contain("architecture arm64"))
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
			let result = locateProjectsInDirectory(directoryURL.URLByAppendingPathComponent("ReactiveCocoaLayout")).wait()
			expect(result.isSuccess()).to(beFalsy())
		}
	}
}
