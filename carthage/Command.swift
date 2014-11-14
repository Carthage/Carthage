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

	/// A human-readable, high-level description of what this command is used
	/// for.
	var function: String { get }

	/// Runs this subcommand in the given mode.
	func run(mode: CommandMode) -> Result<()>
}

/// Maintains the list of commands available to run.
public final class CommandRegistry {
	private var commandsByVerb: [String: CommandType] = [:]

	/// All available commands.
	public var commands: [CommandType] {
		return sorted(commandsByVerb.values) { return $0.verb < $1.verb }
	}

	public init() {}

	/// Registers the given command, making it available to run.
	///
	/// If another command was already registered with the same `verb`, it will
	/// be overwritten.
	public func register(command: CommandType) {
		commandsByVerb[command.verb] = command
	}

	/// Runs the command corresponding to the given verb, passing it the given
	/// arguments.
	///
	/// Returns the results of the execution, or nil if no such command exists.
	public func runCommand(verb: String, arguments: [String]) -> Result<()>? {
		return self[verb]?.run(.Arguments(ArgumentParser(arguments)))
	}

	/// Returns the command matching the given verb, or nil if no such command
	/// is registered.
	public subscript(verb: String) -> CommandType? {
		return commandsByVerb[verb]
	}
}

/// Represents an argument passed on the command line.
private enum RawArgument: Equatable {
	/// A key corresponding to an option (e.g., `verbose` for `--verbose`).
	case Key(String)

	/// A value, either associated with an option or passed as a positional
	/// argument.
	case Value(String)
}

private func ==(lhs: RawArgument, rhs: RawArgument) -> Bool {
	switch (lhs, rhs) {
	case let (.Key(left), .Key(right)):
		return left == right

	case let (.Value(left), .Value(right)):
		return left == right

	default:
		return false
	}
}

extension RawArgument: Printable {
	private var description: String {
		switch self {
		case let .Key(key):
			return "--\(key)"

		case let .Value(value):
			return "\"\(value)\""
		}
	}
}

/// Constructs an `InvalidArgument` error that indicates a missing value for
/// the argument by the given name.
private func missingArgumentError(argumentName: String) -> NSError {
	let description = "Missing argument for \(argumentName)"
	return CarthageError.InvalidArgument(description: description).error
}

/// Constructs an `InvalidArgument` error that describes how to use the
/// option, with the given example of key (and value, if applicable) usage.
private func informativeUsageError<T>(keyValueExample: String, option: Option<T>) -> NSError {
	var description = ""

	if option.defaultValue != nil {
		description += "["
	}

	description += keyValueExample

	if option.defaultValue != nil {
		description += "]"
	}

	description += "\n\t\(option.usage)"
	return CarthageError.InvalidArgument(description: description).error
}

/// Constructs an `InvalidArgument` error that describes how to use the
/// option.
private func informativeUsageError<T: ArgumentType>(option: Option<T>) -> NSError {
	var example = ""

	if let key = option.key {
		example += "--\(key) "
	}

	example += "(\(T.name))"

	return informativeUsageError(example, option)
}

/// Constructs an `InvalidArgument` error that describes how to use the
/// given boolean option.
private func informativeUsageError(option: Option<Bool>) -> NSError {
	precondition(option.key != nil)

	return informativeUsageError("--(no-)\(option.key!)", option)
}

/// Destructively parses a list of command-line arguments.
public final class ArgumentParser {
	/// The remaining arguments to be extracted, in their raw form.
	private var rawArguments: [RawArgument] = []

	/// Initializes the generator from a simple list of command-line arguments.
	public init(_ arguments: [String]) {
		var permitKeys = true

		for arg in arguments {
			// Check whether this is a keyed argument.
			if permitKeys && arg.hasPrefix("--") {
				// Check for -- by itself, which should terminate the keyed
				// argument list.
				let keyStartIndex = arg.startIndex.successor().successor()
				if keyStartIndex == arg.endIndex {
					permitKeys = false
				} else {
					let key = arg.substringFromIndex(keyStartIndex)
					rawArguments.append(.Key(key))
				}
			} else {
				rawArguments.append(.Value(arg))
			}
		}
	}

	/// Returns whether the given key was enabled or disabled, or nil if it
	/// was not given at all.
	///
	/// If the key is found, it is then removed from the list of arguments
	/// remaining to be parsed.
	private func consumeBooleanKey(key: String) -> Bool? {
		let oldArguments = rawArguments
		rawArguments.removeAll()

		var result: Bool?
		for arg in oldArguments {
			if arg == .Key(key) {
				result = true
			} else if arg == .Key("no-\(key)") {
				result = false
			} else {
				rawArguments.append(arg)
			}
		}

		return result
	}

	/// Returns the value associated with the given flag, or nil if the flag was
	/// not specified. If the key is presented, but no value was given, an error
	/// is returned.
	///
	/// If a value is found, the key and the value are both removed from the
	/// list of arguments remaining to be parsed.
	private func consumeValueForKey(key: String) -> Result<String?> {
		let oldArguments = rawArguments
		rawArguments.removeAll()

		var foundValue: String?
		argumentLoop: for var index = 0; index < oldArguments.count; index++ {
			let arg = oldArguments[index]

			if arg == .Key(key) {
				if ++index < oldArguments.count {
					switch oldArguments[index] {
					case let .Value(value):
						foundValue = value
						continue argumentLoop

					default:
						break
					}
				}
	
				return failure(missingArgumentError("--\(key)"))
			} else {
				rawArguments.append(arg)
			}
		}

		return success(foundValue)
	}

	/// Returns the next positional argument that hasn't yet been returned, or
	/// nil if there are no more positional arguments.
	private func consumePositionalArgument() -> String? {
		for var index = 0; index < rawArguments.count; index++ {
			switch rawArguments[index] {
			case let .Value(value):
				rawArguments.removeAtIndex(index)
				return value

			default:
				break
			}
		}

		return nil
	}
}

/// Describes the "mode" in which a command should run.
public enum CommandMode {
	/// Options should be parsed from the given command-line arguments.
	case Arguments(ArgumentParser)

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
///					<*> m <| Option(key: "verbose", defaultValue: 0, usage: "the verbosity level with which to read the logs")
///					<*> m <| Option(key: "outputFilename", defaultValue: "", usage: "a file to print output to, instead of stdout")
///					<*> m <| Option(usage: "the log to read")
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
public struct Option<T> {
	/// The key that controls this option. For example, a key of `verbose` would
	/// be used for a `--verbose` option.
	///
	/// If this is nil, this option will not have a corresponding flag, and must
	/// be specified as a plain value at the end of the argument list.
	///
	/// This must be non-nil for a boolean option.
	public let key: String?

	/// The default value for this option. This is the value that will be used
	/// if the option is never explicitly specified on the command line.
	///
	/// If this is nil, this option is always required.
	public let defaultValue: T?

	/// A human-readable string describing the purpose of this option. This will
	/// be shown in help messages.
	public let usage: String

	public init(key: String? = nil, defaultValue: T? = nil, usage: String) {
		self.key = key
		self.defaultValue = defaultValue
		self.usage = usage
	}

	/// Constructs an `InvalidArgument` error that describes how the option was
	/// used incorrectly. `value` should be the invalid value given by the user.
	private func invalidUsageError(value: String) -> NSError {
		let description = "Invalid value for '\(self)': \(value)"
		return CarthageError.InvalidArgument(description: description).error
	}
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

/// Represents a value that can be converted from a command-line argument.
public protocol ArgumentType {
	/// A human-readable name for this type.
	class var name: String { get }

	/// Attempts to parse a value from the given command-line argument.
	class func fromString(string: String) -> Self?
}

extension Int: ArgumentType {
	public static let name = "integer"

	public static func fromString(string: String) -> Int? {
		return string.toInt()
	}
}

extension String: ArgumentType {
	public static let name = "string"

	public static func fromString(string: String) -> String? {
		return string
	}
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
	switch mode {
	case let .Arguments(arguments):
		var stringValue: String?
		if let key = option.key {
			switch arguments.consumeValueForKey(key) {
			case let .Success(value):
				stringValue = value.unbox

			case let .Failure(error):
				return failure(error)
			}
		} else {
			stringValue = arguments.consumePositionalArgument()
		}

		if let stringValue = stringValue {
			if let value = T.fromString(stringValue) {
				return success(value)
			}

			return failure(option.invalidUsageError(stringValue))
		} else if let defaultValue = option.defaultValue {
			return success(defaultValue)
		} else {
			return failure(missingArgumentError(option.description))
		}

	case .Usage:
		return failure(informativeUsageError(option))
	}
}

/// Evaluates the given boolean option in the given mode.
///
/// If parsing command line arguments, and no value was specified on the command
/// line, the option's `defaultValue` is used.
public func <|(mode: CommandMode, option: Option<Bool>) -> Result<Bool> {
	precondition(option.key != nil)

	switch mode {
	case let .Arguments(arguments):
		if let value = arguments.consumeBooleanKey(option.key!) {
			return success(value)
		} else if let defaultValue = option.defaultValue {
			return success(defaultValue)
		} else {
			return failure(missingArgumentError(option.description))
		}

	case .Usage:
		return failure(informativeUsageError(option))
	}
}
