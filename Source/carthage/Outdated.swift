import CarthageKit
import Commandant
import Foundation
import ReactiveSwift
import Curry

/// Type that encapsulates the configuration and evaluation of the `outdated` subcommand.
public struct OutdatedCommand: CommandProtocol {
	enum UpdateType {
		case newest
		case newer
		case ineligible

		init?(currentVersion current: PinnedVersion, applicableVersion applicable: PinnedVersion, latestVersion latest: PinnedVersion) {
			guard current != latest else { return nil }
			if applicable == latest {
				self = .newest
			} else if current != applicable {
				self = .newer
			} else {
				self = .ineligible
			}
		}

		var explanation: String {
			switch self {
			case .newest:
				return "Will be updated to the newest version."
			case .newer:
				return "Will be updated, but not to the newest version because of the specified version in Cartfile."
			case .ineligible:
				return "Will not be updated because of the specified version in Cartfile."
			}
		}

		static var legend: String {
			let header = "Legend — <color> • «what happens when you run `carthage update`»:\n"
			return header + [UpdateType.newest, .newer, .ineligible].map {
				let (color, explanation) = ($0.color, $0.explanation)
				let tabs = String(
					repeating: "\t",
					count: color == .yellow || color == .magenta ? 1 : 2
				)
				return "<" + String(describing: color) + ">" + tabs + "• " + explanation
			}.joined(separator: "\n")
		}
	}

	public struct Options: OptionsProtocol {
		public let useSSH: Bool
		public let isVerbose: Bool
		public let outputXcodeWarnings: Bool
		public let colorOptions: ColorOptions
		public let directoryPath: String
		public let useNetrc: Bool

		public static func evaluate(_ mode: CommandMode) -> Result<Options, CommandantError<CarthageError>> {
			let projectDirectoryOption = Option(
				key: "project-directory",
				defaultValue: FileManager.default.currentDirectoryPath,
				usage: "the directory containing the Carthage project"
			)

			return curry(Options.init)
				<*> mode <| Option(key: "use-ssh", defaultValue: false, usage: "use SSH for downloading GitHub repositories")
				<*> mode <| Option(key: "verbose", defaultValue: false, usage: "include nested dependencies")
				<*> mode <| Option(key: "xcode-warnings", defaultValue: false, usage: "output Xcode compatible warning messages")
				<*> ColorOptions.evaluate(mode, additionalUsage: UpdateType.legend)
				<*> mode <| projectDirectoryOption
				<*> mode <| Option(key: "use-netrc",
								   defaultValue: false,
								   usage: "use authentication credentials from ~/.netrc file when downloading binary only frameworks")
		}

		/// Attempts to load the project referenced by the options, and configure it
		/// accordingly.
		public func loadProject() -> SignalProducer<Project, CarthageError> {
			let directoryURL = URL(fileURLWithPath: self.directoryPath, isDirectory: true)
			let project = Project(directoryURL: directoryURL)
			project.preferHTTPS = !self.useSSH
			project.useNetrc = self.useNetrc

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
							let update = UpdateType(currentVersion: current, applicableVersion: applicable, latestVersion: latest)
							let style = formatting[update]
							let versionSummary = "\(style(current.description)) -> \(style(applicable.description)) (Latest: \(latest))"
							carthage.println(formatting.projectName(project.name) + " " + versionSummary)
						}
					}
				} else {
					carthage.println("All dependencies are up to date.")
				}
			})
			.waitOnCommand()
	}
}
