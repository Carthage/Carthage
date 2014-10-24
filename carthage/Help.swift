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
	static let verb = "help"

	init() {
	}

	init<C: CollectionType where C.Generator.Element == String>(_ arguments: C) {
	}

	func run() -> Result<()> {
		println("ohai help")
		return success()
	}
}
