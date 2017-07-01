import CarthageKit
import Commandant
import Foundation
import Result

public struct VersionCommand: CommandProtocol {
	public let verb = "version"
	public let function = "Display the current version of Carthage"

	public func run(_ options: NoOptions<CarthageError>) -> Result<(), CarthageError> {
		carthage.println(localVersion())
		return .success(())
	}
}
