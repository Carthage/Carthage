import CarthageKit
import Commandant
import Foundation
import Curry

/// Type that encapsulates the configuration and evaluation of the `cleanup` subcommand.
public struct CleanupCommand: CommandProtocol {
	public let verb = "cleanup"
	public let function = "Remove unneeded files from Carthage directory"

	public struct Options: OptionsProtocol {
		public let directoryPath: String
		public let colorOptions: ColorOptions

		public static func evaluate(_ mode: CommandMode) -> Result<Options, CommandantError<CarthageError>> {
			return curry(self.init)
				<*> mode <| Option(
					key: "project-directory",
					defaultValue: FileManager.default.currentDirectoryPath,
					usage: "the directory containing the Carthage project"
				)
				<*> ColorOptions.evaluate(mode)
		}

		public func loadProject() -> Project {
			let directoryURL = URL(fileURLWithPath: self.directoryPath, isDirectory: true)
			let project = Project(directoryURL: directoryURL)
			var eventSink = ProjectEventSink(colorOptions: colorOptions)
			project.projectEvents.observeValues { eventSink.put($0) }
			return project
		}
	}

	public func run(_ options: Options) -> Result<(), CarthageError> {
		return options.loadProject().removeUnneededItems().waitOnCommand()
	}
}
