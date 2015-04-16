//
//  Clean.swift
//  Carthage
//
//  Created by Chris Tava on 4/15/15.
//  Copyright (c) 2015 Carthage. All rights reserved.
//

import Foundation
import CarthageKit
import Commandant
import Foundation
import LlamaKit
import ReactiveCocoa

public struct CleanCommand: CommandType {
	public let verb = "clean"
	public let function = "Deletes Carthage directory and Cartfile.resolved file"
		
	public func run(mode: CommandMode) -> Result<(), CommandantError<CarthageError>> {
		return producerWithOptions(CleanOptions.evaluate(mode))
			|> joinMap(.Merge) { options -> SignalProducer<(), CommandError> in
				let formatting = options.colorOptions.formatting
				return options.loadProject()
					|> joinMap(.Merge) { $0.clean() }
					|> on(next: { path in
						carthage.println(formatting.bullets + "Clean complete")
					})
					|> promoteErrors
			}
			|> waitOnCommand
	}
}

public struct CleanOptions: OptionsType {
	public let directoryPath: String
	public let colorOptions: ColorOptions
	
	public static func create(colorOptions: ColorOptions)(directoryPath: String) -> CleanOptions {
		return self(directoryPath: directoryPath,colorOptions: colorOptions)
	}
	
	public static func evaluate(m: CommandMode) -> Result<CleanOptions, CommandantError<CarthageError>> {
		return evaluate(m, useBinariesAddendum: "")
	}
	
	public static func evaluate(m: CommandMode, useBinariesAddendum: String) -> Result<CleanOptions, CommandantError<CarthageError>> {
		return create
			<*> ColorOptions.evaluate(m)
			<*> m <| Option(defaultValue: NSFileManager.defaultManager().currentDirectoryPath, usage: "the directory containing the Carthage project")
	}
	
	/// Attempts to load the project
	public func loadProject() -> SignalProducer<Project, CarthageError> {
		if let directoryURL = NSURL.fileURLWithPath(self.directoryPath, isDirectory: true) {
			let project = Project(directoryURL: directoryURL)
			
			var eventSink = ProjectEventSink(colorOptions: colorOptions)
			project.projectEvents.observe(next: { eventSink.put($0) })
						
			return SignalProducer(value: project)
			
		} else {
			return SignalProducer(error: CarthageError.InvalidArgument(description: "Invalid project path: \(directoryPath)"))
		}
	}
}
