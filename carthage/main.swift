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

let commands = CommandRegistry()
commands.register(BootstrapCommand())
commands.register(BuildCommand())
commands.register(CheckoutCommand())
commands.register(UpdateCommand())

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
	let errorDescription = (error.domain == CarthageErrorDomain ? error.localizedDescription : error.description)
	fputs("\(errorDescription)\n", stderr)
	exit(EXIT_FAILURE)

case .None:
	fputs("Unrecognized command: '\(verb)'. See `carthage help`.\n", stderr)
	exit(EXIT_FAILURE)
}
