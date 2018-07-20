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
			.on(value: { _ in
				carthage.println("No incompatibilities found in Cartfile.resolved")
			})
			.waitOnCommand()
	}
}
