import Foundation
import Result
import ReactiveSwift

// swiftlint:disable vertical_parameter_alignment_on_call
// swiftlint:disable vertical_parameter_alignment

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

	private typealias ResolverEvaluation = (state: ResolverState, dependencySet: DependencySet)

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
			let resolverResult = try backtrack(dependencySet: dependencySet, rootDependencies: requiredDependencies.map { $0.0 })

			switch resolverResult.state {
			case .accepted:
				try resolverResult.dependencySet.eliminateSameNamedDependencies(rootEntries: requiredDependencies)
			case .rejected:
				if let rejectionError = dependencySet.rejectionError {
					throw rejectionError
				} else {
					throw CarthageError.unsatisfiableDependencyList(dependenciesToUpdate ?? dependencies.map { $0.key.name } )
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
	private func backtrack(dependencySet: DependencySet, rootDependencies: [Dependency]) throws -> (state: ResolverState, dependencySet: DependencySet) {
		if dependencySet.isRejected {
			return (.rejected, dependencySet)
		} else if dependencySet.isComplete {
			let valid = try dependencySet.validateForCyclicDepencies(rootDependencies: rootDependencies)
			if valid {
				return (.accepted, dependencySet)
			} else {
				return (.rejected, dependencySet)
			}
		}

		var result: ResolverEvaluation?
		var lastRejectionError: CarthageError?
		while result == nil {
			// Keep iterating until there are no subsets to resolve anymore
			if let subSet = try dependencySet.popSubSet() {
				let subResult = try backtrack(dependencySet: subSet, rootDependencies: rootDependencies)
				switch subResult.state {
				case .rejected:
					if subSet === dependencySet {
						result = (.rejected, subSet)
					}
					if subSet.rejectionError != nil {
						lastRejectionError = subSet.rejectionError
					}
				case .accepted:
					// Set contains all dependencies, we've got a winner
					result = (.accepted, subResult.dependencySet)
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
		return result!
	}
}
