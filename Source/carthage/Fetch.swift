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

public struct FetchCommand: CommandType {
	public let verb = "fetch"
	public let function = "Clones or fetches a Git repository ahead of time"

	public func run(mode: CommandMode) -> Result<(), CommandantError<CarthageError>> {
		return producerWithOptions(FetchOptions.evaluate(mode))
			|> flatMap(.Merge) { options -> SignalProducer<(), CommandError> in
				let project = ProjectIdentifier.Git(options.repositoryURL)
				var eventSink = ProjectEventSink(colorOptions: options.colorOptions)

				return cloneOrFetchProject(project, options.verbose, preferHTTPS: true)
					|> on(next: { event, _ in
						eventSink.put(event)
					})
					|> then(.empty)
					|> promoteErrors
			}
			|> waitOnCommand
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
