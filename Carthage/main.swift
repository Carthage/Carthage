//
//  main.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation

let helpCommand = HelpCommand()
let commands = [
	helpCommand
]

var arguments = Process.arguments
if arguments.count == 0 {
	arguments.append(helpCommand.verb)
}

let verb = arguments[0]
if let match = find(commands.map { $0.verb }, verb) {
	arguments.removeAtIndex(0)
	commands[match].run(arguments)
} else {
	println("Unrecognized command: \(verb)")
	helpCommand.run([])
}
