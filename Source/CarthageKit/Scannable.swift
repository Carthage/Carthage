//
//  Scannable.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-08.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import Result

/// Anything that can be parsed from an NSScanner.
public protocol Scannable {
	/// Attempts to parse an instance of the receiver from the given scanner.
	///
	/// If parsing fails, the scanner will be left at the first invalid
	/// character (with any partially valid input already consumed).
	static func fromScanner(scanner: NSScanner) -> Result<Self, CarthageError>
}
