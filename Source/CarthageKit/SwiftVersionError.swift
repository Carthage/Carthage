import Foundation

internal enum SwiftVersionError: Error, Equatable {
	/// An error in determining the local Swift version
	case unknownLocalSwiftVersion

	/// An error in determining the framework Swift version
	case unknownFrameworkSwiftVersion(message: String)

	/// The framework binary is not compatible with the local Swift version.
	case incompatibleFrameworkSwiftVersions(local: String, framework: String)

}

extension SwiftVersionError: CustomStringConvertible {
	var description: String {
		switch self {
		case .unknownLocalSwiftVersion:
			return "Unable to determine local Swift version."

		case let .unknownFrameworkSwiftVersion(message):
			return "Unable to determine framework Swift version: \(message)"

		case let .incompatibleFrameworkSwiftVersions(local, framework):
			return "Incompatible Swift version - framework was built with \(framework) and the local version is \(local)."
		}
	}
}
