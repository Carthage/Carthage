import CarthageKit
import Commandant
import Result
import Foundation
import ReactiveSwift
import Curry

/// Type that encapsulates the configuration and evaluation of the `fetch` subcommand.
public struct FetchCommand: CommandProtocol {
	public struct Options: OptionsProtocol {
		public let colorOptions: ColorOptions
		public let repositoryURL: GitURL

		public static func evaluate(_ mode: CommandMode) -> Result<Options, CommandantError<CarthageError>> {
			return curry(self.init)
				<*> ColorOptions.evaluate(mode)
				<*> mode <| Argument(usage: "the Git repository that should be cloned or fetched")
		}
	}

	public let verb = "fetch"
	public let function = "Clones or fetches a Git repository ahead of time"

	public func run(_ options: Options) -> Result<(), CarthageError> {
		let dependency = Dependency.git(options.repositoryURL)
		var eventSink = ProjectEventSink(colorOptions: options.colorOptions)

		return cloneOrFetch(dependency: dependency, preferHTTPS: true)
			.on(value: { event, _ in
				if let event = event {
					eventSink.put(event)
				}
			})
			.waitOnCommand()
	}
}
