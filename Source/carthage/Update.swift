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
		public let configuration: String
		public let buildPlatform: BuildPlatform
		public let toolchain: String?
		public let derivedDataPath: String?
		public let verbose: Bool
		public let checkoutOptions: CheckoutCommand.Options
		public let dependenciesToUpdate: [String]?

		/// The build options corresponding to these options.
		public var buildOptions: BuildCommand.Options {
			return BuildCommand.Options(configuration: configuration, buildPlatform: buildPlatform, toolchain: toolchain, derivedDataPath: derivedDataPath, skipCurrent: true, colorOptions: checkoutOptions.colorOptions, verbose: verbose, directoryPath: checkoutOptions.directoryPath, dependenciesToBuild: dependenciesToUpdate)
		}

		/// If `checkoutAfterUpdate` and `buildAfterUpdate` are both true, this will
		/// be a producer representing the work necessary to build the project.
		///
		/// Otherwise, this producer will be empty.
		public var buildProducer: SignalProducer<(), CarthageError> {
			if checkoutAfterUpdate && buildAfterUpdate {
				return BuildCommand().buildWithOptions(buildOptions)
			} else {
				return .empty
			}
		}

		public static func create(configuration: String) -> BuildPlatform -> String? -> String? -> Bool -> Bool -> Bool -> CheckoutCommand.Options -> Options {
			return { buildPlatform in { toolchain in { derivedDataPath in { verbose in { checkoutAfterUpdate in { buildAfterUpdate in { checkoutOptions in
				return self.init(checkoutAfterUpdate: checkoutAfterUpdate, buildAfterUpdate: buildAfterUpdate, configuration: configuration, buildPlatform: buildPlatform, toolchain: toolchain, derivedDataPath: derivedDataPath, verbose: verbose, checkoutOptions: checkoutOptions, dependenciesToUpdate: checkoutOptions.dependenciesToCheckout)
			} } } } } } }
		}

		public static func evaluate(m: CommandMode) -> Result<Options, CommandantError<CarthageError>> {
			return create
				<*> m <| Option(key: "configuration", defaultValue: "Release", usage: "the Xcode configuration to build (ignored if --no-build option is present)")
				<*> m <| Option(key: "platform", defaultValue: .All, usage: "the platforms to build for (one of ‘all’, ‘Mac’, ‘iOS’, ‘watchOS’, 'tvOS', or comma-separated values of the formers except for ‘all’)\n(ignored if --no-build option is present)")
				<*> m <| Option<String?>(key: "toolchain", defaultValue: nil, usage: "the toolchain to build with")
				<*> m <| Option<String?>(key: "derived-data", defaultValue: nil, usage: "path to the custom derived data folder")
				<*> m <| Option(key: "verbose", defaultValue: false, usage: "print xcodebuild output inline (ignored if --no-build option is present)")
				<*> m <| Option(key: "checkout", defaultValue: true, usage: "skip the checking out of dependencies after updating")
				<*> m <| Option(key: "build", defaultValue: true, usage: "skip the building of dependencies after updating (ignored if --no-checkout option is present)")
				<*> CheckoutCommand.Options.evaluate(m, useBinariesAddendum: " (ignored if --no-build option is present)", dependenciesUsage: "the dependency names to update, checkout and build")
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
