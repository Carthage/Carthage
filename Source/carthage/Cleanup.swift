import CarthageKit
import Commandant
import Foundation
import Result
import Curry
import ReactiveSwift

/// Type that encapsulates the configuration and evaluation of the `version` subcommand.
public struct CleanupCommand: CommandProtocol {
	public let verb = "cleanup"
	public let function = "Remove unneeded files from Carthage directory"

	public struct Options: OptionsProtocol {
		public let directoryPath: String

		public static func evaluate(_ mode: CommandMode) -> Result<Options, CommandantError<CarthageError>> {
			return curry(self.init)
				<*> mode <| Option(
					key: "project-directory",
					defaultValue: FileManager.default.currentDirectoryPath,
					usage: "the directory containing the Carthage project"
			)
		}

		public func loadProject() -> Project {
			let directoryURL = URL(fileURLWithPath: self.directoryPath, isDirectory: true)
			return Project(directoryURL: directoryURL)
		}
	}

	public func run(_ options: Options) -> Result<(), CarthageError> {
		return options.loadProject().removeUnneededItems().waitOnCommand()
	}
}
