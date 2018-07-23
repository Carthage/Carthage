import CarthageKit
import Commandant
import Foundation
import ReactiveSwift
import Result

/// Type that encapsulates the configuration and evaluation of the `verify` subcommand.
public struct VerifyCommand: CommandProtocol {
	public let verb = "verify"
	public let function = "Verify that the versions in Cartfile.resolved are compatible with the Cartfile requirements"

	public func run(_ options: CheckoutCommand.Options) -> Result<(), CarthageError> {
		return options.loadProject().flatMap(.concat) { (project: Project) in
				return project.loadResolvedCartfile().map {
						project.verify(resolvedCartfile: $0)
					}
			}
			.on(value: { _ in
				carthage.println("No incompatibilities found in Cartfile.resolved")
			})
			.waitOnCommand()
	}
}
