//
//  Help.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit

struct HelpCommand: CommandType {
	let verb = "help"

	func run(_ arguments: [String] = []) -> Result<()> {
		println("ohai help")
		return success()
	}
}
