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

	private let printer: Printer
	private let fileManager: FileManager

	public init(printer: Printer, fileManager: FileManager) {
		self.printer = printer
		self.fileManager = fileManager
	}

	public func run(options: UpdateCommand.Options) -> Result<(), CarthageError> {
		// Reuse UpdateOptions, since all `bootstrap` flags should correspond to
		// `update` flags.
		return options.loadProject()
			.flatMap(.Merge) { project -> SignalProducer<(), CarthageError> in
				if !self.fileManager.fileExistsAtPath(project.resolvedCartfileURL.path!) {
					let formatting = options.checkoutOptions.colorOptions.formatting
					self.printer.println(formatting.bullets + "No Cartfile.resolved found, updating dependencies")
					return project.updateDependencies(shouldCheckout: options.checkoutAfterUpdate)
				}

				if options.checkoutAfterUpdate {
					return project.checkoutResolvedDependencies(options.dependenciesToUpdate)
				} else {
					return .empty
				}
			}
			.then(options.buildProducer)
			.waitOnCommand()
	}
}
