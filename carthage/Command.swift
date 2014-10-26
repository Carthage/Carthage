//
//  Command.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import LlamaKit

/// Represents a Carthage subcommand that can be executed with its own set of
/// arguments.
public protocol CommandType {
	/// The action that users should specify to use this subcommand (e.g.,
	/// `help`).
	var verb: String { get }

	/// Runs this subcommand in the given mode.
	func run(mode: CommandMode) -> Result<()>
}

/// A generator that destructively enumerates a list of command-line arguments.
public final class ArgumentGenerator: GeneratorType {
	typealias Element = String

	private var touchedKeyedArguments = [String: String]()

	/// All flags associated with values that have not yet been read through
	/// a subscripting call.
	internal var untouchedKeyedArguments = [String: String]()

	/// Arguments not associated with any flags.
	private var floatingArguments: GeneratorOf<String>

	/// Initializes the generator from a simple list of command-line arguments.
	public init(_ arguments: [String]) {
		var currentKey: String? = nil
		var permitKeys = true

		var floating = [String]()

		for arg in arguments {
			let keyStartIndex = arg.startIndex.successor().successor()

			if permitKeys && keyStartIndex <= arg.endIndex && arg.substringToIndex(keyStartIndex) == "--" {
				if let key = currentKey {
					untouchedKeyedArguments[key] = ""
					currentKey = nil
				}

				// Check for -- by itself.
				if keyStartIndex == arg.endIndex {
					permitKeys = false
				} else {
					currentKey = arg.substringFromIndex(keyStartIndex)
				}

				continue
			}

			if let key = currentKey {
				untouchedKeyedArguments[key] = arg
				currentKey = nil
			} else {
				floating.append(arg)
			}
		}

		if let key = currentKey {
			untouchedKeyedArguments[key] = ""
		}

		floatingArguments = GeneratorOf(floating.generate())
	}

	/// Yields the next argument _not_ associated with a flag, or nil if all
	/// unassociated arguments have been enumerated already.
	public func next() -> String? {
		return floatingArguments.next()
	}

	/// Returns the value associated with the given flag, or nil if it was not
	/// provided.
	///
	/// Flags provided without a value will result in an empty string.
	public subscript(key: String) -> String? {
		if let value = untouchedKeyedArguments.removeValueForKey(key) {
			touchedKeyedArguments[key] = value
		}

		return touchedKeyedArguments[key]
	}
}

/// Describes the "mode" in which a command should run.
public enum CommandMode {
	/// Options should be parsed from the given command-line arguments.
	case Arguments(ArgumentGenerator)

	/// Each option should record its usage information in an error, for
	/// presentation to the user.
	case Usage
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
///			let outputFilename: String
///			let logName: String
///
///			static func create(verbosity: Int)(outputFilename: String)(logName: String) -> LogOptions {
///				return LogOptions(verbosity: verbosity, outputFilename: outputFilename, logName: logName)
///			}
///
///			static func evaluate(m: CommandMode) -> Result<LogOptions> {
///				return create
///					<*> m <| option(key: "verbose", 0, "the verbosity level with which to read the logs")
///					<*> m <| option(key: "outputFilename", defaultValue: "", "a file to print output to, instead of stdout")
///					<*> m <| option("the log to read")
///			}
///		}
public protocol OptionsType {
	/// Evaluates this set of options in the given mode.
	///
	/// Returns the parsed options, or an `InvalidArgument` error containing
	/// usage information.
	class func evaluate(m: CommandMode) -> Result<Self>
}

/// Describes an option that can be provided on the command line.
public struct Option<T: ArgumentType> {
	/// The key that controls this option. For example, a key of `verbose` would
	/// be used for a `--verbose` option.
	///
	/// If this is nil, this option will not have a corresponding flag, and must
	/// be specified as a plain value at the end of the argument list.
	public let key: String?

	/// The default value for this option. This is the value that will be used
	/// if the option is never explicitly specified on the command line.
	///
	/// If this is nil, this option is always required.
	public let defaultValue: T?

	/// A human-readable string describing the purpose of this option. This will
	/// be shown in help messages.
	public let usage: String
}

extension Option: Printable {
	public var description: String {
		if let key = key {
			return "--\(key)"
		} else {
			return usage
		}
	}
}

/// Constructs an option with the given parameters.
public func option<T: ArgumentType>(key: String? = nil, defaultValue: T? = nil, usage: String) -> Option<T> {
	return Option(key: key, defaultValue: defaultValue, usage: usage)
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

/// Constructs an `InvalidArgument` error that describes how to use `option`.
private func informativeUsageError<T>(option: Option<T>) -> NSError {
	let description = "\(option)\n\t\(option.usage)"
	return CarthageError.InvalidArgument(description: description).error
}

/// Constructs an `InvalidArgument` error that describes how `option` was used
/// incorrectly. `value` should be the invalid value given by the user.
private func invalidUsageError<T>(option: Option<T>, value: String) -> NSError {
	var description: String?
	if value == "" {
		description = "Missing argument for \(option)"
	} else {
		description = "Invalid value for \(option): \(value)"
	}

	return CarthageError.InvalidArgument(description: description!).error
}

/// Combines the text of the two errors, if they're both `InvalidArgument`
/// errors. Otherwise, uses whichever one is not (biased toward the left).
private func combineUsageErrors(left: NSError, right: NSError) -> NSError {
	let combinedError = CarthageError.InvalidArgument(description: "\(left.localizedDescription)\n\(right.localizedDescription)").error

	func isUsageError(error: NSError) -> Bool {
		return error.domain == combinedError.domain && error.code == combinedError.code
	}

	if isUsageError(left) {
		if isUsageError(right) {
			return combinedError
		} else {
			return right
		}
	} else {
		return left
	}
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

/// Applies `f` to the value in the given result.
///
/// In the context of command-line option parsing, this is used to chain
/// together the parsing of multiple arguments. See OptionsType for an example.
public func <*><T, U>(f: T -> U, value: Result<T>) -> Result<U> {
	return value.map(f)
}

/// Applies the function in `f` to the value in the given result.
///
/// In the context of command-line option parsing, this is used to chain
/// together the parsing of multiple arguments. See OptionsType for an example.
public func <*><T, U>(f: Result<(T -> U)>, value: Result<T>) -> Result<U> {
	switch (f, value) {
	case let (.Failure(left), .Failure(right)):
		return failure(combineUsageErrors(left, right))

	case let (.Failure(left), .Success):
		return failure(left)

	case let (.Success, .Failure(right)):
		return failure(right)

	case let (.Success(f), .Success(value)):
		let newValue = f.unbox(value.unbox)
		return success(newValue)
	}
}

/// Evaluates the given option in the given mode.
///
/// If parsing command line arguments, and no value was specified on the command
/// line, the option's `defaultValue` is used.
public func <|<T: ArgumentType>(mode: CommandMode, option: Option<T>) -> Result<T> {
	switch (mode) {
	case let .Arguments(arguments):
		var stringValue: String?
		if let key = option.key {
			stringValue = arguments[key]
		} else {
			stringValue = arguments.next()
		}

		if let stringValue = stringValue {
			if stringValue != "" {
				if let value = T.fromString(stringValue) {
					return success(value)
				}
			}

			return failure(invalidUsageError(option, stringValue))
		} else if let defaultValue = option.defaultValue {
			return success(defaultValue)
		} else {
			// TODO: Flags vs. missing options will need to be differentiated
			// once we support booleans.
			return failure(invalidUsageError(option, ""))
		}

	case .Usage:
		return failure(informativeUsageError(option))
	}
}
