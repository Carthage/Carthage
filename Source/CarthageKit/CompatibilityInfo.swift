import Foundation
import Result

/// Identifies a dependency, its pinned version, and its compatible and incompatible requirements
public struct CompatibilityInfo: Equatable {
	public typealias Requirements = [Dependency: [Dependency: VersionSpecifier]]

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

	/// Accepts a dictionary which maps a dependency to the pinned versions of the dependencies it requires.
	/// Returns an inverted dictionary which maps a dependency to the dependencies that require it and the pinned version required
	/// e.g. [A: [B: 1, C: 2]] -> [B: [A: 1], C: [A: 2]]
	public static func invert(requirements: Requirements) -> Result<Requirements, CarthageError> {
		var invertedRequirements: Requirements = [:]
		for (dependency, requirements) in requirements {
			for (requiredDependency, requiredVersion) in requirements {
				var requirements = invertedRequirements[requiredDependency] ?? [:]

				if requirements[dependency] != nil {
					return .init(error: .duplicateDependencies([DuplicateDependency(dependency: dependency, locations: [])]))
				}

				requirements[dependency] = requiredVersion
				invertedRequirements[requiredDependency] = requirements
			}
		}
		return .init(invertedRequirements)
	}

	/// Constructs CompatibilityInfo objects for dependencies with incompatibilities
	/// given a dictionary of dependencies with pinned versions and their corresponding requirements
	public static func incompatibilities(for dependencies: [Dependency: PinnedVersion], requirements: CompatibilityInfo.Requirements) -> Result<[CompatibilityInfo], CarthageError> {
		return CompatibilityInfo.invert(requirements: requirements)
			.map { invertedRequirements -> [CompatibilityInfo] in
				return dependencies.compactMap { dependency, version in
					if case .success = SemanticVersion.from(version), let requirements = invertedRequirements[dependency] {
						return CompatibilityInfo(dependency: dependency, pinnedVersion: version, requirements: requirements)
					}
					return nil
				}
				.filter { !$0.incompatibleRequirements.isEmpty }
			}
	}
}
