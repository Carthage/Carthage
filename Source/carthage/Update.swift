import CarthageKit
import Commandant
import Foundation
import Result
import ReactiveSwift
import Curry

/// Type that encapsulates the configuration and evaluation of the `update` subcommand.
public struct UpdateCommand: CommandProtocol {
	public struct Options: OptionsProtocol {
		public let checkoutAfterUpdate: Bool
		public let buildAfterUpdate: Bool
		public let isVerbose: Bool
		public let logPath: String?
		public let buildOptions: CarthageKit.BuildOptions
		public let checkoutOptions: CheckoutCommand.Options
		public let dependenciesToUpdate: [String]?
		public let isPrivateCache: Bool

		/// The build options corresponding to these options.
		public var buildCommandOptions: BuildCommand.Options {
			return BuildCommand.Options(
				buildOptions: buildOptions,
				skipCurrent: true,
				colorOptions: checkoutOptions.colorOptions,
				isVerbose: isVerbose,
				directoryPath: checkoutOptions.directoryPath,
				logPath: logPath,
				dependenciesToBuild: dependenciesToUpdate,
				isPrivateCache: isPrivateCache
			)
		}

		/// If `checkoutAfterUpdate` and `buildAfterUpdate` are both true, this will
		/// be a producer representing the work necessary to build the project.
		///
		/// Otherwise, this producer will be empty.
		public var buildProducer: SignalProducer<(), CarthageError> {
			if checkoutAfterUpdate && buildAfterUpdate {
				return BuildCommand().buildWithOptions(buildCommandOptions)
			} else {
				return .empty
			}
		}

		private init(checkoutAfterUpdate: Bool,
		             buildAfterUpdate: Bool,
		             isVerbose: Bool,
		             logPath: String?,
		             buildOptions: BuildOptions,
		             checkoutOptions: CheckoutCommand.Options,
		             isPrivateCache: Bool)
		{
			self.checkoutAfterUpdate = checkoutAfterUpdate
			self.buildAfterUpdate = buildAfterUpdate
			self.isVerbose = isVerbose
			self.logPath = logPath
			self.buildOptions = buildOptions
			self.checkoutOptions = checkoutOptions
			self.dependenciesToUpdate = checkoutOptions.dependenciesToCheckout
			self.isPrivateCache = isPrivateCache
		}

		public static func evaluate(_ mode: CommandMode) -> Result<Options, CommandantError<CarthageError>> {
			let buildDescription = "skip the building of dependencies after updating\n(ignored if --no-checkout option is present)"

			let binariesAddendum = "\n(ignored if --no-build or --toolchain option is present)"
			let dependenciesUsage = "the dependency names to update, checkout and build"

			return curry(self.init)
				<*> mode <| Option(key: "checkout", defaultValue: true, usage: "skip the checking out of dependencies after updating")
				<*> mode <| Option(key: "build", defaultValue: true, usage: buildDescription)
				<*> mode <| Option(key: "verbose", defaultValue: false, usage: "print xcodebuild output inline (ignored if --no-build option is present)")
				<*> mode <| Option(key: "log-path", defaultValue: nil, usage: "path to the xcode build output. A temporary file is used by default")
				<*> BuildOptions.evaluate(mode, addendum: "\n(ignored if --no-build option is present)")
				<*> CheckoutCommand.Options.evaluate(mode, useBinariesAddendum: binariesAddendum, dependenciesUsage: dependenciesUsage)
				<*> mode <| Option(key: "private-cache", defaultValue: false, usage: "creates different cache folder")
		}

		/// Attempts to load the project referenced by the options, and configure it
		/// accordingly.
		public func loadProject() -> SignalProducer<Project, CarthageError> {
			return checkoutOptions.loadProject()
				.on(value: { project in
					// Never check out binaries if 
					// 1. we're skipping the build step, or
					// 2. `--toolchain` option is given
					// because that means users may need the repository checkout.
					if !self.buildAfterUpdate || self.buildOptions.toolchain != nil {
						project.useBinaries = false
					}
				})
		}
	}

	public let verb = "update"
	public let function = "Update and rebuild the project's dependencies"

	public func run(_ options: Options) -> Result<(), CarthageError> {
		return options.loadProject()
			.flatMap(.merge) { project -> SignalProducer<(), CarthageError> in

				let checkDependencies: SignalProducer<(), CarthageError>
				if let depsToUpdate = options.dependenciesToUpdate {
					checkDependencies = project
						.loadCombinedCartfile()
						.flatMap(.concat) { cartfile -> SignalProducer<(), CarthageError> in
							let dependencyNames = cartfile.dependencies.keys.map { $0.name.lowercased() }
							let unknownDependencyNames = Set(depsToUpdate.map { $0.lowercased() }).subtracting(dependencyNames)

							if !unknownDependencyNames.isEmpty {
								return SignalProducer(error: .unknownDependencies(unknownDependencyNames.sorted()))
							}
							return .empty
						}
				} else {
					checkDependencies = .empty
				}

				let updateDependencies = project.updateDependencies(
					shouldCheckout: options.checkoutAfterUpdate, buildOptions: options.buildOptions,
					dependenciesToUpdate: options.dependenciesToUpdate
				)

				return checkDependencies.then(updateDependencies)
			}
			.then(options.buildProducer)
			.waitOnCommand()
	}
}
