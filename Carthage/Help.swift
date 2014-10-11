//
//  Help.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation

class HelpCommand: Command {
	let verb = "help"

	func run(arguments: [String]) {
		println("ohai help")
	}
}
