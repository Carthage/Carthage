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

	private let registry: CommandRegistry

	/// Initializes the command to provide help from the given registry of
	/// commands.
	public init(registry: CommandRegistry) {
		self.registry = registry
	}

	public func run(mode: CommandMode) -> Result<()> {
		println("Available commands:\n")

		for command in registry.commands {
			println("\t\(command.verb)")
		}

		return success(())
	}
}
