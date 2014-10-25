//
//  Help.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit

/// Offers general or subcommand-specific help.
public struct HelpCommand: CommandType {
	public let verb = "help"

	public func run(arguments: [String]) -> Result<()> {
		println("ohai help")
		return success(())
	}
}
