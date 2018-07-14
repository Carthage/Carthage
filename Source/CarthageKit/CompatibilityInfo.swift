import Foundation

/// Identifies a dependency, its pinned version, and versions of this dependency with which it may or may not be compatible
public struct CompatibilityInfo: Equatable {
	/// The dependecy
	public let dependency: Dependency

	/// The pinned version of the dependency
	public let pinnedVersion: PinnedVersion
	
	/// Versions of this dependency with which it may or may not be compatible
	public let dependencyVersions: [(Dependency, VersionSpecifier)]
	
	/// The versions which are not compatible with the pinned version of this dependency
	public var incompatibleVersions: [(Dependency, VersionSpecifier)] {
		return dependencyVersions.filter { _, version in !version.isSatisfied(by: pinnedVersion) }
	}

	public static func == (lhs: CompatibilityInfo, rhs: CompatibilityInfo) -> Bool {
		return lhs.dependency == rhs.dependency &&
			lhs.pinnedVersion == rhs.pinnedVersion &&
			lhs.dependencyVersions.elementsEqual(rhs.dependencyVersions, by: { $0.0 == $1.0 && $0.1 == $1.1 })
	}
}
