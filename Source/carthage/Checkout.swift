import CarthageKit
import Commandant
import Foundation
import Result
import ReactiveSwift
import Curry

/// Type that encapsulates the configuration and evaluation of the `checkout` subcommand.
public struct CheckoutCommand: CommandProtocol {
	public struct Options: OptionsProtocol {
		public let useSSH: Bool
		public let useSubmodules: Bool
		public let colorOptions: ColorOptions
		public let directoryPath: String
		public let dependenciesToCheckout: [String]?

		private init(useSSH: Bool,
		             useSubmodules: Bool,
		             colorOptions: ColorOptions,
		             directoryPath: String,
		             dependenciesToCheckout: [String]?
		) {
			self.useSSH = useSSH
			self.useSubmodules = useSubmodules
			self.colorOptions = colorOptions
			self.directoryPath = directoryPath
			self.dependenciesToCheckout = dependenciesToCheckout
		}

		public static func evaluate(_ mode: CommandMode) -> Result<Options, CommandantError<CarthageError>> {
			return evaluate(mode, dependenciesUsage: "the dependency names to checkout")
		}

		public static func evaluate(_ mode: CommandMode, dependenciesUsage: String) -> Result<Options, CommandantError<CarthageError>> {
			return curry(self.init)
				<*> mode <| Option(key: "use-ssh", defaultValue: false, usage: "use SSH for downloading GitHub repositories")
				<*> mode <| Option(key: "use-submodules", defaultValue: false, usage: "add dependencies as Git submodules")
				<*> ColorOptions.evaluate(mode)
				<*> mode <| Option(key: "project-directory", defaultValue: FileManager.default.currentDirectoryPath, usage: "the directory containing the Carthage project")
				<*> (mode <| Argument(defaultValue: [], usage: dependenciesUsage, usageParameter: "dependency names")).map { $0.isEmpty ? nil : $0 }
		}

		/// Attempts to load the project referenced by the options, and configure it
		/// accordingly.
		public func loadProject() -> SignalProducer<Project, CarthageError> {
			let directoryURL = URL(fileURLWithPath: self.directoryPath, isDirectory: true)
			let project = Project(directoryURL: directoryURL)
			project.preferHTTPS = !self.useSSH
			project.useSubmodules = self.useSubmodules

			var eventSink = ProjectEventSink(colorOptions: colorOptions)
			project.projectEvents.observeValues { eventSink.put($0) }

			return SignalProducer(value: project)
		}
	}

	public let verb = "checkout"
	public let function = "Check out the project's dependencies"

	public func run(_ options: Options) -> Result<(), CarthageError> {
		return self.checkoutWithOptions(options)
			.waitOnCommand()
	}

	/// Checks out dependencies with the given options.
	public func checkoutWithOptions(_ options: Options) -> SignalProducer<(), CarthageError> {
		return options.loadProject()
			.flatMap(.merge) { $0.checkoutResolvedDependencies(options.dependenciesToCheckout, buildOptions: nil) }
	}
}
