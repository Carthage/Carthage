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
import LlamaKit
import ReactiveCocoa

public struct UpdateCommand: CommandType {
	public let verb = "update"
	public let function = "Update and rebuild the project's dependencies"

	public func run(mode: CommandMode) -> Result<()> {
		return ColdSignal.fromResult(UpdateOptions.evaluate(mode))
			.map { options -> ColdSignal<()> in
				return ColdSignal.fromResult(options.projectSettings)
					.map { settings in loadProjectWithSettings(settings, options.checkoutOptions.colorOptions) }
					.merge(identity)
					.map { $0.updateDependencies() }
					.merge(identity)
					.then(options.buildSignal)
			}
			.merge(identity)
			.wait()
	}
}

public struct UpdateOptions: OptionsType {
	public let buildAfterUpdate: Bool
	public let configuration: String
	public let buildPlatform: BuildPlatform
	public let verbose: Bool

	// TODO: Hide this?
	public let checkoutOptions: CheckoutOptions

	/// The build options corresponding to these options.
	public var buildOptions: BuildOptions {
		return BuildOptions(configuration: configuration, buildPlatform: buildPlatform, skipCurrent: true, colorOptions: checkoutOptions.colorOptions, verbose: verbose, directoryPath: checkoutOptions.directoryPath)
	}

	/// If `buildAfterUpdate` is true, this will be a signal representing the
	/// work necessary to build the project.
	///
	/// Otherwise, this signal will be empty.
	public var buildSignal: ColdSignal<()> {
		if buildAfterUpdate {
			return BuildCommand().buildWithOptions(buildOptions)
		} else {
			return .empty()
		}
	}

	public static func create(configuration: String)(buildPlatform: BuildPlatform)(verbose: Bool)(buildAfterUpdate: Bool)(checkoutOptions: CheckoutOptions) -> UpdateOptions {
		return self(buildAfterUpdate: buildAfterUpdate, configuration: configuration, buildPlatform: buildPlatform, verbose: verbose, checkoutOptions: checkoutOptions)
	}

	public static func evaluate(m: CommandMode) -> Result<UpdateOptions> {
		return create
			<*> m <| Option(key: "configuration", defaultValue: "Release", usage: "the Xcode configuration to build (ignored if --no-build option is present)")
			<*> m <| Option(key: "platform", defaultValue: .All, usage: "the platform to build for (ignored if --no-build option is present)")
			<*> m <| Option(key: "verbose", defaultValue: false, usage: "print xcodebuild output inline (ignored if --no-build option is present)")
			<*> m <| Option(key: "build", defaultValue: true, usage: "skip the building of dependencies after updating")
			<*> CheckoutOptions.evaluate(m, useBinariesAddendum: " (ignored if --no-build option is present)")
	}

	/// Attempts to instantiate the `ProjectSettings` corresponding to the given
	/// options.
	public var projectSettings: Result<ProjectSettings> {
		return checkoutOptions.projectSettings.map { (var settings) in
			// Never check out binaries if we're skipping the build step,
			// because that means users may need the repository checkout.
			if !self.buildAfterUpdate {
				settings.useBinaries = false
			}

			return settings
		}
	}
}
