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
		let directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("TestFramework", withExtension: nil)!

		it("should build") {
			let result = buildInDirectory(directoryURL).wait()
			expect(result.error()).to(beNil())
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
