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
import ReactiveSwift

public struct BootstrapCommand: CommandProtocol {
	public let verb = "bootstrap"
	public let function = "Check out and build the project's dependencies"

	public func run(_ options: UpdateCommand.Options) -> Result<(), CarthageError> {
		// Reuse UpdateOptions, since all `bootstrap` flags should correspond to
		// `update` flags.
		return options.loadProject()
			.flatMap(.merge) { project -> SignalProducer<(), CarthageError> in
				if !FileManager.default.fileExists(atPath: project.resolvedCartfileURL.path) {
					let formatting = options.checkoutOptions.colorOptions.formatting
					carthage.println(formatting.bullets + "No Cartfile.resolved found, updating dependencies")
					return project.updateDependencies(shouldCheckout: options.checkoutAfterUpdate)
				}
				
				let checkDependencies: SignalProducer<(), CarthageError>
				if let depsToUpdate = options.dependenciesToUpdate {
					checkDependencies = project
						.loadResolvedCartfile()
						.flatMap(.concat) { resolvedCartfile -> SignalProducer<(), CarthageError> in
							let resolvedDependencyNames = resolvedCartfile.dependencies.map { $0.project.name.lowercased() }
							let unresolvedDependencyNames = Set(depsToUpdate.map { $0.lowercased() }).subtracting(resolvedDependencyNames)
							
							if !unresolvedDependencyNames.isEmpty {
								return SignalProducer(error: .unresolvedDependencies(unresolvedDependencyNames.sorted()))
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
