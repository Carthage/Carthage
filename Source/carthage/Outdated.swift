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
import ReactiveSwift

public struct OutdatedCommand: CommandProtocol {
	public struct Options: OptionsProtocol {
		public let useSSH: Bool
		public let isVerbose: Bool
		public let colorOptions: ColorOptions
		public let directoryPath: String
		
		public static func create(_ useSSH: Bool) -> (Bool) -> (ColorOptions) -> (String) -> Options {
			return { isVerbose in { colorOptions in { directoryPath in
				return self.init(useSSH: useSSH, isVerbose: isVerbose, colorOptions: colorOptions, directoryPath: directoryPath)
			} } }
		}
		
		public static func evaluate(_ m: CommandMode) -> Result<Options, CommandantError<CarthageError>> {
			return create
				<*> m <| Option(key: "use-ssh", defaultValue: false, usage: "use SSH for downloading GitHub repositories")
				<*> m <| Option(key: "verbose", defaultValue: false, usage: "include nested dependencies")
				<*> ColorOptions.evaluate(m)
				<*> m <| Option(key: "project-directory", defaultValue: FileManager.default.currentDirectoryPath, usage: "the directory containing the Carthage project")
		}
		
		/// Attempts to load the project referenced by the options, and configure it
		/// accordingly.
		public func loadProject() -> SignalProducer<Project, CarthageError> {
			let directoryURL = URL(fileURLWithPath: self.directoryPath, isDirectory: true)
			let project = Project(directoryURL: directoryURL)
			project.preferHTTPS = !self.useSSH
			
			var eventSink = ProjectEventSink(colorOptions: colorOptions)
			project.projectEvents.observeValues { eventSink.put($0) }
			
			return SignalProducer(value: project)
		}
	}
	
	public let verb = "outdated"
	public let function = "Check for compatible updates to the project's dependencies"

	public func run(_ options: Options) -> Result<(), CarthageError> {
		return options.loadProject()
			.flatMap(.merge) { $0.outdatedDependencies(options.isVerbose) }
			.on(value: { outdatedDependencies in
				let formatting = options.colorOptions.formatting

				if !outdatedDependencies.isEmpty {
					carthage.println(formatting.path("The following dependencies are outdated:"))
					for (currentDependency, updatedDependency) in outdatedDependencies {
						carthage.println(formatting.projectName(currentDependency.project.name) + " \(currentDependency.version) -> \(updatedDependency.version)")
					}
				} else {
					carthage.println("All dependencies are up to date.")
				}
			})
			.waitOnCommand()
	}
}
