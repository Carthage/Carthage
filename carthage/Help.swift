//
//  Help.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Commandant
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
		return HelpOptions.evaluate(mode)
			.flatMap { options in
				if let verb = options.verb {
					if let command = self.registry[verb] {
						println(command.function)
						println()
						return command.run(.Usage)
					} else {
						fputs("Unrecognized command: '\(verb)'\n", stderr)
					}
				}

				println("Available commands:\n")

				let maxVerbLength = maxElement(self.registry.commands.map { countElements($0.verb) })

				for command in self.registry.commands {
					let padding = Repeat<Character>(count: maxVerbLength - countElements(command.verb), repeatedValue: " ")

					var formattedVerb = command.verb
					formattedVerb.extend(padding)

					println("   \(formattedVerb)   \(command.function)")
				}

				return success(())
			}
	}
}

private struct HelpOptions: OptionsType {
	let verb: String?

	static func create(verb: String) -> HelpOptions {
		return self(verb: (verb == "" ? nil : verb))
	}

	static func evaluate(m: CommandMode) -> Result<HelpOptions> {
		return create
			<*> m <| Option(defaultValue: "", usage: "the command to display help for")
	}
}
