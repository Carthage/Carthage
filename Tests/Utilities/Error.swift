//
//  Error.swift
//  Carthage
//
//  Created by J.D. Healy on 3/3/15.
//  Copyright (c) 2015 Carthage. All rights reserved.
//

import Foundation
import LlamaKit

/// Errors for CarthageTests. Methods for `NSError`s and `LlamaKit.failure`s.
enum Error: Int {
	case PathResolution = 100
	case StringifyData
	case Assertion

	static let domain = "org.carthage.CarthageTests"

	func error(description: String) -> NSError {
		return Error.error(description, code: self.rawValue)
	}

	func failure<T>(description: String) -> Result<T> {
		return LlamaKit.failure( error(description) )
	}

	static func error(description: String, code: Int) -> NSError {
		return NSError(domain: Error.domain, code: code, userInfo: [ NSLocalizedDescriptionKey: description ])
	}

	static func failure<T>(description: String? = nil) -> Result<T> {
		return LlamaKit.failure( Error.error(description ?? "Generic error.", code: 900) )
	}
}
