import CarthageKit
import Commandant
import Foundation
import ReactiveSwift
import Result

/// Type that encapsulates the configuration and evaluation of the `verify` subcommand.
public struct VerifyCommand: CommandProtocol {
	public let verb = "verify"
	public let function = "Verify that the dependencies in Cartfile.resolved are compatible"

	public func run(_ options: CheckoutCommand.Options) -> Result<(), CarthageError> {
		return options.loadProject().flatMap(.concat) { project in
				return project.verify()
			}
			.on(value: { (incompatibilities: [CompatibilityInfo]) in
				if incompatibilities.isEmpty {
					carthage.println("No incompatibilities found in Cartfile.resolved")
				} else {
					carthage.println("The following incompatibilities were found in Cartfile.resolved:")
					incompatibilities.forEach { incompatibility in
						for (dependency, version) in incompatibility.dependencyVersions {
							let message = "\(incompatibility.dependency.name) is incompatible with \(dependency.name) \(version)"
							let formatting = options.colorOptions.formatting
							carthage.println(formatting.bullets + message)
						}
					}
				}
			})
			.waitOnCommand()
	}
}
