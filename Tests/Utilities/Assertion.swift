//
//  Assertion.swift
//  Carthage
//
//  Created by J.D. Healy on 3/3/15.
//  Copyright (c) 2015 Carthage. All rights reserved.
//

import Foundation
import LlamaKit

/// Functions to use in a `tryMap` on a `ColdSignal<String>`.
internal struct Assertion {

	static func output(#contains: String)(output: String) -> Result<String> {
		let asserted = contains

		if output.rangeOfString(asserted) != nil {
			return success(output)
		} else {
			return Error.Assertion.failure("Assertion failed: «\(asserted)» not found.")
		}
	}

	static func output(matches: NSRegularExpression)(output: String) -> Result<String> {
		let regularExpression = matches
		
		if regularExpression.matchesInString(
			output,
			options: nil,
			range: NSMakeRange(0, countElements(output))
		).isEmpty {
			return Error.Assertion.failure("Assertion failed: «\(regularExpression)» not matched.")
		} else {
			return success(output)
		}
	}

	static func color(assertion: Bool)(output: String) -> Result<String> {
    switch output.rangeOfString("\u{001B}") {
    case .Some where assertion == true:
			return success(output)
    case .None where assertion == false:
			return success(output)
    default:
			return Error.Assertion.failure(
				"Asserion failed: color " + { $0 ? "found." : "not found." }(!assertion)
			)
    }
  }

}

