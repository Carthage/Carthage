//
//  Update.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-12.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa
import CarthageKit

public struct UpdateCommand: CommandType {
	public let verb = "update"
	public let function = "Update and rebuild the project's dependencies"

	public func run(mode: CommandMode) -> Result<()> {
		return ColdSignal.fromResult(UpdateOptions.evaluate(mode))
			.map { options -> ColdSignal<()> in
				return ColdSignal.fromResult(options.checkoutOptions.loadProject())
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
	public let checkoutOptions: CheckoutOptions

	/// The build options corresponding to these options.
	public var buildOptions: BuildOptions {
		return BuildOptions(configuration: configuration, skipCurrent: true, directoryPath: checkoutOptions.directoryPath)
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

	public static func create(configuration: String)(buildAfterUpdate: Bool)(checkoutOptions: CheckoutOptions) -> UpdateOptions {
		return self(buildAfterUpdate: buildAfterUpdate, configuration: configuration, checkoutOptions: checkoutOptions)
	}

	public static func evaluate(m: CommandMode) -> Result<UpdateOptions> {
		return create
			<*> m <| Option(key: "configuration", defaultValue: "Release", usage: "the Xcode configuration to build (ignored if --no-build option is present)")
			<*> m <| Option(key: "build", defaultValue: true, usage: "skip the building of dependencies after updating")
			<*> CheckoutOptions.evaluate(m)
	}
}
