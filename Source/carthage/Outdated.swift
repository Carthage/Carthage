//
//  Outdated.swift
//  Carthage
//
//  Created by Matt Prowse on 2015-06-24
//  Copyright (c) 2015 Carthage. All rights reserved.
//

import CarthageKit
import Commandant
import Foundation
import Result
import ReactiveCocoa

public struct OutdatedCommand: CommandType {
	public let verb = "outdated"
	public let function = "Check for updates to the project's dependencies"

	public func run(mode: CommandMode) -> Result<(), CommandantError<CarthageError>> {
		return producerWithOptions(OutdatedOptions.evaluate(mode))
			.flatMap(.Merge) { options in
				return options.loadProject()
					.flatMap(.Merge) { $0.outdatedDependencies(options.verbose) }
					.on(next: { outdatedDependencies in
						let formatting = options.colorOptions.formatting

						if outdatedDependencies.count > 0 {
							carthage.println(formatting.bullets + formatting.path(string: "The following dependencies are outdated:"))
							for dependency in outdatedDependencies {
								carthage.println(formatting.bullets + formatting.projectName(string: dependency.project.name) + " \(dependency.version)")
							}
						} else {
							carthage.println(formatting.bullets + "All dependencies are up to date.")
						}
					})
					.promoteErrors()
			}
			.waitOnCommand()
	}
}

public struct OutdatedOptions: OptionsType {
	public let directoryPath: String
	public let useSSH: Bool
	public let useSubmodules: Bool
	public let verbose: Bool
	public let colorOptions: ColorOptions

	/// The checkout options corresponding to these options.
	public var checkoutOptions: CheckoutOptions {
		return CheckoutOptions(directoryPath: directoryPath, useSSH: useSSH, useSubmodules: useSubmodules, useBinaries: true, colorOptions: colorOptions)
	}

	public static func create(useSSH: Bool)(useSubmodules: Bool)(verbose: Bool)(colorOptions: ColorOptions)(directoryPath: String) -> OutdatedOptions {
		return self.init(directoryPath: directoryPath, useSSH: useSSH, useSubmodules: useSubmodules, verbose: verbose, colorOptions: colorOptions)
	}

	public static func evaluate(m: CommandMode) -> Result<OutdatedOptions, CommandantError<CarthageError>> {
		return create
			<*> m <| Option(key: "use-ssh", defaultValue: false, usage: "use SSH for downloading GitHub repositories")
			<*> m <| Option(key: "use-submodules", defaultValue: false, usage: "add dependencies as Git submodules")
			<*> m <| Option(key: "verbose", defaultValue: false, usage: "include transient dependencies in addition to explicit depencies")
			<*> ColorOptions.evaluate(m)
			<*> m <| Option(defaultValue: NSFileManager.defaultManager().currentDirectoryPath, usage: "the directory containing the Carthage project")
	}

	/// Attempts to load the project referenced by the options, and configure it
	/// accordingly.
	public func loadProject() -> SignalProducer<Project, CarthageError> {
		return checkoutOptions.loadProject()
	}
}
