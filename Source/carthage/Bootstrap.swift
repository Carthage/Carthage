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
import Result
import ReactiveCocoa

public struct BootstrapCommand: CommandType {
	public let verb = "bootstrap"
	public let function = "Check out and build the project's dependencies"

	public func run(options: UpdateCommand.Options) -> Result<(), CarthageError> {
		// Reuse UpdateOptions, since all `bootstrap` flags should correspond to
		// `update` flags.
		return options.loadProject()
			.flatMap(.Merge) { project -> SignalProducer<(), CarthageError> in
				if !NSFileManager.defaultManager().fileExistsAtPath(project.resolvedCartfileURL.path!) {
					let formatting = options.checkoutOptions.colorOptions.formatting
					carthage.println(formatting.bullets + "No Cartfile.resolved found, updating dependencies")
					return project.updateDependencies(shouldCheckout: options.checkoutAfterUpdate)
				}
				
				let checkDependencies: SignalProducer<(), CarthageError>
				if let depsToUpdate = options.dependenciesToUpdate {
					checkDependencies = project
						.loadResolvedCartfile()
						.flatMap(.Concat) { resolvedCartfile -> SignalProducer<(), CarthageError> in
							let resolvedDependencyNames = resolvedCartfile.dependencies.map { $0.project.name.lowercaseString }
							let unresolvedDependencyNames = Set(depsToUpdate.map { $0.lowercaseString }).subtract(resolvedDependencyNames)
							
							if !unresolvedDependencyNames.isEmpty {
								return SignalProducer(error: .UnresolvedDependencies(unresolvedDependencyNames.sort()))
							}
							return .empty
						}
				} else {
					checkDependencies = .empty
				}
				
				let checkoutDependencies: SignalProducer<(), CarthageError>
				if options.checkoutAfterUpdate {
					checkoutDependencies = project.checkoutResolvedDependencies(options.dependenciesToUpdate)
				} else {
					checkoutDependencies = .empty
				}
				
				return checkDependencies.then(checkoutDependencies)
			}
			.then(options.buildProducer)
			.waitOnCommand()
	}
}
