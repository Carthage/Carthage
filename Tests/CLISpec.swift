//
//  CLISpec.swift
//  CarthageTests
//
//  Created by J.D. Healy on 2/22/15.
//  Copyright (c) 2015 Carthage. All rights reserved.
//

import Foundation
import Nimble
import Quick
import LlamaKit
import ReactiveCocoa
import ReactiveTask

class CLISpec: QuickSpec {
	override func spec() {
		describe("CLI") {

			Fixture.DependsOnPrelude.temporaryDirectory

			it("should echo lemon with ZSH") {
				let echo = CLI.Modifier(modify: {
					launchPath, arguments, environment, workingDirectoryPath in
					return ("/bin/echo", arguments, environment, workingDirectoryPath)
				})
				
				expect(
					CLI.Carthage.launch(
						arguments: ["🍋"],
						modify: [echo, .ZSH()]
					)
					.try( Assertion.output(contains: "🍋") )
					.single().error()
				).to(beNil())
			}
			
		}
	}
}