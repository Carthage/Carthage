//
//  VersionSpec.swift
//  Carthage
//
//  Created by J.D. Healy on 3/2/15.
//  Copyright (c) 2015 Carthage. All rights reserved.
//

import Foundation
import Nimble
import Quick
import LlamaKit
import ReactiveCocoa
import ReactiveTask

class VersionSpec: QuickSpec {
	override func spec() {
		describe("version") {

			for ttyEnabled in [true, false] {
				let suffix = " with" + (ttyEnabled ? "" : "out") + " TTY"

				it("should display version" + suffix) {
					expect(
						CLI.Carthage.launch(
							arguments: ["version"],
							modify: [.TTY(ttyEnabled)]
						)
						// ‘version’ output should have a dot in it’s version.
						.try( Assertion.output(contains: ".") )
						// ‘version’ output doesn’t include any colored elements.
						.try( Assertion.color(false) )
						.single().error()
					).to(beNil())
				}
			}

		}
	}
}
