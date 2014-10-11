//
//  main.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit

let commands = [
	HelpCommand.verb: HelpCommand.self
]

var arguments = Process.arguments

let verb = arguments.first ?? HelpCommand.verb
let args = arguments.count > 0 ? Array(dropFirst(arguments)) : []

let result = commands[verb]?(args).run()

switch result {
case .Some(.Success):
	exit(EXIT_SUCCESS)
	
case let .Some(.Failure(error)):
	fputs("Error executing command \(verb): \(error)", stderr)
	exit(EXIT_FAILURE)
	
case .None:
	println("Unrecognized command: '\(verb)'. See `carthage --help'.'")
	exit(EXIT_FAILURE)
}
