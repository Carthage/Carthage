import Foundation

typealias DependencyEntry = (key: Dependency, value: VersionSpecifier)

// swiftlint:disable vertical_parameter_alignment_on_call
// swiftlint:disable vertical_parameter_alignment
// swiftlint:disable type_body_length

/**
Set representing a complete dependency tree with all compatible versions per dependency.

It uses ConcreteVersionSet as implementation for storing the concrete compatible versions.
*/
final class DependencySet {
	// MARK: - Properties

	/**
	The set of yet unresolved dependencies. For a complete dependency set this should be empty.
	*/
	public private(set) var unresolvedDependencies: Set<Dependency>

	/**
	The rejectionError describing the reason for rejection if any.
	*/
	public var rejectionError: CarthageError?

	/**
	Whether or not the set is rejected. No further processing necessary.
	*/
	public var isRejected: Bool {
		return rejectionError != nil
	}

	/**
	Whether or not the set is complete. No further processing necessary.
	*/
	public var isComplete: Bool {
		// Dependency resolution is complete if there are no unresolved dependencies anymore
		return unresolvedDependencies.isEmpty
	}

	/**
	True if and only if the set is not rejected and is complete.
	*/
	public var isAccepted: Bool {
		return !isRejected && isComplete
	}

	private var contents: [Dependency: ConcreteVersionSet]
	private var updatableDependencyNames: Set<String>
	private let retriever: DependencyRetriever

	// MARK: - Initializers

	public convenience init(requiredDependencies: [DependencyEntry],
							updatableDependencyNames: Set<String>,
							retriever: DependencyRetriever) throws {
		self.init(unresolvedDependencies: Set(requiredDependencies.map { $0.key }),
				  updatableDependencyNames: updatableDependencyNames,
				  contents: [Dependency: ConcreteVersionSet](),
				  retriever: retriever)
		try self.expand(parent: nil, with: requiredDependencies)
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

	// MARK: - Public methods

	/**
	Returns a copy of this set.
	*/
	public var copy: DependencySet {
		return DependencySet(
			unresolvedDependencies: unresolvedDependencies,
			updatableDependencyNames: updatableDependencyNames,
			contents: contents.mapValues { $0.copy },
			retriever: retriever)
	}

	/**
	Returns all resolved dependencies as a dictionary.
	*/
	public var resolvedDependencies: [Dependency: PinnedVersion] {
		return contents.filterMapValues { $0.first?.pinnedVersion }
	}

	/**
	Returns the next unresolved dependency for processing. The dependency returned is the dependency with the highest likelyhood of producing a conflict.
	*/
	public var nextUnresolvedDependency: Dependency? {
		return retriever.problematicDependencies.first { unresolvedDependencies.contains($0) } ?? unresolvedDependencies.first
	}

	/**
	The currently resolved versions for the specified dependency.
	*/
	public func versions(for dependency: Dependency) -> ConcreteVersionSet? {
		return contents[dependency]
	}

	/**
	Whether or not this set contains the specified dependency.
	*/
	public func containsDependency(_ dependency: Dependency) -> Bool {
		return contents[dependency] != nil
	}

	/**
	Whether or not the specified dependency is updatable.
	*/
	public func isUpdatableDependency(_ dependency: Dependency) -> Bool {
		return updatableDependencyNames.isEmpty || updatableDependencyNames.contains(dependency.name)
	}

	/**
	Pops a subset of this set for further processing, by taking the next most appropriate unresolved dependency.

	Basically this singles out one concrete version for this unresolved dependency and removes this exact versioned dependency from the receiver,
	while returning a copy with that version for that dependency.

	Example: say the next unresolved dependency is A with versions [1.1, 1.2, 1.3, 1.4]. Then after this operation the receiver would contain versions:
	[1.1, 1.2, 1.3] and the returned copy would contain version [1.4].

	If there was already exactly one version for the dependency, no copy is returned but the receiver itself.

	If there was no further subset to process (no unresolved dependencies or the receiver is already rejected), nil is returned.
	*/
	public func popSubSet() throws -> DependencySet? {
		while !isComplete && !isRejected {
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
							// Rejected, no versions left
							newSet.rejectionError = cachedConflict.error
							break
						}
					}
				}

				if !newSet.isRejected {
					if try newSet.expand(parent: ConcreteVersionedDependency(dependency: dependency, concreteVersion: version),
										 with: try retriever.findDependencies(for: dependency, version: version),
										 forceUpdatable: isUpdatableDependency(dependency)) {
						newSet.unresolvedDependencies.remove(dependency)
					}
				}
				return newSet
			}
		}

		return nil
	}

	/**
	Validates this set for cyclic dependencies.

	Returns true if valid, false otherwise (which means a cycle has been encountered).
	The rejectionError for the set will be set in case a cycle was encountered.
	*/
	public func validateForCyclicDepencies(rootDependencies: [Dependency]) throws -> Bool {
		var stack = [Dependency: Set<Dependency>]()
		let foundCycle = try hasCycle(for: rootDependencies, parent: nil, stack: &stack)
		if foundCycle {
			rejectionError = CarthageError.dependencyCycle(stack)
		}
		return !foundCycle
	}

	/**
	Eliminates dependencies with duplicate names, keeping the most relevant once.

	The carthage model does not allow two dependencies with the same name, this is because forks should be allowed to override their upstreams.
	*/
	public func eliminateSameNamedDependencies(rootEntries: [DependencyEntry]) throws {
		var names = Set<String>()
		var duplicatedDependencyNames = Set<String>()
		var versionSpecifiers = [Dependency: VersionSpecifier]()

		for entry in rootEntries {
			versionSpecifiers[entry.key] = entry.value
		}

		// Check for dependencies with the same name and store them in the duplicatedDependencyNames set
		for (dependency, _) in contents {
			let result = names.insert(dependency.name)
			if !result.inserted {
				duplicatedDependencyNames.insert(dependency.name)
			}
		}

		// For the duplicatedDependencyNames: ensure only the dependency with the highest precedence versionSpecifier remains
		for name in duplicatedDependencyNames {
			let sameNamedDependencies = contents.compactMap { entry -> (dependency: Dependency, versionSpecifier: VersionSpecifier?)? in
				let dependency = entry.key
				if dependency.name == name {
					return (dependency, versionSpecifiers[dependency])
				} else {
					return nil
				}
				}.sorted { entry1, entry2 -> Bool in
					let precedence1 = (entry1.versionSpecifier?.precedence ?? 0)
					let precedence2 = (entry2.versionSpecifier?.precedence ?? 0)
					return precedence1 > precedence2
			}

			if sameNamedDependencies.count > 1 && (sameNamedDependencies[0].versionSpecifier == nil || sameNamedDependencies[1].versionSpecifier != nil) {
				// Cannot determine precedence: report an error.
				// Requires a specific versionSpecifier for exactly one of these dependencies in the root Cartfile.
				let error = CarthageError.incompatibleDependencies(sameNamedDependencies.map { $0.dependency })
				throw error
			}

			for i in 1..<sameNamedDependencies.count {
				let dependency = sameNamedDependencies[i].dependency
				contents[dependency] = nil
			}
		}
	}

	// MARK: - Private methods

	/**
	Returns a rejected copy of this set, which is basically an empty set with the rejectionError set.
	*/
	private func rejectedCopy(rejectionError: CarthageError) -> DependencySet {
		let dependencySet = DependencySet(unresolvedDependencies: Set<Dependency>(),
										  updatableDependencyNames: Set<String>(),
										  contents: [Dependency: ConcreteVersionSet](),
										  retriever: self.retriever)
		dependencySet.rejectionError = rejectionError
		return dependencySet
	}

	private func removeVersion(_ version: ConcreteVersion, for dependency: Dependency) -> Bool {
		if let versionSet = contents[dependency] {
			versionSet.remove(version)
			return !versionSet.isEmpty
		}
		return false
	}

	private func setVersions(_ versions: ConcreteVersionSet, for dependency: Dependency) -> Bool {
		contents[dependency] = versions
		return !versions.isEmpty
	}

	private func removeAllVersionsExcept(_ version: ConcreteVersion, for dependency: Dependency) -> Bool {
		if let versionSet = versions(for: dependency) {
			versionSet.removeAll(except: version)
			return !versionSet.isEmpty
		}
		return false
	}

	private func constrainVersions(for dependency: Dependency, with versionSpecifier: VersionSpecifier) -> Bool {
		if let versionSet = versions(for: dependency) {
			versionSet.retainVersions(compatibleWith: versionSpecifier)
			return !versionSet.isEmpty
		}
		return false
	}

	private func addUpdatableDependency(_ dependency: Dependency) {
		if !updatableDependencyNames.isEmpty {
			updatableDependencyNames.insert(dependency.name)
		}
	}

	/**
	Expands this set by iterating over the transitive dependencies and processing them.
	*/
	@discardableResult
	private func expand(parent: ConcreteVersionedDependency?, with transitiveDependencies: [DependencyEntry], forceUpdatable: Bool = false) throws -> Bool {
		for (transitiveDependency, versionSpecifier) in transitiveDependencies {
			let isUpdatable = forceUpdatable || isUpdatableDependency(transitiveDependency)
			if forceUpdatable {
				addUpdatableDependency(transitiveDependency)
			}

			guard try process(transitiveDependency: transitiveDependency,
							  definedBy: ConcreteVersionSetDefinition(definingDependency: parent, versionSpecifier: versionSpecifier),
							  isUpdatable: isUpdatable) == true else {
								// Errors were encountered, fail fast
								return false
			}
		}
		return true
	}

	/**
	Rejects this set with the specified error.
	*/
	private func reject(dependency: Dependency, error: CarthageError,
						definingDependency: ConcreteVersionedDependency? = nil,
						conflictingWith conflictingDependency: ConcreteVersionedDependency? = nil) {
		rejectionError = error
		if let nonNilDefiningDependency = definingDependency {
			retriever.addCachedConflict(for: nonNilDefiningDependency, conflictingWith: conflictingDependency, error: error)
		}
		retriever.addProblematicDependency(dependency)
	}

	/**
	Processes a transitive dependency.
	*/
	private func process(transitiveDependency: Dependency, definedBy definition: ConcreteVersionSetDefinition, isUpdatable: Bool) throws -> Bool {
		let versionSpecifier = definition.versionSpecifier
		let definingDependency = definition.definingDependency
		let existingVersionSet = versions(for: transitiveDependency)

		if existingVersionSet == nil || (existingVersionSet!.isPinned && isUpdatable) {
			let validVersions = try retriever.findAllVersions(for: transitiveDependency, compatibleWith: versionSpecifier, isUpdatable: isUpdatable)

			if !setVersions(validVersions, for: transitiveDependency) {
				let error = CarthageError.requiredVersionNotFound(transitiveDependency, versionSpecifier)
				reject(dependency: transitiveDependency, error: error, definingDependency: definingDependency)
				return false
			}

			unresolvedDependencies.insert(transitiveDependency)
			existingVersionSet?.pinnedVersionSpecifier = nil
			validVersions.addDefinition(definition)
		} else if let versionSet = existingVersionSet {
			defer {
				versionSet.addDefinition(definition)
			}

			if !constrainVersions(for: transitiveDependency, with: versionSpecifier) {
				assert(!versionSet.definitions.isEmpty, "Expected definitions to not be empty")
				if let incompatibleDefinition = versionSet.conflictingDefinition(for: versionSpecifier) {
					let existingRequirement: CarthageError.VersionRequirement = (specifier: incompatibleDefinition.versionSpecifier,
																				 fromDependency: incompatibleDefinition.definingDependency?.dependency)
					let newRequirement: CarthageError.VersionRequirement = (specifier: versionSpecifier,
																			fromDependency: definition.definingDependency?.dependency)
					let error = CarthageError.incompatibleRequirements(transitiveDependency, existingRequirement, newRequirement)

					reject(dependency: transitiveDependency, error: error, definingDependency: definition.definingDependency,
						   conflictingWith: incompatibleDefinition.definingDependency)
				} else {
					reject(dependency: transitiveDependency, error: CarthageError.unsatisfiableDependencyList(Array(updatableDependencyNames)))
				}
				return false
			}
		}
		return true
	}

	/**
	Check for a completely resolved set, whether there are no cyclic dependencies.
	*/
	private func hasCycle(for dependencies: [Dependency], parent: Dependency?, stack: inout [Dependency: Set<Dependency>]) throws -> Bool {
		if let definedParent = parent {
			if stack[definedParent] == nil {
				stack[definedParent] = Set(dependencies)
			} else {
				return true
			}
		}

		for dependency in dependencies {
			if let versionSet = contents[dependency] {
				// Only check the most appropriate version
				if let version = versionSet.first {
					let transitiveDependencies = try retriever.findDependencies(for: dependency, version: version).map { $0.0 }
					if try hasCycle(for: transitiveDependencies, parent: dependency, stack: &stack) {
						return true
					}
				}
			}
		}

		if let definedParent = parent {
			stack[definedParent] = nil
		}
		return false
	}
}

extension VersionSpecifier {
	/**
	Precedence for sorting VersionSpecifiers with decreasing specifics (The more specific the specifier the higher the precedence).
	*/
	fileprivate var precedence: Int {
		switch self {
		case .gitReference:
			return 5
		case .exactly:
			return 4
		case .compatibleWith:
			return 3
		case .atLeast:
			return 2
		case .any:
			return 1
		}
	}
}
