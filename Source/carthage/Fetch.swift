//
//  Fetch.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-12-24.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Commandant
import Result
import Foundation
import ReactiveCocoa
import ReactiveTask

public struct FetchCommand: CommandType {
	public let verb = "fetch"
	public let function = "Clones or fetches a Git repository ahead of time"

	public func run(mode: CommandMode) -> Result<(), CommandantError<CarthageError>> {
		return producerWithOptions(FetchOptions.evaluate(mode))
			|> flatMap(.Merge) { options in
				return self.fetchWithOptions(options)
				|> promoteErrors
			}
			|> waitOnCommand
	}
	
	private func fetchWithOptions(options: FetchOptions) -> SignalProducer<(), CarthageError> {
		return openLoggingHandle(options.verbose, "git")
			|> flatMap(.Merge) { (fileHandle, temporaryURL) -> SignalProducer<(), CarthageError> in
				let formatting = options.colorOptions.formatting
				let stderrHandle = NSFileHandle.fileHandleWithStandardError()

				let project = ProjectIdentifier.Git(options.repositoryURL)
				var eventSink = ProjectEventSink(colorOptions: options.colorOptions)
				
				return cloneOrFetchProject(project, preferHTTPS: true)
					|> on(started: {
						if let temporaryURL = temporaryURL {
							carthage.println(formatting.bullets + "git output can be found in " + formatting.path(string: temporaryURL.path!))
						}
						}, next: { event, _ in
							switch event {
							case let .StandardOutput(data):
								fileHandle.writeData(data)
								
							case let .StandardError(data):
								fileHandle.writeData(data)
								stderrHandle.writeData(data)
							}

							eventSink.put(event)
					})
					|> then(.empty)
		}
	}
}

private struct FetchOptions: OptionsType {
	let colorOptions: ColorOptions
	let repositoryURL: GitURL
	let verbose: Bool

	static func create(colorOptions: ColorOptions)(repositoryURL: GitURL)(verbose: Bool) -> FetchOptions {
		return self(colorOptions: colorOptions, repositoryURL: repositoryURL, verbose: verbose)
	}

	static func evaluate(m: CommandMode) -> Result<FetchOptions, CommandantError<CarthageError>> {
		return create
			<*> ColorOptions.evaluate(m)
			<*> m <| Option(usage: "the Git repository that should be cloned or fetched")
			<*> m <| Option(key: "verbose", defaultValue: false, usage: "print xcodebuild output inline (ignored if --no-build option is present)")
	}
}
