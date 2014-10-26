//
//  CommandSpec.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-25.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import Nimble
import Quick

struct TestOptions: OptionsType {
	let intValue: Int
	let stringValue: String
	let optionalFilename: String
	let requiredName: String

	static func create(a: Int)(b: String)(c: String)(d: String) -> TestOptions {
		return self(intValue: a, stringValue: b, optionalFilename: c, requiredName: d)
	}

	static func evaluate(m: CommandMode) -> Result<TestOptions> {
		return create
			<*> m <| Option(key: "intValue", defaultValue: 0, usage: "Some integer value")
			<*> m <| Option(key: "stringValue", defaultValue: "foobar", usage: "Some string value")
			<*> m <| Option(defaultValue: "", usage: "A filename that you can optionally specify")
			<*> m <| Option(usage: "A name you're required to specify")
	}
}

class OptionsTypeSpec: QuickSpec {
	override func spec() {
		describe("CommandMode.Arguments") {
			func tryArguments(arguments: String...) -> Result<TestOptions> {
				return TestOptions.evaluate(.Arguments(ArgumentGenerator(arguments)))
			}

			it("should fail if a required argument is missing") {
				expect(tryArguments().isSuccess()).to(beFalsy())
			}
		}

		describe("CommandMode.Usage") {
		}
	}
}
