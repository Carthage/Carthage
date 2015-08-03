//
//  Checkout.swift
//  Carthage
//
//  Created by Alan Rogers on 11/10/2014.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Commandant
import Foundation
import Result
import ReactiveCocoa

public struct CheckoutCommand: CommandType {
	public let verb = "checkout"
	public let function = "Check out the project's dependencies"

	public func run(mode: CommandMode) -> Result<(), CommandantError<CarthageError>> {
		return producerWithOptions(CheckoutOptions.evaluate(mode))
			|> flatMap(.Merge) { options in
				return self.checkoutWithOptions(options)
					|> promoteErrors
			}
			|> waitOnCommand
	}

	/// Checks out dependencies with the given options.
	public func checkoutWithOptions(options: CheckoutOptions) -> SignalProducer<(), CarthageError> {
		return openLoggingHandle(options.verbose, "git")
			|> flatMap(.Merge) { (fileHandle, temporaryURL) -> SignalProducer<(), CarthageError> in
				let formatting = options.colorOptions.formatting
				
				return options.loadProject(fileHandle)
					|> on(started: {
						if let temporaryURL = temporaryURL {
							carthage.println(formatting.bullets + "git output can be found in " + formatting.path(string: temporaryURL.path!))
						}
					})
					|> flatMap(.Merge) { $0.checkoutResolvedDependencies(fileHandle) }
		}
	}
}

public struct CheckoutOptions: OptionsType {
	public let directoryPath: String
	public let useSSH: Bool
	public let useSubmodules: Bool
	public let useBinaries: Bool
	public let verbose: Bool
	public let colorOptions: ColorOptions

	public static func create(useSSH: Bool)(useSubmodules: Bool)(useBinaries: Bool)(verbose: Bool)(colorOptions: ColorOptions)(directoryPath: String) -> CheckoutOptions {
		return self(directoryPath: directoryPath, useSSH: useSSH, useSubmodules: useSubmodules, useBinaries: useBinaries, verbose: verbose, colorOptions: colorOptions)
	}

	public static func evaluate(m: CommandMode) -> Result<CheckoutOptions, CommandantError<CarthageError>> {
		return evaluate(m, useBinariesAddendum: "")
	}

	public static func evaluate(m: CommandMode, useBinariesAddendum: String) -> Result<CheckoutOptions, CommandantError<CarthageError>> {
		return create
			<*> m <| Option(key: "use-ssh", defaultValue: false, usage: "use SSH for downloading GitHub repositories")
			<*> m <| Option(key: "use-submodules", defaultValue: false, usage: "add dependencies as Git submodules")
			<*> m <| Option(key: "use-binaries", defaultValue: true, usage: "check out dependency repositories even when prebuilt frameworks exist" + useBinariesAddendum)
			<*> m <| Option(key: "verbose", defaultValue: false, usage: "print out more details")
			<*> ColorOptions.evaluate(m)
			<*> m <| Option(defaultValue: NSFileManager.defaultManager().currentDirectoryPath, usage: "the directory containing the Carthage project")
	}

	/// Attempts to load the project referenced by the options, and configure it
	/// accordingly.
	public func loadProject(gitFileHandle: NSFileHandle) -> SignalProducer<Project, CarthageError> {
		if let directoryURL = NSURL.fileURLWithPath(self.directoryPath, isDirectory: true) {
			let project = Project(directoryURL: directoryURL)
			project.preferHTTPS = !self.useSSH
			project.useSubmodules = self.useSubmodules
			project.useBinaries = self.useBinaries

			var eventSink = ProjectEventSink(colorOptions: colorOptions)
			project.projectEvents.observe(next: { eventSink.put($0) })

			return project.migrateIfNecessary(self, gitFileHandle: gitFileHandle)
				|> on(next: carthage.println)
				|> then(SignalProducer(value: project))
		} else {
			return SignalProducer(error: CarthageError.InvalidArgument(description: "Invalid project path: \(directoryPath)"))
		}
	}
}
