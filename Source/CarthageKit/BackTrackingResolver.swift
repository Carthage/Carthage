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
		let requiredDependencies: [DependencyEntry]
		let hasSpecificDepedenciesToUpdate = !updatableDependencyNames.isEmpty

		if hasSpecificDepedenciesToUpdate {
			requiredDependencies = dependencies.filter { dependency, _ in
				updatableDependencyNames.contains(dependency.name) || pinnedVersions[dependency] != nil
			}
		} else {
			requiredDependencies = Array(dependencies)
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
		var lastRejectionError: CarthageError? = nil
		while result == nil {
			// Keep iterating until there are no subsets to resolve anymore
			if let subSet = try dependencySet.popSubSet() {
				if subSet.isRejected {
					if subSet === dependencySet {
						result = (.rejected, subSet)
					}
					if subSet.rejectionError != nil {
						lastRejectionError = subSet.rejectionError
					}
				} else {
					// Backtrack again with this subset
					let nestedResult = try backtrack(dependencySet: subSet)
					switch nestedResult.state {
					case .rejected:
						if subSet === dependencySet {
							result = (.rejected, subSet)
						}
						if subSet.rejectionError != nil {
							lastRejectionError = subSet.rejectionError
						}
					case .accepted:
						// Set contains all dependencies, we've got a winner
						result = (.accepted, nestedResult.dependencySet)
					}
				}
				
			} else {
				// All done
				result = (.rejected, dependencySet)
				if dependencySet.rejectionError == nil {
					dependencySet.rejectionError = lastRejectionError
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

private final class DependencyConflict {
	// Error for the conflict
	let error: CarthageError
	
	// Nil array means: conflict with root level definition
	var conflictingDependencies: [ConcreteVersionedDependency]? = nil
	
	init(error: CarthageError, conflictingDependency: ConcreteVersionedDependency? = nil) {
		self.error = error
		if let nonNilConflictingDependency = conflictingDependency {
			conflictingDependencies = [nonNilConflictingDependency]
		}
	}
	
	public func addConflictingDependency(_ conflictingDependency: ConcreteVersionedDependency?) {
		if let nonNilConflictingDependency = conflictingDependency {
			conflictingDependencies?.append(nonNilConflictingDependency)
		} else {
			conflictingDependencies = nil
		}
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
	private var versionsCache = [DependencyVersionSpec: ConcreteVersionSet]()
	private var conflictCache = [PinnedDependency: DependencyConflict]()
	public private(set) var problematicDependencies = Set<Dependency>()

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

	public func findDependencies(for dependency: Dependency, version: ConcreteVersion) throws -> [DependencyEntry] {
		let pinnedDependency = PinnedDependency(dependency: dependency, pinnedVersion: version.pinnedVersion)
		var result: [DependencyEntry] = try dependencyCache.object(
			for: pinnedDependency,
			byStoringDefault: try dependenciesForDependency(dependency, version.pinnedVersion).collect().first()!.dematerialize()
		)
		
		// Sort according to relevance for faster processing: always process problematic dependencies first
		if !problematicDependencies.isEmpty {
			result.sort { (entry1, entry2) -> Bool in
				if problematicDependencies.contains(entry1.key) && !problematicDependencies.contains(entry2.key) {
					return true
				} else {
					return false
				}
			}
		}

		return result
	}

	public func addCachedConflict(for dependency: ConcreteVersionedDependency, conflictingWith conflictingDependency: ConcreteVersionedDependency? = nil, error: CarthageError) {
		storeCachedConflict(for: dependency, conflictingWith: conflictingDependency, error: error)
		
		// Add the inverse as well
		if let nonNilConflictingDependency = conflictingDependency {
			storeCachedConflict(for: nonNilConflictingDependency, conflictingWith: dependency, error: error)
		}
	}
	
	private func storeCachedConflict(for dependency: ConcreteVersionedDependency, conflictingWith conflictingDependency: ConcreteVersionedDependency? = nil, error: CarthageError) {
		let key = PinnedDependency(dependency: dependency.dependency, pinnedVersion: dependency.concreteVersion.pinnedVersion)
		
		if let existingConflict = conflictCache[key] {
			existingConflict.addConflictingDependency(conflictingDependency)
		} else {
			conflictCache[key] = DependencyConflict(error: error, conflictingDependency: conflictingDependency)
		}
		addProblematicDependency(dependency.dependency)
	}
	
	public func cachedConflict(for dependency: ConcreteVersionedDependency) -> DependencyConflict? {
		let key = PinnedDependency(dependency: dependency.dependency, pinnedVersion: dependency.concreteVersion.pinnedVersion)
		return conflictCache[key]
	}
	
	public func addProblematicDependency(_ dependency: Dependency) {
		problematicDependencies.insert(dependency)
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

	public var rejectionError: CarthageError?

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
	
	public var nextUnresolvedDependency: Dependency? {
		let problematicDependencies = retriever.problematicDependencies
		
		if problematicDependencies.count < unresolvedDependencies.count {
			for problematicDependency in problematicDependencies {
				if unresolvedDependencies.contains(problematicDependency) {
					return problematicDependency
				}
			}
		} else {
			for unresolvedDependency in unresolvedDependencies {
				if problematicDependencies.contains(unresolvedDependency) {
					return unresolvedDependency
				}
			}
		}
		return unresolvedDependencies.first
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

	convenience init(requiredDependencies: [DependencyEntry],
							updatableDependencyNames: Set<String>,
							retriever: DependencyRetriever) throws {
		self.init(unresolvedDependencies: Set(requiredDependencies.map { $0.key }),
				  updatableDependencyNames: updatableDependencyNames,
				  contents: [Dependency: ConcreteVersionSet](),
				  retriever: retriever)
		try self.expand(parent: nil, with: requiredDependencies)
	}
	
	public func rejectedCopy(rejectionError: CarthageError) -> DependencySet {
		let dependencySet = DependencySet(unresolvedDependencies: Set<Dependency>(), updatableDependencyNames: Set<String>(), contents: [Dependency: ConcreteVersionSet](), retriever: self.retriever)
		dependencySet.rejectionError = rejectionError
		return dependencySet
	}

	public func removeVersion(_ version: ConcreteVersion, for dependency: Dependency) -> Bool {
		if let versionSet = contents[dependency] {
			versionSet.remove(version)
			return !versionSet.isEmpty
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
		while !unresolvedDependencies.isEmpty && !isRejected {
			if let dependency = self.nextUnresolvedDependency {
				// Select the first version, which is also the most appropriate version (highest version corresponding with version specifier)
				guard let versionSet = contents[dependency], let version = versionSet.first else {
					// Empty version set for this dependency, so there's no more subsets to consider
					return nil
				}
				
				let concreteVersionedDependency = ConcreteVersionedDependency(dependency: dependency, concreteVersion: version)
				let optionalCachedConflict = retriever.cachedConflict(for: concreteVersionedDependency)
				let newSet: DependencySet
				
				if let cachedConflict = optionalCachedConflict, cachedConflict.conflictingDependencies == nil {
					// Conflicts with the root level definitions: immediately exit with error
					_ = removeVersion(version, for: dependency)
					newSet = rejectedCopy(rejectionError: cachedConflict.error)
					return newSet
				}
				
				// Remove all versions except the selected version if needed. If the number of versions is already 1, we don't need a copy.
				let count = versionSet.count
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
				
				// Check for cached conflicts
				if let cachedConflict = optionalCachedConflict, let conflictingDependencies = cachedConflict.conflictingDependencies {
					// Remove all conflicting dependencies from this set
					for concreteDependency in conflictingDependencies {
						if newSet.removeVersion(concreteDependency.concreteVersion, for: concreteDependency.dependency) == false {
							// Rejected
							newSet.rejectionError = CarthageError.unsatisfiableDependencyList([concreteDependency.dependency.name])
							break
						}
					}
				}
				
				if !newSet.isRejected {
					if try newSet.expand(parent: ConcreteVersionedDependency(dependency: dependency, concreteVersion: version), with: try retriever.findDependencies(for: dependency, version: version), forceUpdatable: isUpdatableDependency(dependency)) {
						newSet.unresolvedDependencies.remove(dependency)
					}
				}
				return newSet
			}
		}

		return nil
	}

	@discardableResult
	public func expand(parent: ConcreteVersionedDependency?, with transitiveDependencies: [DependencyEntry], forceUpdatable: Bool = false) throws -> Bool {
		for (transitiveDependency, versionSpecifier) in transitiveDependencies {
			let isUpdatable = forceUpdatable || isUpdatableDependency(transitiveDependency)
			if forceUpdatable {
				addUpdatableDependency(transitiveDependency)
			}

			guard try process(dependency: transitiveDependency,
							  definedBy: ConcreteVersionSetDefinition(definingDependency: parent, versionSpecifier: versionSpecifier),
							  isUpdatable: isUpdatable) == true else {
				// Errors were encountered, fail fast
				return false
			}
		}
		return true
	}

	private func process(dependency: Dependency, definedBy definition: ConcreteVersionSetDefinition, isUpdatable: Bool) throws -> Bool {
		let versionSpecifier = definition.versionSpecifier
		let definingDependency = definition.definingDependency
		let existingVersionSet = versions(for: dependency)
		
		if existingVersionSet == nil || (existingVersionSet!.isPinned && isUpdatable) {
			let validVersions = try retriever.findAllVersions(for: dependency, compatibleWith: versionSpecifier, isUpdatable: isUpdatable)

			if !setVersions(validVersions, for: dependency) {
				let error = CarthageError.requiredVersionNotFound(dependency, versionSpecifier)
				rejectionError = error
				if let nonNilDefiningDependency = definingDependency {
					retriever.addCachedConflict(for: nonNilDefiningDependency, error: error)
				}
				retriever.addProblematicDependency(dependency)
				return false
			}

			existingVersionSet?.pinnedVersionSpecifier = nil
			validVersions.addDefinition(definition)
		} else if let versionSet = existingVersionSet {
			versionSet.addDefinition(definition)

			if !constrainVersions(for: dependency, with: versionSpecifier) {
				let hasIntersectionWithCurrentSpec: (ConcreteVersionSetDefinition) -> Bool = { spec in
					return intersection(spec.versionSpecifier, definition.versionSpecifier) == nil
				}
				if let incompatibleDefinition = versionSet.definitions.first(where: hasIntersectionWithCurrentSpec) {
					let newRequirement: CarthageError.VersionRequirement = (specifier: versionSpecifier, fromDependency: definition.definingDependency?.dependency)
					let existingRequirement: CarthageError.VersionRequirement = (specifier: incompatibleDefinition.versionSpecifier, fromDependency: incompatibleDefinition.definingDependency?.dependency)
					let error = CarthageError.incompatibleRequirements(dependency, existingRequirement, newRequirement)
					rejectionError = error
					if let nonNilDefiningDependency = definition.definingDependency {
						retriever.addCachedConflict(for: nonNilDefiningDependency, conflictingWith: incompatibleDefinition.definingDependency, error: error)
					}
					retriever.addProblematicDependency(dependency)
				} else {
					rejectionError = CarthageError.unsatisfiableDependencyList([dependency.name])
					retriever.addProblematicDependency(dependency)
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
