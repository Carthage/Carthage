//
//  BootstrapSpec.swift
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

class BootstrapSpec: QuickSpec {
	override func spec() {
		describe("bootstrap") {

			it("should not bootstrap with platform of lemon") {
				expect(
					CLI.Carthage.launch(
						arguments: ["bootstrap", "--platform", "🍋"],
						workingDirectoryPath: Fixture.DependsOnPrelude
					).single().error()
				).notTo(beNil())
			}

			for ttyEnabled in [true, false] {
				let suffix = " with" + (ttyEnabled ? "" : "out") + " TTY"

				let with·or·without = "xxx"

				let out = ttyEnabled ? "" : "out"
				let reverseOut = ttyEnabled ? "out" : ""

				it("should bootstrap with\(out) color" + suffix) {
					expect(
						CLI.Carthage.launch(
							arguments: ["bootstrap", "--verbose", "--platform", "Mac"],
							workingDirectoryPath: Fixture.DependsOnPrelude,
							modify: [.TTY(ttyEnabled)]
						)
							.try( Assertion.color(ttyEnabled) )
							.try( Assertion.output(contains: "BUILD TARGET") )
							.single().error()
					).to(beNil())
				}
			}

		}
	}
}
