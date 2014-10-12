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
			let result = buildInDirectory(directoryURL).await()
			expect(result.error()).to(beNil())
		}
	}
}
