import CarthageKit
import Commandant
import Foundation
import Result
import ReactiveSwift
import Curry

/// Type that encapsulates the configuration and evaluation of the `outdated` subcommand.
public struct OutdatedCommand: CommandProtocol {
	enum UpdateAvailabilityAndApplicability: String {
		case updatesAvailableAllApplicable =
		"Will be updated to the newest version."
		case updatesAvailableSomeApplicable =
		"Will be updated, but not to the newest version because of the specified version in Cartfile."
		case updatesAvailableNoneApplicable =
		"Will not be updated because of the specified version in Cartfile."
		case noUpdatesAvailable =
		"Will not be updated: no updates available."

		init(currentVersion current: PinnedVersion, applicableVersion applicable: PinnedVersion, latestVersion latest: PinnedVersion) {
			switch (current, applicable, latest) {
			case (current, applicable, latest) where current != latest && applicable == latest:
				self = .updatesAvailableAllApplicable
			case (current, applicable, latest) where current != applicable && applicable != latest:
				self = .updatesAvailableSomeApplicable
			case (current, applicable, latest) where current != latest && current == applicable:
				self = .updatesAvailableNoneApplicable
			default:
				self = .noUpdatesAvailable
			}
		}
	}

	public struct Options: OptionsProtocol {
		public let useSSH: Bool
		public let isVerbose: Bool
		public let outputXcodeWarnings: Bool
		public let colorOptions: ColorOptions
		public let directoryPath: String

		public static func evaluate(_ mode: CommandMode) -> Result<Options, CommandantError<CarthageError>> {
			let projectDirectoryOption = Option(
				key: "project-directory",
				defaultValue: FileManager.default.currentDirectoryPath,
				usage: "the directory containing the Carthage project"
			)

			return curry(self.init)
				<*> mode <| Option(key: "use-ssh", defaultValue: false, usage: "use SSH for downloading GitHub repositories")
				<*> mode <| Option(key: "verbose", defaultValue: false, usage: "include nested dependencies")
				<*> mode <| Option(key: "xcode-warnings", defaultValue: false, usage: "output Xcode compatible warning messages")
				<*> ColorOptions.evaluate(mode)
				<*> mode <| projectDirectoryOption
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

					for (project, current, applicable, latest) in outdatedDependencies {
						if options.outputXcodeWarnings {
							carthage.println("warning: \(formatting.projectName(project.name)) is out of date (\(current) -> \(applicable)) (Latest: \(latest))")
						} else {
							let availability = UpdateAvailabilityAndApplicability(currentVersion: current, applicableVersion: applicable, latestVersion: latest)
							let style = formatting[availability]
							let versionSummary = "\(style(current.description)) -> \(style(applicable.description)) (Latest: \(latest))"
							carthage.println(formatting.projectName(project.name) + " " + versionSummary)
						}
					}
					formatting.legendForOutdatedCommand.map(carthage.println)
				} else {
					carthage.println("All dependencies are up to date.")
				}
			})
			.waitOnCommand()
	}
}
