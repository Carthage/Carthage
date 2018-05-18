import Foundation
import Result
import ReactiveSwift

// swiftlint:disable vertical_parameter_alignment_on_call
// swiftlint:disable vertical_parameter_alignment
private typealias DependencyEntry = (key: Dependency, value: VersionSpecifier)

/**
Resolver implementation based on an optimized Backtracking Algorithm.

See: https://en.wikipedia.org/wiki/Backtracking

The implementation does not use the reactive stream APIs to be able to keep the time complexity down and have a simple algorithm.
*/
public final class BackTrackingResolver: ResolverProtocol {
	private let versionsForDependency: (Dependency) -> SignalProducer<PinnedVersion, CarthageError>
	private let resolvedGitReference: (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
	private let dependenciesForDependency: (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>

	/**
	Current resolver state, accepted or rejected.
	*/
	private enum ResolverState {
		case rejected, accepted
	}

	/**
	Instantiates a resolver with the given strategies for retrieving the versions for a specific dependency, the set of dependencies for a pinned dependency and
	for retrieving a pinned git reference.
	
	versionsForDependency - Sends a stream of available versions for a
	                         dependency.
	dependenciesForDependency - Loads the dependencies for a specific
	                            version of a dependency.
	resolvedGitReference - Resolves an arbitrary Git reference to the
	                       	latest object.
	*/
	public init(
		versionsForDependency: @escaping (Dependency) -> SignalProducer<PinnedVersion, CarthageError>,
		dependenciesForDependency: @escaping (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>,
		resolvedGitReference: @escaping (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
		) {
		self.versionsForDependency = versionsForDependency
		self.dependenciesForDependency = dependenciesForDependency
		self.resolvedGitReference = resolvedGitReference
	}

	/**
	Attempts to determine the most appropriate valid version to use for each
	dependency in `dependencies`, and all nested dependencies thereof.

	Sends a dictionary with each dependency and its resolved version.
	*/
	public func resolve(
		dependencies: [Dependency: VersionSpecifier],
		lastResolved: [Dependency: PinnedVersion]? = nil,
		dependenciesToUpdate: [String]? = nil
		) -> SignalProducer<[Dependency: PinnedVersion], CarthageError> {
		let result: Result<[Dependency: PinnedVersion], CarthageError>

		let pinnedVersions = lastResolved ?? [Dependency: PinnedVersion]()
		let dependencyRetriever = DependencyRetriever(versionsForDependency: versionsForDependency,
													  dependenciesForDependency: dependenciesForDependency,
													  resolvedGitReference: resolvedGitReference,
													  pinnedVersions: pinnedVersions)
		let updatableDependencyNames = dependenciesToUpdate.map { Set($0) } ?? Set()
		let requiredDependencies: AnySequence<DependencyEntry>
		let hasSpecificDepedenciesToUpdate = !updatableDependencyNames.isEmpty

		if hasSpecificDepedenciesToUpdate {
			requiredDependencies = AnySequence(dependencies.filter { dependency, _ in
				updatableDependencyNames.contains(dependency.name) || pinnedVersions[dependency] != nil
			})
		} else {
			requiredDependencies = AnySequence(dependencies)
		}

		do {
			let dependencySet = try DependencySet(requiredDependencies: requiredDependencies,
												  updatableDependencyNames: updatableDependencyNames,
												  retriever: dependencyRetriever)
			let resolverResult = try backtrack(dependencySet: dependencySet)

			switch resolverResult.state {
			case .accepted:
				break
			case .rejected:
				if let rejectionError = dependencySet.rejectionError {
					throw rejectionError
				} else {
					throw CarthageError.unresolvedDependencies(dependencySet.unresolvedDependencies.map { $0.name })
				}
			}

			result = .success(resolverResult.dependencySet.resolvedDependencies)
		} catch let error {
			let carthageError: CarthageError = (error as? CarthageError) ?? CarthageError.internalError(description: error.localizedDescription)

			result = .failure(carthageError)
		}

		switch result {
		case .failure(let error):
			print("Resolver failed with error: \(error)")
		case .success(let dependencyDictionary):
			print("Resolver succeeded with dependency set: \(dependencyDictionary)")
		}

		return SignalProducer(result: result)
	}

	/**
	Recursive backtracking algorithm to resolve the dependency set.
	
	See: https://en.wikipedia.org/wiki/Backtracking
	*/
	private func backtrack(dependencySet: DependencySet) throws -> (state: ResolverState, dependencySet: DependencySet) {
		if dependencySet.isRejected {
			return (.rejected, dependencySet)
		} else if dependencySet.isComplete {
			return (.accepted, dependencySet)
		}

		var result: (state: ResolverState, dependencySet: DependencySet)? = nil
		while result == nil {
			// Use an autorelease pool here to keep memory usage down
			try autoreleasepool {
				// Keep iterating until there are no subsets to resolve anymore
				if let subSet = try dependencySet.popSubSet() {
					// Backtrack again with this subset
					let nestedResult = try backtrack(dependencySet: subSet)

					switch nestedResult.state {
					case .rejected:
						if subSet === dependencySet {
							result = (.rejected, subSet)
						}
					case .accepted:
						// Set contains all dependencies, we've got a winner
						result = (.accepted, nestedResult.dependencySet)
					}
				} else {
					// All done
					result = (.rejected, dependencySet)
				}
			}
		}

		// By definition result is not nil at this point (while loop only breaks when result is not nil)
		guard let finalResult = result else {
			preconditionFailure("Expected result to not be nil")
		}
		return finalResult
	}
}

/**
Class responsible for the retrieval of dependencies using the supplied closures as strategies.

This class adds caching functionality to optimize for performance.

It also keeps track of encountered conflicts.
*/
private final class DependencyRetriever {
	private var pinnedVersions: [Dependency: PinnedVersion]
	private let versionsForDependency: (Dependency) -> SignalProducer<PinnedVersion, CarthageError>
	private let resolvedGitReference: (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
	private let dependenciesForDependency: (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>

	private var dependencyCache = [PinnedDependency: [DependencyEntry]]()
	private var versionsCache = [VersionedDependency: ConcreteVersionSet]()
	private var conflictCache = [VersionedDependency: CarthageError]()

	init(
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

	private struct PinnedDependency: Hashable {
		let dependency: Dependency
		let pinnedVersion: PinnedVersion

		public var hashValue: Int {
			return 37 &* dependency.hashValue &+ pinnedVersion.hashValue
		}

		public static func == (lhs: PinnedDependency, rhs: PinnedDependency) -> Bool {
			return lhs.dependency == rhs.dependency && lhs.pinnedVersion == rhs.pinnedVersion
		}
	}

	private struct VersionedDependency: Hashable {
		let dependency: Dependency
		let versionSpecifier: VersionSpecifier
		let isUpdatable: Bool

		public var hashValue: Int {
			var hash = dependency.hashValue
			hash = 37 &* hash &+ versionSpecifier.hashValue
			hash = 37 &* hash &+ isUpdatable.hashValue
			return hash
		}

		public static func == (lhs: VersionedDependency, rhs: VersionedDependency) -> Bool {
			return lhs.dependency == rhs.dependency && lhs.versionSpecifier == rhs.versionSpecifier
		}
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

	func findAllVersions(for dependency: Dependency, compatibleWith versionSpecifier: VersionSpecifier, isUpdatable: Bool) throws -> ConcreteVersionSet {
		let versionedDependency = VersionedDependency(dependency: dependency, versionSpecifier: versionSpecifier, isUpdatable: isUpdatable)

		let concreteVersionSet = try versionsCache.object(
			for: versionedDependency,
			byStoringDefault: try findAllVersionsUncached(for: dependency, compatibleWith: versionSpecifier, isUpdatable: isUpdatable)
		)

		guard !isUpdatable || !concreteVersionSet.isEmpty else {
			throw CarthageError.requiredVersionNotFound(dependency, versionSpecifier)
		}

		print("Versions for dependency '\(dependency.name)' with versionSpecifier \(versionSpecifier): \(concreteVersionSet)")

		return concreteVersionSet
	}

	func findDependencies(for dependency: Dependency, version: ConcreteVersion) throws -> [DependencyEntry] {
		let pinnedDependency = PinnedDependency(dependency: dependency, pinnedVersion: version.pinnedVersion)
		let result: [DependencyEntry] = try dependencyCache.object(
			for: pinnedDependency,
			byStoringDefault: try dependenciesForDependency(dependency, version.pinnedVersion).collect().first()!.dematerialize()
		)

		print("Dependencies for dependency '\(dependency.name)' with version \(version): \(result)")

		return result
	}

	func setCachedError(_ error: CarthageError, for dependency: Dependency, with versionSpecifier: VersionSpecifier) {
		let key = VersionedDependency(dependency: dependency, versionSpecifier: versionSpecifier, isUpdatable: true)
		conflictCache[key] = error
	}

	func cachedError(for dependency: Dependency, with versionSpecifier: VersionSpecifier) -> CarthageError? {
		let key = VersionedDependency(dependency: dependency, versionSpecifier: versionSpecifier, isUpdatable: true)
		return conflictCache[key]
	}
}

/**
Set representing a complete dependency tree with all compatible versions per dependency.

It uses ConcreteVersionSet as implementation for storing the concrete compatible versions.
*/
private final class DependencySet {
	private var contents: [Dependency: ConcreteVersionSet]

	private var updatableDependencyNames: Set<String>

	private let retriever: DependencyRetriever

	public private(set) var unresolvedDependencies: Set<Dependency>

	public private(set) var rejectionError: CarthageError?

	public var isRejected: Bool {
		return rejectionError != nil
	}

	public var isComplete: Bool {
		// Dependency resolution is complete if there are no unresolved dependencies anymore
		return unresolvedDependencies.isEmpty
	}

	public var isAccepted: Bool {
		return !isRejected && isComplete
	}

	public var copy: DependencySet {
		return DependencySet(
			unresolvedDependencies: unresolvedDependencies,
			updatableDependencyNames: updatableDependencyNames,
			contents: contents.mapValues { $0.copy },
			retriever: retriever)
	}

	public var resolvedDependencies: [Dependency: PinnedVersion] {
		return contents.filterMapValues { $0.first?.pinnedVersion }
	}

	private init(unresolvedDependencies: Set<Dependency>,
				 updatableDependencyNames: Set<String>,
				 contents: [Dependency: ConcreteVersionSet],
				 retriever: DependencyRetriever) {
		self.unresolvedDependencies = unresolvedDependencies
		self.updatableDependencyNames = updatableDependencyNames
		self.contents = contents
		self.retriever = retriever
	}

	convenience init(requiredDependencies: AnySequence<DependencyEntry>,
							updatableDependencyNames: Set<String>,
							retriever: DependencyRetriever) throws {
		self.init(unresolvedDependencies: Set(requiredDependencies.map { $0.key }),
				  updatableDependencyNames: updatableDependencyNames,
				  contents: [Dependency: ConcreteVersionSet](),
				  retriever: retriever)
		try self.update(parent: nil, with: requiredDependencies)
	}

	public func removeVersion(_ version: ConcreteVersion, for dependency: Dependency) -> Bool {
		if let versionSet = contents[dependency] {
			versionSet.remove(version)
			return true
		}

		return false
	}

	public func setVersions(_ versions: ConcreteVersionSet, for dependency: Dependency) -> Bool {
		contents[dependency] = versions
		unresolvedDependencies.insert(dependency)
		return !versions.isEmpty
	}

	public func removeAllVersionsExcept(_ version: ConcreteVersion, for dependency: Dependency) -> Bool {
		if let versionSet = versions(for: dependency) {
			versionSet.removeAll(except: version)
			return !versionSet.isEmpty
		}
		return false
	}

	public func constrainVersions(for dependency: Dependency, with versionSpecifier: VersionSpecifier) -> Bool {
		if let versionSet = versions(for: dependency) {
			versionSet.retainVersions(compatibleWith: versionSpecifier)
			return !versionSet.isEmpty
		}
		return false
	}

	public func versions(for dependency: Dependency) -> ConcreteVersionSet? {
		return contents[dependency]
	}

	public func containsDependency(_ dependency: Dependency) -> Bool {
		return contents[dependency] != nil
	}

	public func isUpdatableDependency(_ dependency: Dependency) -> Bool {
		return updatableDependencyNames.isEmpty || updatableDependencyNames.contains(dependency.name)
	}

	public func addUpdatableDependency(_ dependency: Dependency) {
		if !updatableDependencyNames.isEmpty {
			updatableDependencyNames.insert(dependency.name)
		}
	}

	public func popSubSet() throws -> DependencySet? {
		while !unresolvedDependencies.isEmpty {
			if let dependency = unresolvedDependencies.first, let versionSet = contents[dependency], let version = versionSet.first {
				let count = versionSet.count
				let newSet: DependencySet
				if count > 1 {
					let copy = self.copy
					let valid1 = copy.removeAllVersionsExcept(version, for: dependency)

					assert(valid1, "Expected set to contain the specified version")

					let valid2 = removeVersion(version, for: dependency)

					assert(valid2, "Expected set to contain the specified version")

					newSet = copy
				} else {
					newSet = self
				}

				let transitiveDependencies = try retriever.findDependencies(for: dependency, version: version)

				try newSet.update(parent: dependency, with: AnySequence(transitiveDependencies), forceUpdatable: isUpdatableDependency(dependency))

				return newSet
			}
		}

		return nil
	}

	public func update(parent: Dependency?, with transitiveDependencies: AnySequence<DependencyEntry>, forceUpdatable: Bool = false) throws {
		if isRejected {
			return
		}
		if let definedParent = parent {
			unresolvedDependencies.remove(definedParent)
		}

		for (transitiveDependency, versionSpecifier) in transitiveDependencies {
			if let cachedConflict = retriever.cachedError(for: transitiveDependency, with: versionSpecifier) {
				rejectionError = cachedConflict
				return
			}

			let isUpdatable = forceUpdatable || isUpdatableDependency(transitiveDependency)
			if forceUpdatable {
				addUpdatableDependency(transitiveDependency)
			}

			let handled = try handle(dependency: transitiveDependency,
									 from: DependencyTreeVersionSpecification(parent: parent, versionSpecifier: versionSpecifier),
									 isUpdatable: isUpdatable)
			if !handled {
				// Errors were encountered, fail fast
				return
			}
		}
	}

	private func handle(dependency: Dependency, from currentSpec: DependencyTreeVersionSpecification, isUpdatable: Bool) throws -> Bool {
		let versionSpecifier = currentSpec.versionSpecifier
		let parent = currentSpec.parent
		let existingVersionSet = versions(for: dependency)

		if existingVersionSet == nil || (existingVersionSet!.isPinned && isUpdatable) {
			let validVersions = try retriever.findAllVersions(for: dependency, compatibleWith: versionSpecifier, isUpdatable: isUpdatable)

			if !setVersions(validVersions, for: dependency) {
				rejectionError = CarthageError.requiredVersionNotFound(dependency, versionSpecifier)
				retriever.setCachedError(rejectionError!, for: dependency, with: versionSpecifier)
				return false
			}

			existingVersionSet?.pinnedVersionSpecifier = nil
			validVersions.addSpec(currentSpec)
		} else if let versionSet = existingVersionSet {
			versionSet.addSpec(currentSpec)

			if !constrainVersions(for: dependency, with: versionSpecifier) {
				let hasIntersectionWithCurrentSpec: (DependencyTreeVersionSpecification) -> Bool = { spec in
					return intersection(spec.versionSpecifier, currentSpec.versionSpecifier) == nil
				}
				if let incompatibleSpec = versionSet.specs.first(where: hasIntersectionWithCurrentSpec) {
					let newRequirement: CarthageError.VersionRequirement = (specifier: versionSpecifier, fromDependency: parent)
					let existingRequirement: CarthageError.VersionRequirement = (specifier: incompatibleSpec.versionSpecifier, fromDependency: incompatibleSpec.parent)
					rejectionError = CarthageError.incompatibleRequirements(dependency, existingRequirement, newRequirement)
					if incompatibleSpec.parent == nil {
						retriever.setCachedError(rejectionError!, for: dependency, with: versionSpecifier)
					}
				} else {
					rejectionError = CarthageError.unsatisfiableDependencyList([dependency.name])
				}
				return false
			}
		}
		return true
	}
}

extension Dictionary {
	/**
	Returns the value for the specified key if it exists, else it will store the default value as created by the closure and will return that value instead.
	
	This method is useful for caches where the first time a value is instantiated it should be stored in the cache for subsequent use.
	
	Compare this to the method [_ key, default: ] which does return a default but doesn't store it in the dictionary.
	*/
	fileprivate mutating func object(for key: Dictionary.Key, byStoringDefault defaultValue: @autoclosure () throws -> Dictionary.Value) rethrows -> Dictionary.Value {
		if let v = self[key] {
			return v
		} else {
			let dv = try defaultValue()
			self[key] = dv
			return dv
		}
	}

	/**
	Transforms the values of the dictionary with the specified transform and removes all values for the transform returns nil.
	*/
	fileprivate func filterMapValues<T>(_ transform: (Dictionary.Value) throws -> T?) rethrows -> [Dictionary.Key: T] {
		var result = [Dictionary.Key: T]()
		for (key, value) in self {
			if let transformedValue = try transform(value) {
				result[key] = transformedValue
			}
		}

		return result
	}
}
