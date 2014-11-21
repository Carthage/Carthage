//
//  Bootstrap.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-15.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa
import CarthageKit

public struct BootstrapCommand: CommandType {
	public let verb = "bootstrap"
	public let function = "Check out and build the project's dependencies"

	public func run(mode: CommandMode) -> Result<()> {
		// Reuse UpdateOptions, since all `bootstrap` flags should correspond to
		// `update` flags.
		return ColdSignal.fromResult(UpdateOptions.evaluate(mode))
			.map { options -> ColdSignal<()> in
				return ColdSignal.fromResult(options.checkoutOptions.loadProject())
					.map { project -> ColdSignal<()> in
						return ColdSignal.lazy {
							if NSFileManager.defaultManager().fileExistsAtPath(project.cartfileLockURL.path!) {
								return project.checkoutLockedDependencies()
							} else {
								println("*** No Cartfile.lock found, updating dependencies")
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
