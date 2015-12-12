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
	public let verb = "update"
	public let function = "Update and rebuild the project's dependencies"

	public func run(mode: CommandMode) -> Result<(), CommandantError<CarthageError>> {
		return producerWithOptions(UpdateOptions.evaluate(mode))
			.flatMap(.Merge) { options -> SignalProducer<(), CommandError> in
				return options.loadProject()
					.flatMap(.Merge) { $0.updateDependencies(
						shouldCheckout: options.checkoutAfterUpdate,
						dependenciesToUpdate: options.dependenciesToUpdate
						)
					}
					.then(options.buildProducer)
					.promoteErrors()
			}
			.waitOnCommand()
	}
}

public struct UpdateOptions: OptionsType {
	public let checkoutAfterUpdate: Bool
	public let buildAfterUpdate: Bool
	public let configuration: String
	public let buildPlatform: BuildPlatform
	public let dependenciesToUpdate: [String]
	public let verbose: Bool
	public let checkoutOptions: CheckoutOptions

	/// The build options corresponding to these options.
	public var buildOptions: BuildOptions {
		return BuildOptions(configuration: configuration, buildPlatform: buildPlatform, dependenciesToBuild: dependenciesToUpdate, skipCurrent: true, colorOptions: checkoutOptions.colorOptions, verbose: verbose, directoryPath: checkoutOptions.directoryPath)
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

	public static func create(configuration: String) -> BuildPlatform -> String -> Bool -> Bool -> Bool -> CheckoutOptions -> UpdateOptions {
		return { buildPlatform in { dependenciesToUpdate in { verbose in { checkoutAfterUpdate in { buildAfterUpdate in { checkoutOptions in
			return self.init(checkoutAfterUpdate: checkoutAfterUpdate, buildAfterUpdate: buildAfterUpdate, configuration: configuration, buildPlatform: buildPlatform, dependenciesToUpdate: dependenciesToUpdate.split(), verbose: verbose, checkoutOptions: checkoutOptions)
		} } } } } }
	}

	public static func evaluate(m: CommandMode) -> Result<UpdateOptions, CommandantError<CarthageError>> {
		return create
			<*> m <| Option(key: "configuration", defaultValue: "Release", usage: "the Xcode configuration to build (ignored if --no-build option is present)")
			<*> m <| Option(key: "platform", defaultValue: .All, usage: "the platforms to build for (one of ‘all’, ‘Mac’, ‘iOS’, ‘watchOS’, 'tvOS', or comma-separated values of the formers except for ‘all’)\n(ignored if --no-build option is present)")
			<*> m <| Option(key: "include", defaultValue: "", usage: "the comma-separated dependency names to update and build")
			<*> m <| Option(key: "verbose", defaultValue: false, usage: "print xcodebuild output inline (ignored if --no-build option is present)")
			<*> m <| Option(key: "checkout", defaultValue: true, usage: "skip the checking out of dependencies after updating")
			<*> m <| Option(key: "build", defaultValue: true, usage: "skip the building of dependencies after updating (ignored if --no-checkout option is present)")
			<*> CheckoutOptions.evaluate(m, useBinariesAddendum: " (ignored if --no-build option is present)")
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
