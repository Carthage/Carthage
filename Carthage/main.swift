//
//  main.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation

let commands : [Command] = [
	HelpCommand(),
	CheckoutCommand(),
]

var arguments = Process.arguments
if arguments.count == 0 {
	arguments.append("help")
}

let verb = arguments[0]

// We should always find a match, since we default to `help`.
let match = find(commands.map { $0.verb }, verb)!

arguments.removeAtIndex(0)
commands[match].run(arguments)
