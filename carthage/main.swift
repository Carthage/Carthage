//
//  main.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import LlamaKit
import ReactiveCocoa

// Hopefully this will be built into the standard library someday.
func combineDictionaries<K, V>(lhs: [K: V], rhs: [K: V]) -> [K: V] {
	var result = lhs
	for (key, value) in rhs {
		result.updateValue(value, forKey: key)
	}
	return result
}

let commands = CommandRegistry()
commands.register(BuildCommand())
commands.register(LocateCommand())

let helpCommand = HelpCommand(registry: commands)
commands.register(helpCommand)

var arguments = Process.arguments

// Remove the executable name.
assert(arguments.count >= 1)
arguments.removeAtIndex(0)

let verb = arguments.first ?? helpCommand.verb
if arguments.count > 0 {
	// Remove the command name.
	arguments.removeAtIndex(0)
}

switch commands.runCommand(verb, arguments: arguments) {
case .Some(.Success):
	exit(EXIT_SUCCESS)

case let .Some(.Failure(error)):
	// TODO: This is super dumb.
	let comparisonError = CarthageError.InvalidArgument(description: "").error

	if error.domain == comparisonError.domain && error.code == comparisonError.code {
		fputs("\(error.localizedDescription)\n", stderr)
	} else {
		fputs("Error executing command \(verb): \(error)\n", stderr)
	}

	exit(EXIT_FAILURE)

case .None:
	fputs("Unrecognized command: '\(verb)'. See `carthage help`.\n", stderr)
	exit(EXIT_FAILURE)
}
