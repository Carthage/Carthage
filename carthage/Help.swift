//
//  Help.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit

public struct HelpCommand: CommandType {
	public let verb = "help"
	public let function = "Display general or command-specific help"

	private let registry: CommandRegistry

	/// Initializes the command to provide help from the given registry of
	/// commands.
	public init(registry: CommandRegistry) {
		self.registry = registry
	}

	public func run(mode: CommandMode) -> Result<()> {
		println("Available commands:\n")

		for command in registry.commands {
			println("  \(command.verb): \(command.function)")
		}

		return success(())
	}
}
