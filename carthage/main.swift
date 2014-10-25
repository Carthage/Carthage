//
//  main.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

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

let availableCommands: [CommandType] = [
	BuildCommand(),
	HelpCommand(),
	LocateCommand()
]

let commandsByVerb = availableCommands.map { [$0.verb: $0] }.reduce([:], combine: combineDictionaries)
var arguments = Process.arguments

assert(arguments.count >= 1)
arguments.removeAtIndex(0)

let verb = arguments.first ?? HelpCommand().verb
if arguments.count > 0 {
	arguments.removeAtIndex(0)
}

let result = commandsByVerb[verb]?.run(arguments).wait()

switch result {
case .Some(.Success):
	exit(EXIT_SUCCESS)

case let .Some(.Failure(error)):
	fputs("Error executing command \(verb): \(error)", stderr)
	exit(EXIT_FAILURE)

case .None:
	fputs("Unrecognized command: '\(verb)'. See `carthage help`.", stderr)
	exit(EXIT_FAILURE)
}
