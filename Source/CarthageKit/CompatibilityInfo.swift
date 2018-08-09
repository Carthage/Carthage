import Foundation

/// Identifies a dependency, its pinned version, and its compatible and incompatible requirements
public struct CompatibilityInfo {
	/// The dependency
	public let dependency: Dependency

	/// The pinned version of this dependency
	public let pinnedVersion: PinnedVersion

	/// Requirements with which the pinned version of this dependency may or may not be compatible
	private let requirements: [Dependency: VersionSpecifier]

	public init(dependency: Dependency, pinnedVersion: PinnedVersion, requirements: [Dependency: VersionSpecifier]) {
		self.dependency = dependency
		self.pinnedVersion = pinnedVersion
		self.requirements = requirements
	}

	/// Requirements which are compatible with the pinned version of this dependency
	public var compatibleRequirements: [Dependency: VersionSpecifier] {
		return requirements.filter { _, version in version.isSatisfied(by: pinnedVersion) }
	}

	/// Requirements which are not compatible with the pinned version of this dependency
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
