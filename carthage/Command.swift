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

/// Represents a Carthage subcommand that can be executed with its own set of
/// arguments.
public protocol CommandType {
	/// The action that users should specify to use this subcommand (e.g.,
	/// `help`).
	var verb: String { get }

	/// Runs this subcommand with the given arguments.
	///
	/// Returns a signal that will complete or error when the command finishes.
	func run(arguments: [String]) -> ColdSignal<()>
}

/// Represents a record of options for a command, which can be parsed from
/// a list of command-line arguments.
///
/// This is most helpful when used in conjunction with the `option` function,
/// and `<*>` and `<|` combinators.
///
/// Example:
///
///		struct LogOptions: OptionsType {
///			let verbosity: Int
///			let outputFilename: String?
///			let logName: String
///
///			static func create(verbosity: Int)(outputFilename: String?)(logName: String) -> LogOptions {
///				return LogOptions(verbosity: verbosity, outputFilename: outputFilename, logName: logName)
///			}
///
///			static func parse(args: [String]) -> ColdSignal<LogOptions> {
///				return create
///					<*> args <| option("verbose", 0, "The verbosity level with which to read the logs")
///					<*> args <| option("outputFilename", "A file to print output to, instead of stdout")
///					<*> args <| option("logName", "all", "The log to read")
///			}
///		}
public protocol OptionsType {
	/// Parses a set of options from the given command-line arguments.
	///
	/// Returns a signal that will error if the arguments are invalid for the
	/// receiving OptionsType.
	class func parse(args: [String]) -> ColdSignal<Self>
}

/// Describes an option that can be provided on the command line.
public struct Option<T> {
	/// The key that controls this option.
	///
	/// For example, a key of `verbose` would be used for a `--verbose` option.
	public let key: String

	/// The default value for this option. This is the value that will be used
	/// if the option is never explicitly specified on the command line.
	public let defaultValue: T

	/// A human-readable string describing the purpose of this option. This will
	/// be shown in help messages.
	public let usage: String
}

/// Constructs an option with the given parameters.
public func option<T: ArgumentType>(key: String, defaultValue: T, usage: String) -> Option<T> {
	return Option(key: key, defaultValue: defaultValue, usage: usage)
}

/// Contructs a nullable option with the given parameters.
///
/// This must be used for options that permit `nil`, because it's impossible to
/// extend `Optional` with the `ArgumentType` protocol.
public func option<T: ArgumentType>(key: String, usage: String) -> Option<T?> {
	return Option(key: key, defaultValue: nil, usage: usage)
}

/// Represents a value that can be converted from a command-line argument.
public protocol ArgumentType {
	/// Attempts to parse a value from the given command-line argument.
	class func fromString(string: String) -> Self?
}

extension Int: ArgumentType {
	public static func fromString(string: String) -> Int? {
		return string.toInt()
	}
}

extension String: ArgumentType {
	public static func fromString(string: String) -> String? {
		return string
	}
}

/// Constructs an error that describes how `option` was used incorrectly.
///
/// If provided, `value` should be the invalid value given by the user.
private func usageError<T>(option: Option<T>, value: String?) -> NSError {
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

/// Applies `f` to the values in the given signal.
///
/// In the context of command-line option parsing, this is used to chain
/// together the parsing of multiple arguments. See OptionsType for an example.
public func <*><T, U>(f: T -> U, value: ColdSignal<T>) -> ColdSignal<U> {
	return value.map(f)
}

/// Applies the functions in `f` to the values in the given signal.
///
/// In the context of command-line option parsing, this is used to chain
/// together the parsing of multiple arguments. See OptionsType for an example.
public func <*><T, U>(f: ColdSignal<(T -> U)>, value: ColdSignal<T>) -> ColdSignal<U> {
	return f.combineLatestWith(value)
		.map { (f, value) in f(value) }
}

/// Attempts to parse a value for the given option from the given command-line
/// arguments.
///
/// Returns either a signal of one value or an error. If no value was specified
/// on the command line, the option's `defaultValue` is used.
public func <|<T: ArgumentType>(arguments: [String], option: Option<T>) -> ColdSignal<T> {
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

/// Attempts to parse a value for the given nullable option from the given
/// command-line arguments.
///
/// Returns either a signal of one value or an error. If no value was specified
/// on the command line, `nil` is used.
public func <|<T: ArgumentType>(arguments: [String], option: Option<T?>) -> ColdSignal<T?> {
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
