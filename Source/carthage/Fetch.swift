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
	public struct Options: OptionsType {
		public let colorOptions: ColorOptions
		public let repositoryURL: GitURL

		static func create(colorOptions: ColorOptions) -> GitURL -> Options {
			return { repositoryURL in
				return self.init(colorOptions: colorOptions, repositoryURL: repositoryURL)
			}
		}

		public static func evaluate(m: CommandMode) -> Result<Options, CommandantError<CarthageError>> {
			return create
				<*> ColorOptions.evaluate(m)
				<*> m <| Argument(usage: "the Git repository that should be cloned or fetched")
		}
	}
	
	public let verb = "fetch"
	public let function = "Clones or fetches a Git repository ahead of time"

	public func run(options: Options) -> Result<(), CarthageError> {
		let project = ProjectIdentifier.Git(options.repositoryURL)
		var eventSink = ProjectEventSink(colorOptions: options.colorOptions)

		return cloneOrFetchProject(project, preferHTTPS: true)
			.on(next: { event, _ in
				eventSink.put(event)
			})
			.waitOnCommand()
	}
}
