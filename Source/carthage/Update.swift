//
//  Update.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-12.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Commandant
import Foundation
import Result
import ReactiveSwift

public struct UpdateCommand: CommandProtocol {
	public struct Options: OptionsProtocol {
		public let checkoutAfterUpdate: Bool
		public let buildAfterUpdate: Bool
		public let isVerbose: Bool
		public let buildOptions: CarthageKit.BuildOptions
		public let checkoutOptions: CheckoutCommand.Options
		public let logPath: String?
		public let dependenciesToUpdate: [String]?

		/// The build options corresponding to these options.
		public var buildCommandOptions: BuildCommand.Options {
			return BuildCommand.Options(buildOptions: buildOptions, skipCurrent: true, colorOptions: checkoutOptions.colorOptions, isVerbose: isVerbose, directoryPath: checkoutOptions.directoryPath, logPath: logPath, dependenciesToBuild: dependenciesToUpdate)
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

		public static func create(_ checkoutAfterUpdate: Bool) -> (Bool) -> (Bool) -> (String?) -> (BuildOptions) -> (CheckoutCommand.Options) -> Options {
			return { buildAfterUpdate in { isVerbose in { logPath in {  buildOptions in { checkoutOptions in
				return self.init(checkoutAfterUpdate: checkoutAfterUpdate, buildAfterUpdate: buildAfterUpdate, isVerbose: isVerbose, buildOptions: buildOptions, checkoutOptions: checkoutOptions, logPath: logPath, dependenciesToUpdate: checkoutOptions.dependenciesToCheckout)
			} } } } }
		}

		public static func evaluate(_ m: CommandMode) -> Result<Options, CommandantError<CarthageError>> {
			return create
				<*> m <| Option(key: "checkout", defaultValue: true, usage: "skip the checking out of dependencies after updating")
				<*> m <| Option(key: "build", defaultValue: true, usage: "skip the building of dependencies after updating\n(ignored if --no-checkout option is present)")
				<*> m <| Option(key: "verbose", defaultValue: false, usage: "print xcodebuild output inline (ignored if --no-build option is present)")
				<*> m <| Option(key: "log-path", defaultValue: nil, usage: "path to the xcode build output. A temporary file is used by default")
				<*> BuildOptions.evaluate(m, addendum: "\n(ignored if --no-build option is present)")
				<*> CheckoutCommand.Options.evaluate(m, useBinariesAddendum: "\n(ignored if --no-build or --toolchain option is present)", dependenciesUsage: "the dependency names to update, checkout and build")
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
