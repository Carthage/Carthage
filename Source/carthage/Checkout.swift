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
	public typealias Options = CheckoutOptions
	public let verb = "checkout"
	public let function = "Check out the project's dependencies"

	public func run(options: CheckoutOptions) -> Result<(), CarthageError> {
		return self.checkoutWithOptions(options)
			.waitOnCommand()
	}

	/// Checks out dependencies with the given options.
	public func checkoutWithOptions(options: CheckoutOptions) -> SignalProducer<(), CarthageError> {
		return options.loadProject()
			.flatMap(.Merge) { $0.checkoutResolvedDependencies() }
	}
}

public struct CheckoutOptions: OptionsType {
	public let useSSH: Bool
	public let useSubmodules: Bool
	public let useBinaries: Bool
	public let colorOptions: ColorOptions
	public let directoryPath: String

	public static func create(useSSH: Bool) -> Bool -> Bool -> ColorOptions -> String -> CheckoutOptions {
		return { useSubmodules in { useBinaries in { colorOptions in { directoryPath in
			// Disable binary downloads when using submodules.
			// See https://github.com/Carthage/Carthage/issues/419.
			let shouldUseBinaries = useSubmodules ? false : useBinaries
			return self.init(useSSH: useSSH, useSubmodules: useSubmodules, useBinaries: shouldUseBinaries, colorOptions: colorOptions, directoryPath: directoryPath)
		} } } }
	}

	public static func evaluate(m: CommandMode) -> Result<CheckoutOptions, CommandantError<CarthageError>> {
		return evaluate(m, useBinariesAddendum: "")
	}

	public static func evaluate(m: CommandMode, useBinariesAddendum: String) -> Result<CheckoutOptions, CommandantError<CarthageError>> {
		return create
			<*> m <| Option(key: "use-ssh", defaultValue: false, usage: "use SSH for downloading GitHub repositories")
			<*> m <| Option(key: "use-submodules", defaultValue: false, usage: "add dependencies as Git submodules")
			<*> m <| Option(key: "use-binaries", defaultValue: true, usage: "check out dependency repositories even when prebuilt frameworks exist, disabled if --use-submodules option is present" + useBinariesAddendum)
			<*> ColorOptions.evaluate(m)
			<*> m <| Option(key: "project-directory", defaultValue: NSFileManager.defaultManager().currentDirectoryPath, usage: "the directory containing the Carthage project")
	}

	/// Attempts to load the project referenced by the options, and configure it
	/// accordingly.
	public func loadProject() -> SignalProducer<Project, CarthageError> {
		let directoryURL = NSURL.fileURLWithPath(self.directoryPath, isDirectory: true)
		let project = Project(directoryURL: directoryURL)
		project.preferHTTPS = !self.useSSH
		project.useSubmodules = self.useSubmodules
		project.useBinaries = self.useBinaries

		var eventSink = ProjectEventSink(colorOptions: colorOptions)
		project.projectEvents.observeNext { eventSink.put($0) }

		return project.migrateIfNecessary(colorOptions)
			.on(next: carthage.println)
			.then(SignalProducer(value: project))
	}
}
