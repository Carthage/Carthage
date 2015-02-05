//
//  Bootstrap.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-15.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Commandant
import Foundation
import LlamaKit
import ReactiveCocoa

public struct BootstrapCommand: CommandType {
	public let verb = "bootstrap"
	public let function = "Check out and build the project's dependencies"

	public func run(mode: CommandMode) -> Result<()> {
		// Reuse UpdateOptions, since all `bootstrap` flags should correspond to
		// `update` flags.
		return ColdSignal.fromResult(UpdateOptions.evaluate(mode))
			.map { options -> ColdSignal<()> in
				return options.loadProject()
					.map { project -> ColdSignal<()> in
						return ColdSignal.lazy {
							if NSFileManager.defaultManager().fileExistsAtPath(project.resolvedCartfileURL.path!) {
								return project.checkoutResolvedDependencies()
							} else {
								let formatting = options.checkoutOptions.colorOptions.formatting
								carthage.println(formatting.bullets + "No Cartfile.resolved found, updating dependencies")
								return project.updateDependencies()
							}
						}
					}
					.merge(identity)
					.then(options.buildSignal)
			}
			.merge(identity)
			.wait()
	}
}
