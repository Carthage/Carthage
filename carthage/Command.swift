//
//  Command.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import ReactiveCocoa

protocol CommandType {
	var verb: String { get }

	init()

	func run(arguments: [String]) -> ColdSignal<()>
}

protocol OptionsType {
	class func parse(args: [String]) -> ColdSignal<Self>
}

protocol ArgumentType {
	class func fromString(string: String) -> Self?
}

struct Option<T> {
	let key: String
	let defaultValue: T
	let usage: String
}

func option<T: ArgumentType>(key: String, defaultValue: T, usage: String) -> Option<T> {
	return Option(key: key, defaultValue: defaultValue, usage: usage)
}

func option<T: ArgumentType>(key: String, usage: String) -> Option<T?> {
	return Option(key: key, defaultValue: nil, usage: usage)
}

extension Bool: ArgumentType {
	static func fromString(string: String) -> Bool? {
		return (string as NSString).boolValue
	}
}

extension Int: ArgumentType {
	static func fromString(string: String) -> Int? {
		return string.toInt()
	}
}

extension String: ArgumentType {
	static func fromString(string: String) -> String? {
		return string
	}
}

func usageError<T>(option: Option<T>, value: String?) -> NSError {
	var description: String?
	if let value = value {
		description = "Invalid value for \(option): \(value)"
	} else {
		description = "Missing argument for \(option)"
	}

	return NSError(domain: CarthageErrorDomain, code: 999, userInfo: [ NSLocalizedDescriptionKey: description! ])
}

// Inspired by the Argo library:
// https://github.com/thoughtbot/Argo
/*
	Copyright (c) 2014 thoughtbot, inc.

	MIT License

	Permission is hereby granted, free of charge, to any person obtaining
	a copy of this software and associated documentation files (the
	"Software"), to deal in the Software without restriction, including
	without limitation the rights to use, copy, modify, merge, publish,
	distribute, sublicense, and/or sell copies of the Software, and to
	permit persons to whom the Software is furnished to do so, subject to
	the following conditions:

	The above copyright notice and this permission notice shall be
	included in all copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
	EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
	MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
	NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
	LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
	OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
	WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
infix operator <*> {
	associativity left
}

infix operator <| {
	associativity left
	precedence 150
}

func <*><T, U>(f: T -> U, value: ColdSignal<T>) -> ColdSignal<U> {
	return value.map(f)
}

func <*><T, U>(f: ColdSignal<(T -> U)>, value: ColdSignal<T>) -> ColdSignal<U> {
	return f.combineLatestWith(value)
		.map { (f, value) in f(value) }
}

func <|<T: ArgumentType>(arguments: [String], option: Option<T>) -> ColdSignal<T> {
	var keyIndex = find(arguments, "--\(option.key)")
	if let keyIndex = keyIndex {
		if keyIndex + 1 < arguments.count {
			let stringValue = arguments[keyIndex + 1]
			if let value = T.fromString(stringValue) {
				return .single(value)
			} else {
				return .error(usageError(option, stringValue))
			}
		}

		return .error(usageError(option, nil))
	}

	return .single(option.defaultValue)
}

func <|<T: ArgumentType>(arguments: [String], option: Option<T?>) -> ColdSignal<T?> {
	var keyIndex = find(arguments, "--\(option.key)")
	if let keyIndex = keyIndex {
		if keyIndex + 1 < arguments.count {
			let stringValue = arguments[keyIndex + 1]
			if let value = T.fromString(stringValue) {
				return .single(value)
			} else {
				return .error(usageError(option, stringValue))
			}
		}

		return .error(usageError(option, nil))
	}

	return .single(nil)
}
