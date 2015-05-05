//
//  Bootstrap.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-15.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Commandant
import Foundation
import Result
import ReactiveCocoa

public struct BootstrapCommand: CommandType {
	public let verb = "bootstrap"
	public let function = "Check out and build the project's dependencies"

	public func run(mode: CommandMode) -> Result<(), CommandantError<CarthageError>> {
		// Reuse UpdateOptions, since all `bootstrap` flags should correspond to
		// `update` flags.
		return producerWithOptions(UpdateOptions.evaluate(mode))
			|> flatMap(.Merge) { options -> SignalProducer<(), CommandError> in
				return options.loadProject()
					|> flatMap(.Merge) { project -> SignalProducer<(), CarthageError> in
						if NSFileManager.defaultManager().fileExistsAtPath(project.resolvedCartfileURL.path!) {
							return project.checkoutResolvedDependencies()
						} else {
							let formatting = options.checkoutOptions.colorOptions.formatting
							carthage.println(formatting.bullets + "No Cartfile.resolved found, updating dependencies")
							return project.updateDependencies()
						}
					}
					|> then(options.buildProducer)
					|> promoteErrors
			}
			|> waitOnCommand
	}
}
