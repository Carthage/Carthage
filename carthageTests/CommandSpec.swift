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

class OptionsTypeSpec: QuickSpec {
	override func spec() {
		describe("CommandMode.Arguments") {
			func tryArguments(arguments: String...) -> Result<TestOptions> {
				return TestOptions.evaluate(.Arguments(ArgumentParser(arguments)))
			}

			it("should fail if a required argument is missing") {
				expect(tryArguments().isSuccess()).to(beFalsy())
			}

			it("should fail if an option is missing a value") {
				expect(tryArguments("required", "--intValue").isSuccess()).to(beFalsy())
			}

			it("should succeed without optional arguments") {
				let value = tryArguments("required").value()
				let expected = TestOptions(intValue: 42, stringValue: "foobar", optionalFilename: "filename", requiredName: "required", enabled: false)
				expect(value).to(equal(expected))
			}

			it("should succeed with some optional arguments") {
				let value = tryArguments("required", "--intValue", "3", "fuzzbuzz").value()
				let expected = TestOptions(intValue: 3, stringValue: "foobar", optionalFilename: "fuzzbuzz", requiredName: "required", enabled: false)
				expect(value).to(equal(expected))
			}

			it("should override previous optional arguments") {
				let value = tryArguments("required", "--intValue", "3", "--stringValue", "fuzzbuzz", "--intValue", "5", "--stringValue", "bazbuzz").value()
				let expected = TestOptions(intValue: 5, stringValue: "bazbuzz", optionalFilename: "filename", requiredName: "required", enabled: false)
				expect(value).to(equal(expected))
			}

			it("should enable a boolean flag") {
				let value = tryArguments("required", "--enabled", "--intValue", "3", "fuzzbuzz").value()
				let expected = TestOptions(intValue: 3, stringValue: "foobar", optionalFilename: "fuzzbuzz", requiredName: "required", enabled: true)
				expect(value).to(equal(expected))
			}

			it("should re-disable a boolean flag") {
				let value = tryArguments("required", "--enabled", "--no-enabled", "--intValue", "3", "fuzzbuzz").value()
				let expected = TestOptions(intValue: 3, stringValue: "foobar", optionalFilename: "fuzzbuzz", requiredName: "required", enabled: false)
				expect(value).to(equal(expected))
			}

			it("should treat -- as the end of valued options") {
				let value = tryArguments("--", "--intValue").value()
				let expected = TestOptions(intValue: 42, stringValue: "foobar", optionalFilename: "filename", requiredName: "--intValue", enabled: false)
				expect(value).to(equal(expected))
			}
		}

		describe("CommandMode.Usage") {
			it("should return an error containing usage information") {
				let error = TestOptions.evaluate(.Usage).error()!
				expect(error.localizedDescription).to(contain("intValue"))
				expect(error.localizedDescription).to(contain("stringValue"))
				expect(error.localizedDescription).to(contain("name you're required to"))
				expect(error.localizedDescription).to(contain("optionally specify"))
			}
		}
	}
}

struct TestOptions: OptionsType, Equatable {
	let intValue: Int
	let stringValue: String
	let optionalFilename: String
	let requiredName: String
	let enabled: Bool

	static func create(a: Int)(b: String)(c: String)(d: String)(e: Bool) -> TestOptions {
		return self(intValue: a, stringValue: b, optionalFilename: d, requiredName: c, enabled: e)
	}

	static func evaluate(m: CommandMode) -> Result<TestOptions> {
		return create
			<*> m <| Option(key: "intValue", defaultValue: 42, usage: "Some integer value")
			<*> m <| Option(key: "stringValue", defaultValue: "foobar", usage: "Some string value")
			<*> m <| Option(usage: "A name you're required to specify")
			<*> m <| Option(defaultValue: "filename", usage: "A filename that you can optionally specify")
			<*> m <| Option(key: "enabled", defaultValue: false, usage: "Whether to be enabled")
	}
}

func ==(lhs: TestOptions, rhs: TestOptions) -> Bool {
	return lhs.intValue == rhs.intValue && lhs.stringValue == rhs.stringValue && lhs.optionalFilename == rhs.optionalFilename && lhs.requiredName == rhs.requiredName
}

extension TestOptions: Printable {
	var description: String {
		return "{ intValue: \(intValue), stringValue: \(stringValue), optionalFilename: \(optionalFilename), requiredName: \(requiredName) }"
	}
}
