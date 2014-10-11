//
//  main.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit

let commandTypes = [
	CheckoutCommand.self
]

var arguments = Process.arguments
if arguments.count == 0 {
	arguments.append(HelpCommand.verb)
}

let verb = arguments[0]
var command: CommandType? = nil

if let match = find(commandTypes.map { $0.verb }, verb) {
	arguments.removeAtIndex(0)
	command = commandTypes[match](arguments)
} else {
	println("Unrecognized command: \(verb)")
	command = HelpCommand()
}

let result = command!.run()
switch result {
case let .Success(_):
	exit(EXIT_SUCCESS)

case let .Failure(error):
	fputs("Error executing command \(verb): \(error)", stderr)
	exit(EXIT_FAILURE)
}
