/// Defines the current CarthageKit version.
public struct CarthageKitVersion {
	public let value: SemanticVersion

	public static let current = CarthageKitVersion(value: SemanticVersion(major: 0, minor: 30, patch: 1))
}
