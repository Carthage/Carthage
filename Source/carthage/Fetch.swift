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
import ReactiveSwift

public struct FetchCommand: CommandProtocol {
	public struct Options: OptionsProtocol {
		public let colorOptions: ColorOptions
		public let repositoryURL: GitURL

		static func create(_ colorOptions: ColorOptions) -> (GitURL) -> Options {
			return { repositoryURL in
				return self.init(colorOptions: colorOptions, repositoryURL: repositoryURL)
			}
		}

		public static func evaluate(_ m: CommandMode) -> Result<Options, CommandantError<CarthageError>> {
			return create
				<*> ColorOptions.evaluate(m)
				<*> m <| Argument(usage: "the Git repository that should be cloned or fetched")
		}
	}
	
	public let verb = "fetch"
	public let function = "Clones or fetches a Git repository ahead of time"

	public func run(_ options: Options) -> Result<(), CarthageError> {
		let project = ProjectIdentifier.git(options.repositoryURL)
		var eventSink = ProjectEventSink(colorOptions: options.colorOptions)

		return cloneOrFetchProject(project, preferHTTPS: true)
			.on(value: { event, _ in
				if let event = event {
					eventSink.put(event)
				}
			})
			.waitOnCommand()
	}
}
