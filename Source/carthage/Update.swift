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
import ReactiveCocoa

public struct UpdateCommand: CommandType {
	public struct Options: OptionsType {
		public let checkoutAfterUpdate: Bool
		public let buildAfterUpdate: Bool
		public let verbose: Bool
		public let buildOptions: CarthageKit.BuildOptions
		public let checkoutOptions: CheckoutCommand.Options
		public let dependenciesToUpdate: [String]?

		/// The build options corresponding to these options.
		public var buildCommandOptions: BuildCommand.Options {
			return BuildCommand.Options(buildOptions: buildOptions, skipCurrent: true, colorOptions: checkoutOptions.colorOptions, verbose: verbose, directoryPath: checkoutOptions.directoryPath, dependenciesToBuild: dependenciesToUpdate)
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

		public static func create(checkoutAfterUpdate: Bool) -> Bool -> Bool -> BuildOptions -> CheckoutCommand.Options -> Options {
			return { buildAfterUpdate in { verbose in {  buildOptions in { checkoutOptions in
				return self.init(checkoutAfterUpdate: checkoutAfterUpdate, buildAfterUpdate: buildAfterUpdate, verbose: verbose, buildOptions: buildOptions, checkoutOptions: checkoutOptions, dependenciesToUpdate: checkoutOptions.dependenciesToCheckout)
			} } } }
		}

		public static func evaluate(m: CommandMode) -> Result<Options, CommandantError<CarthageError>> {
			return create
				<*> m <| Option(key: "checkout", defaultValue: true, usage: "skip the checking out of dependencies after updating")
				<*> m <| Option(key: "build", defaultValue: true, usage: "skip the building of dependencies after updating\n(ignored if --no-checkout option is present)")
				<*> m <| Option(key: "verbose", defaultValue: false, usage: "print xcodebuild output inline (ignored if --no-build option is present)")
				<*> BuildOptions.evaluate(m, addendum: "\n(ignored if --no-build option is present)")
				<*> CheckoutCommand.Options.evaluate(m, useBinariesAddendum: "\n(ignored if --no-build option is present)", dependenciesUsage: "the dependency names to update, checkout and build")
		}

		/// Attempts to load the project referenced by the options, and configure it
		/// accordingly.
		public func loadProject() -> SignalProducer<Project, CarthageError> {
			return checkoutOptions.loadProject()
				.on(next: { project in
					// Never check out binaries if we're skipping the build step,
					// because that means users may need the repository checkout.
					if !self.buildAfterUpdate {
						project.useBinaries = false
					}
				})
		}
	}
	
	public let verb = "update"
	public let function = "Update and rebuild the project's dependencies"

	public func run(options: Options) -> Result<(), CarthageError> {
		return options.loadProject()
			.flatMap(.Merge) { project -> SignalProducer<(), CarthageError> in
				
				let checkDependencies: SignalProducer<(), CarthageError>
				if let depsToUpdate = options.dependenciesToUpdate {
					checkDependencies = project
						.loadCombinedCartfile()
						.flatMap(.Concat) { cartfile -> SignalProducer<(), CarthageError> in
							let dependencyNames = cartfile.dependencies.map { $0.project.name.lowercaseString }
							let unknownDependencyNames = Set(depsToUpdate.map { $0.lowercaseString }).subtract(dependencyNames)
							
							if !unknownDependencyNames.isEmpty {
								return SignalProducer(error: .UnknownDependencies(unknownDependencyNames.sort()))
							}
							return .empty
						}
				} else {
					checkDependencies = .empty
				}
				
				let updateDependencies = project.updateDependencies(
					shouldCheckout: options.checkoutAfterUpdate,
					dependenciesToUpdate: options.dependenciesToUpdate
				)
				
				return checkDependencies.then(updateDependencies)
			}
			.then(options.buildProducer)
			.waitOnCommand()
	}
}
