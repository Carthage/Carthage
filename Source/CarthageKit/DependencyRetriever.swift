import Foundation
import Result
import ReactiveSwift

/**
Class responsible for the retrieval of dependencies using the supplied closures as strategies.

This class adds caching functionality to optimize for performance.

It also keeps track of encountered conflicts.
*/
final class DependencyRetriever {
	private var pinnedVersions: [Dependency: PinnedVersion]
	private let versionsForDependency: (Dependency) -> SignalProducer<PinnedVersion, CarthageError>
	private let resolvedGitReference: (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
	private let dependenciesForDependency: (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>

	private var dependencyCache = [PinnedDependency: [DependencyEntry]]()
	private var versionsCache = [DependencyVersionSpec: ConcreteVersionSet]()
	private var conflictCache = [PinnedDependency: DependencyConflict]()
	private var cachedSortedProblematicDependencies: [Dependency]?
	private var problematicDependencyDictionary = [Dependency: Int]()

	public init(
		versionsForDependency: @escaping (Dependency) -> SignalProducer<PinnedVersion, CarthageError>,
		dependenciesForDependency: @escaping (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>,
		resolvedGitReference: @escaping (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>,
		pinnedVersions: [Dependency: PinnedVersion]
		) {
		self.versionsForDependency = versionsForDependency
		self.dependenciesForDependency = dependenciesForDependency
		self.resolvedGitReference = resolvedGitReference
		self.pinnedVersions = pinnedVersions
	}

	/**
	Finds all versions for the specified dependency compatible with the specified versionSpecifier.
	*/
	public func findAllVersions(for dependency: Dependency, compatibleWith versionSpecifier: VersionSpecifier, isUpdatable: Bool) throws -> ConcreteVersionSet {
		let versionedDependency = DependencyVersionSpec(dependency: dependency, versionSpecifier: versionSpecifier, isUpdatable: isUpdatable)

		let concreteVersionSet = try versionsCache.object(
			for: versionedDependency,
			byStoringDefault: try findAllVersionsUncached(for: dependency, compatibleWith: versionSpecifier, isUpdatable: isUpdatable)
		)

		guard !isUpdatable || !concreteVersionSet.isEmpty else {
			throw CarthageError.requiredVersionNotFound(dependency, versionSpecifier)
		}

		return concreteVersionSet
	}

	/**
	Finds all transitive dependencies for the specified dependency and concrete version.
	*/
	public func findDependencies(for dependency: Dependency, version: ConcreteVersion) throws -> [DependencyEntry] {
		let pinnedDependency = PinnedDependency(dependency: dependency, pinnedVersion: version.pinnedVersion)
		var result: [DependencyEntry] = try dependencyCache.object(
			for: pinnedDependency,
			byStoringDefault: try dependenciesForDependency(dependency, version.pinnedVersion).collect().first()!.dematerialize()
		)

		// Sort according to relevance for faster processing: always process problematic dependencies first
		if !problematicDependencies.isEmpty {
			result.sort { entry1, entry2 -> Bool in
				let problemCount1 = problematicDependencyDictionary[entry1.key] ?? 0
				let problemCount2 = problematicDependencyDictionary[entry2.key] ?? 0
				return problemCount1 > problemCount2
			}
		}

		return result
	}

	/**
	Adds a conflict to the cache. If conflictingDependency is specified as nil, the conflict is with the root level definitions (Cartfile).
	*/
	public func addCachedConflict(for dependency: ConcreteVersionedDependency, conflictingWith conflictingDependency: ConcreteVersionedDependency? = nil, error: CarthageError) {
		storeCachedConflict(for: dependency, conflictingWith: conflictingDependency, error: error)

		// Add the inverse as well
		if let nonNilConflictingDependency = conflictingDependency {
			storeCachedConflict(for: nonNilConflictingDependency, conflictingWith: dependency, error: error)
		}
	}

	/**
	Returns a cached conflict for the specified dependency or nil if there is no such cached conflict.
	*/
	public func cachedConflict(for dependency: ConcreteVersionedDependency) -> DependencyConflict? {
		let key = PinnedDependency(dependency: dependency.dependency, pinnedVersion: dependency.concreteVersion.pinnedVersion)
		return conflictCache[key]
	}

	/**
	Sorted problematic dependencies with decreasing severity (most problematic dependencies are ordered first).
	*/
	public var problematicDependencies: [Dependency] {
		if let dependencies = cachedSortedProblematicDependencies {
			return dependencies
		} else {
			let dependencies = problematicDependencyDictionary.sorted { entry1, entry2 -> Bool in entry1.value > entry2.value }.map { $0.key }
			cachedSortedProblematicDependencies = dependencies
			return dependencies
		}
	}

	/**
	Adds a dependency to the list of problematic dependencies, increasing its severity if it's already there.
	*/
	public func addProblematicDependency(_ dependency: Dependency) {
		let count = problematicDependencyDictionary[dependency] ?? 0
		problematicDependencyDictionary[dependency] = count + 1
		cachedSortedProblematicDependencies = nil
	}

	private func findAllVersionsUncached(for dependency: Dependency, compatibleWith versionSpecifier: VersionSpecifier, isUpdatable: Bool) throws -> ConcreteVersionSet {
		let versionSet = ConcreteVersionSet()

		if !isUpdatable, let pinnedVersion = pinnedVersions[dependency] {
			versionSet.insert(ConcreteVersion(pinnedVersion: pinnedVersion))
			versionSet.pinnedVersionSpecifier = versionSpecifier
		} else if isUpdatable {
			let pinnedVersionsProducer: SignalProducer<PinnedVersion, CarthageError>

			switch versionSpecifier {
			case .gitReference(let hash):
				pinnedVersionsProducer = resolvedGitReference(dependency, hash)
			default:
				pinnedVersionsProducer = versionsForDependency(dependency)
			}

			let concreteVersionsProducer = pinnedVersionsProducer.filterMap { pinnedVersion -> ConcreteVersion? in
				let concreteVersion = ConcreteVersion(pinnedVersion: pinnedVersion)
				versionSet.insert(concreteVersion)
				return nil
			}

			_ = try concreteVersionsProducer.collect().first()!.dematerialize()
		}

		versionSet.retainVersions(compatibleWith: versionSpecifier)
		return versionSet
	}

	private func storeCachedConflict(for dependency: ConcreteVersionedDependency, conflictingWith conflictingDependency: ConcreteVersionedDependency? = nil, error: CarthageError) {
		let key = PinnedDependency(dependency: dependency.dependency, pinnedVersion: dependency.concreteVersion.pinnedVersion)
		let newConflict: Bool
		if let existingConflict = conflictCache[key] {
			newConflict = existingConflict.addConflictingDependency(conflictingDependency)
		} else {
			conflictCache[key] = DependencyConflict(error: error, conflictingDependency: conflictingDependency)
			newConflict = true
		}
		if newConflict {
			addProblematicDependency(dependency.dependency)
		}
	}
}

final class DependencyConflict {
	// Error for the conflict
	public let error: CarthageError

	// Nil array means: conflict with root level definition
	public private(set) var conflictingDependencies: Set<ConcreteVersionedDependency>?

	fileprivate init(error: CarthageError, conflictingDependency: ConcreteVersionedDependency? = nil) {
		self.error = error
		if let nonNilConflictingDependency = conflictingDependency {
			conflictingDependencies = [nonNilConflictingDependency]
		}
	}

	@discardableResult
	fileprivate func addConflictingDependency(_ conflictingDependency: ConcreteVersionedDependency?) -> Bool {
		if let nonNilConflictingDependency = conflictingDependency {
			let result = conflictingDependencies?.insert(nonNilConflictingDependency)
			return result?.inserted ?? true
		} else {
			conflictingDependencies = nil
			return true
		}
	}
}

private struct PinnedDependency: Hashable {
	public let dependency: Dependency
	public let pinnedVersion: PinnedVersion
	private let hash: Int

	init(dependency: Dependency, pinnedVersion: PinnedVersion) {
		self.dependency = dependency
		self.pinnedVersion = pinnedVersion
		self.hash = 37 &* dependency.hashValue &+ pinnedVersion.hashValue
	}

	public var hashValue: Int {
		return hash
	}

	public static func == (lhs: PinnedDependency, rhs: PinnedDependency) -> Bool {
		return lhs.pinnedVersion == rhs.pinnedVersion && lhs.dependency == rhs.dependency
	}
}

private struct DependencyVersionSpec: Hashable {
	public let dependency: Dependency
	public let versionSpecifier: VersionSpecifier
	public let isUpdatable: Bool
	private let hash: Int

	init(dependency: Dependency, versionSpecifier: VersionSpecifier, isUpdatable: Bool) {
		self.dependency = dependency
		self.versionSpecifier = versionSpecifier
		self.isUpdatable = isUpdatable
		var h = dependency.hashValue
		h = 37 &* h &+ versionSpecifier.hashValue
		h = 37 &* h &+ isUpdatable.hashValue
		self.hash = h
	}

	public var hashValue: Int {
		return hash
	}

	public static func == (lhs: DependencyVersionSpec, rhs: DependencyVersionSpec) -> Bool {
		return lhs.isUpdatable == rhs.isUpdatable && lhs.versionSpecifier == rhs.versionSpecifier && lhs.dependency == rhs.dependency
	}
}
