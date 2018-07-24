import Foundation

/// Identifies a dependency, its pinned version, and versions of this dependency with which it may or may not be compatible
public struct CompatibilityInfo {
	/// The dependecy
	public let dependency: Dependency

	/// The pinned version of the dependency
	public let pinnedVersion: PinnedVersion

	/// Versions of this dependency with which it may or may not be compatible
	public let requirements: [Dependency: VersionSpecifier]

	/// The versions which are not compatible with the pinned version of this dependency
	public var incompatibleRequirements: [Dependency: VersionSpecifier] {
		return requirements.filter { _, version in !version.isSatisfied(by: pinnedVersion) }
	}
}

extension CompatibilityInfo: Equatable {
	public static func == (_ lhs: CompatibilityInfo, _ rhs: CompatibilityInfo) -> Bool {
		return lhs.dependency == rhs.dependency &&
			lhs.pinnedVersion == rhs.pinnedVersion &&
			lhs.requirements == rhs.requirements
	}
}
