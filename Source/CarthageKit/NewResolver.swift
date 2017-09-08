import Foundation
import Result
import ReactiveSwift

/// Responsible for resolving acyclic dependency graphs.
public struct NewResolver: ResolverProtocol {
	private let versionsForDependency: (Dependency) -> SignalProducer<PinnedVersion, CarthageError>
	private let resolvedGitReference: (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
	private let dependenciesForDependency: (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>

	/// Instantiates a dependency graph resolver with the given behaviors.
	///
	/// versionsForDependency - Sends a stream of available versions for a
	///                         dependency.
	/// dependenciesForDependency - Loads the dependencies for a specific
	///                             version of a dependency.
	/// resolvedGitReference - Resolves an arbitrary Git reference to the
	///                        latest object.
	public init(
		versionsForDependency: @escaping (Dependency) -> SignalProducer<PinnedVersion, CarthageError>,
		dependenciesForDependency: @escaping (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>,
		resolvedGitReference: @escaping (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
	) {
		self.versionsForDependency = versionsForDependency
		self.dependenciesForDependency = dependenciesForDependency
		self.resolvedGitReference = resolvedGitReference
	}

	/// Attempts to determine the latest valid version to use for each
	/// dependency in `dependencies`, and all nested dependencies thereof.
	///
	/// Sends a dictionary with each dependency and its resolved version.
	public func resolve(
		dependencies: [Dependency: VersionSpecifier],
		lastResolved: [Dependency: PinnedVersion]? = nil,
		dependenciesToUpdate: [String]? = nil
		) -> SignalProducer<[Dependency: PinnedVersion], CarthageError> {
		let result = process(dependencies: dependencies, in: DependencyGraph(whitelist: dependenciesToUpdate, lastResolved: lastResolved))
			.map { graph in graph.versions }

		return SignalProducer(result: result)
	}

	/// Error cache for used for this instance of the resolver
	private let errorCache = ErrorCache()

	/// Produces a lazily computed sequence of valid permutations of `dependencies`
	/// taking into account previously seen errors, in the order they should be tried.
	///
	/// The sequence produces 'DependencyGraph's with `dependencies` added. Each graph
	/// represents one possible permutation of those dependencies
	/// (chosen from among the versions that actually exist for each).
	private func nodePermutations(
		for dependencies: [Dependency: VersionSpecifier],
		in basisGraph: DependencyGraph,
		withParent parentNode: DependencyNode?
		) -> Result<NodePermutations, CarthageError> {
		return SignalProducer<(key: Dependency, value: VersionSpecifier), CarthageError>(dependencies)
			.flatMap(.concat) { (dependency, specifier) -> SignalProducer<[DependencyNode], CarthageError> in
				let versionProducer: SignalProducer<PinnedVersion, CarthageError>
				if case let .gitReference(refName) = specifier {
					versionProducer = self.resolvedGitReference(dependency, refName)
				} else {
					versionProducer = self.versionsForDependency(dependency)
						.filter { specifier.isSatisfied(by: $0) }
				}

				return versionProducer
					.map { DependencyNode(dependency: dependency, proposedVersion: $0, versionSpecifier: specifier, parent: parentNode) }
					.collect()
					.attemptMap { nodes in
						guard !nodes.isEmpty else {
							return .failure(CarthageError.requiredVersionNotFound(dependency, specifier))
						}
						return .success(nodes.sorted())
					}
			}
			.collect()
			.map { nodesToPermute -> NodePermutations in
				return NodePermutations(
					basisGraph: basisGraph,
					nodesToPermute: nodesToPermute,
					errorCache: self.errorCache)
			}
			.first()!
	}

	/// Permutes `dependencies`, attaching each permutation to `basisGraph`, as a dependency of the
	/// specified node (or as a root otherwise). It then recursively processes each graph
	///
	/// This is a helper method, and not meant to be called from outside.
	private func process(
		dependencies: [Dependency: VersionSpecifier],
		in basisGraph: DependencyGraph,
		withParent parent: DependencyNode? = nil
		) -> Result<DependencyGraph, CarthageError> {
		return self.nodePermutations(for: dependencies, in: basisGraph, withParent: parent)
			.flatMap { permutations in
				// Only throw an error if no valid graph was produced by any of the permutations
				var errResult: Result<DependencyGraph, CarthageError>? = nil
				for nextGraphResult in permutations {
					// Immediately fail if graph creation fails
					guard case let .success(nextGraph) = nextGraphResult else { return errResult! }

					let nextResult = self.process(graph: nextGraph)
					switch nextResult {
					case .success:
						return nextResult
					case .failure:
						errResult = errResult ?? nextResult
					}
				}
				return errResult!
			}
	}

	/// Processes the next unvisited node in the graph.
	/// It produces the available versions for the given node, then recursively
	/// performs permutations across those versions
	///
	/// This is a helper method, and not meant to be called from outside.
	private func process(graph: DependencyGraph) -> Result<DependencyGraph, CarthageError> {
		var graph = graph
		guard let node = graph.nextNodeToVisit() else {
			// Base case, all nodes have been visited. Return valid graph
			return graph.validateFinalGraph()
		}

		return self.dependenciesForDependency(node.dependency, node.proposedVersion)
			.attempt { (child, newSpecifier) -> Result<(), CarthageError> in
				// If we haven't added this dependency yet, succeed
				guard let existingChildNode = graph.node(for: child) else {
					return .success(())
				}

				// Check if the previously pinned version satisfies the additional specifier
				guard newSpecifier.isSatisfied(by: existingChildNode.proposedVersion) else {
					// If the specifier is completely incompatible with the existing one,
					// add it to the error cache
					if intersection(newSpecifier, existingChildNode.versionSpecifier) == nil {
						if let existingParent = existingChildNode.parent {
							self.errorCache.addIncompatibilityBetween((node.dependency, node.proposedVersion), (existingParent.dependency, existingParent.proposedVersion))
						} else {
							self.errorCache.addRootIncompatibility(for: (node.dependency, node.proposedVersion))
						}
					}
					let existingReqs: CarthageError.VersionRequirement = (specifier: existingChildNode.versionSpecifier, fromDependency: existingChildNode.parent?.dependency)
					let newReqs: CarthageError.VersionRequirement = (specifier: newSpecifier, fromDependency: node.dependency)
					return .failure(.incompatibleRequirements(child, existingReqs, newReqs))
				}

				return .success(())
			}
			.filter { childDependency, _ in
				// Only run permutations on nodes not already pinned to the graph
				graph.node(for: childDependency) == nil
			}
			.reduce([:]) { curDict, childDependencyTuple in
				var curDict = curDict
				curDict[childDependencyTuple.0] = childDependencyTuple.1
				return curDict
			}
			.concat(value: [:])
			.take(first: 1)
			.first()!
			.flatMap { (dependencies: [Dependency: VersionSpecifier]) in
				return self.process(dependencies: dependencies, in: graph, withParent: node)
			}
	}
}

/// Represents an acyclic dependency graph in which each project appears at most
/// once.
///
/// Dependency graphs can exist in an incomplete or inconsistent state, representing a search
/// in progress.
private struct DependencyGraph {
	/// A full list of all nodes included in the graph.
	var allNodes: Set<DependencyNode> = []

	/// All nodes that have dependencies, associated with those lists of
	/// dependencies themselves including the intermediates.
	var edges: [DependencyNode: Set<DependencyNode>] = [:]

	/// List of nodes that still need to be processed, in the order they should be processed
	var unvisitedNodes: [DependencyNode] = []

	/// Whitelist of dependencies to limit updates to. Once a valid graph is found,
	/// the nodes are filtered down to this list. Remaining nodes are given the values found in 'lastResolved'.
	/// The graph is then re-checked for validity. If it's now invalid due to the whitelist, the search is continued
	let whitelist: [String]?
	let lastResolved: [Dependency: PinnedVersion]?

	init(whitelist: [String]?, lastResolved: [Dependency: PinnedVersion]? = nil) {
		self.whitelist = whitelist
		self.lastResolved = lastResolved
	}

	/// A dictionary defining all the versions that are pinned in this graph.
	var versions: [Dependency: PinnedVersion] {
		var versionDictionary: [Dependency: PinnedVersion] = [:]
		for node in allNodes {
			versionDictionary[node.dependency] = node.proposedVersion
		}
		return versionDictionary
	}

	/// Returns the next unvisited node if available
	mutating func nextNodeToVisit() -> DependencyNode? {
		return !unvisitedNodes.isEmpty ? unvisitedNodes.removeFirst() : nil
	}

	/// Runs final validation against the whitelist on a complete graph (e.g., no more unvisited nodes)
	///
	/// For every node that is not in the whitelist or its dependencies
	/// - If it has a version in 'lastResolved', it must match, or an unsatisfiableDependencyList error is returned
	/// - If the node has no previous version, it will be removed from the returned graph, but the graph is still considered valid
	func validateFinalGraph() -> Result<DependencyGraph, CarthageError> {
		guard unvisitedNodes.isEmpty else {
			return .failure(.internalError(description: "Validating graph before it's been completely expanded"))
		}

		guard let whitelist = whitelist, !whitelist.isEmpty, let lastResolved = lastResolved else {
			return .success(self)
		}

		// Any dependencies of items in the whitelist are also allowed to update
		var nodeWhitelist = Set<DependencyNode>()
		allNodes
			.filter { whitelist.contains($0.dependency.name) }
			.forEach { node in
				nodeWhitelist.insert(node)
				if let nestedDependencies = edges[node] {
					nodeWhitelist.formUnion(nestedDependencies)
				}
			}

		var filteredGraph = self
		for node in allNodes {
			guard !nodeWhitelist.contains(node) else {
				continue
			}

			guard let lastVersion = lastResolved[node.dependency] else {
				// If it doesn't have a previous version, and isn't in the whitelist, remove it from the returned graph
				filteredGraph.allNodes.remove(node)
				filteredGraph.edges.removeValue(forKey: node)
				continue
			}

			// If it's not in the whitelist, and it has a previous version, they should match
			if lastVersion != node.proposedVersion {
				return .failure(.unsatisfiableDependencyList(whitelist))
			}
		}
		return .success(filteredGraph)
	}

	/// Returns the current node for a given dependency, if contained in the graph
	func node(for dependency: Dependency) -> DependencyNode? {
		return allNodes.first { $0.dependency == dependency }
	}

	/// Adds the given node to the graph
	///
	/// Adds the node to the unvisited nodes list
	mutating func addNode(_ node: DependencyNode) -> Result<(), CarthageError> {
		guard !allNodes.contains(node) else {
			let failureMsg = "Attempted to add node \(node), but it already exists in the dependency graph."
				+ "This is an error in carthage, please file an issue\n\033[4mhttps://github.com/Carthage/Carthage/issues/new\033[0m\n"
			return .failure(.internalError(description: failureMsg))
		}

		allNodes.insert(node)
		unvisitedNodes.append(node)

		if let dependencyOf = node.parent {
			var nodeSet = edges[dependencyOf] ?? Set()
			nodeSet.insert(node)

			// If the given node has its dependencies, add them also to the list.
			if let dependenciesOfNode = edges[node] {
				nodeSet.formUnion(dependenciesOfNode)
			}

			edges[dependencyOf] = nodeSet

			// Add a nested dependency to the list of its ancestor.
			let edgesCopy = edges
			for (ancestor, var itsDependencies) in edgesCopy {
				if itsDependencies.contains(dependencyOf) {
					itsDependencies.formUnion(nodeSet)
					edges[ancestor] = itsDependencies
				}
			}
		}

		return .success()
	}

	/// Adds the given nodes to the graph
	///
	/// Adds the nodes to the unvisited nodes list, in the order given
	/// Returns self if successful
	mutating func addNodes
		<C: Collection>
		(_ nodes: C) -> Result<DependencyGraph, CarthageError>
		where C.Iterator.Element == DependencyNode {
			for node in nodes {
				switch self.addNode(node) {
				case .success:
					continue
				case let .failure(error):
					return Result(error: error)
				}
			}

			return .success(self)
	}
}

/// Custom iterator to perform permutations. Used in tandem with the `ErrorCache', 
/// allowing us to short circuit permutations before generating them, rather than
/// filtering results as they come.
private struct NodePermutations: Sequence, IteratorProtocol {
	private let basisGraph: DependencyGraph
	private let nodesToPermute: [[DependencyNode]]
	private let errorCache: ErrorCache
	private var currentPermutation: [Int] // Array of current indexes into pinned version arrays
	private var hasNext = true

	/// Instantiates a permutation sequence for `nodesToPermute`. Each permutation
	/// creates a new graph from `basisGraph`, with the nodes added to the graph.
	init(
		basisGraph: DependencyGraph,
		nodesToPermute: [[DependencyNode]],
		errorCache: ErrorCache
	) {
		self.basisGraph = basisGraph
		self.nodesToPermute = nodesToPermute
		self.errorCache = errorCache
		currentPermutation = Array(repeatElement(0, count: nodesToPermute.count))
	}

	/// Generates the next permutation, skipping over any combinations which are deemed
	/// invalid by the error cache
	mutating func next() -> Result<DependencyGraph, CarthageError>? {
		guard hasNext else { return nil }

		// In case incompatibilities came in for a higher level in the recursion, skip the entire sequence
		guard errorCache.graphIsValid(basisGraph) else { return nil }

		guard let graph = nextValidGraph() else { return nil }

		incrementIndexes()
		return graph
	}

	/// Creates a new graph from the indexes stored in the permutation array
	private func generateGraph() -> Result<DependencyGraph, CarthageError> {
		var newGraph = basisGraph
		let newNodes = currentPermutation.enumerated().map { dependencyIdx, nodeIdx -> DependencyNode in
			let nodes = nodesToPermute[dependencyIdx]
			return nodes[nodeIdx]
		}

		return newGraph.addNodes(newNodes)
	}

	/// Generates the next valid graph, skipping over invalid permutations
	/// Returns an error if any graph generation results in an error
	private mutating func nextValidGraph() -> Result<DependencyGraph, CarthageError>? {
		var result: Result<DependencyGraph, CarthageError>? = nil
		// Skip any invalid permutations
		while hasNext && result == nil {
			result = generateGraph()
			guard case let .success(generatedGraph) = generateGraph() else { break }

			let versions = generatedGraph.versions
			for i in (0..<currentPermutation.count).reversed() {
				let nodes = nodesToPermute[i]
				let node = nodes[currentPermutation[i]]
				if !errorCache.dependencyIsValid(node.dependency, given: versions) {
					incrementIndexes(startingAt: i)
					result = nil
					break
				}
			}
		}

		return result
	}

	/// Basic permutation increment
	private mutating func incrementIndexes(startingAt startingIndex: Int? = nil) {
		guard hasNext else { return }

		// 'skip' any permutations as defined by 'startingIndex' by setting all subsequent values to their max. We don't count this as an 'incremented' occurrence.
		if let startingIndex = startingIndex {
			for i in (startingIndex + 1..<currentPermutation.count) {
				let nodes = nodesToPermute[i]
				currentPermutation[i] = nodes.count - 1
			}
		}

		var incremented = false
		for i in (0..<currentPermutation.count).reversed() {
			let nodeIndex = currentPermutation[i]
			let nodes = nodesToPermute[i]
			if nodeIndex == nodes.count - 1 {
				currentPermutation[i] = 0
			} else {
				currentPermutation[i] = nodeIndex + 1
				incremented = true
				break
			}
		}
		hasNext = incremented
	}
}

/// A node in, or being considered for, an acyclic dependency graph.
private final class DependencyNode {
	/// The dependency that this node refers to.
	let dependency: Dependency

	/// The current requirements this dependency node was created from
	var versionSpecifier: VersionSpecifier

	/// The parent node where versionSpecifier was sourced from
	var parent: DependencyNode?

	/// The dependencies of this node.
	var dependencies: Set<DependencyNode> = []

	/// The version of the dependency that this node represents.
	///
	/// This version is merely "proposed" because it depends on the final
	/// resolution of the graph, as well as whether any "better" graphs exist.
	let proposedVersion: PinnedVersion

	init(dependency: Dependency, proposedVersion: PinnedVersion, versionSpecifier: VersionSpecifier, parent: DependencyNode?) {
		precondition(versionSpecifier.isSatisfied(by: proposedVersion))

		self.dependency = dependency
		self.proposedVersion = proposedVersion
		self.versionSpecifier = versionSpecifier
		self.parent = parent
	}
}

extension DependencyNode: Comparable {
	fileprivate static func < (_ lhs: DependencyNode, _ rhs: DependencyNode) -> Bool {
		let leftSemantic = SemanticVersion.from(lhs.proposedVersion).value ?? SemanticVersion(major: 0, minor: 0, patch: 0)
		let rightSemantic = SemanticVersion.from(rhs.proposedVersion).value ?? SemanticVersion(major: 0, minor: 0, patch: 0)

		// Try higher versions first.
		return leftSemantic > rightSemantic
	}

	fileprivate static func == (_ lhs: DependencyNode, _ rhs: DependencyNode) -> Bool {
		return lhs.dependency == rhs.dependency
	}
}

extension DependencyNode: Hashable {
	fileprivate var hashValue: Int {
		return dependency.hashValue
	}
}

extension DependencyNode: CustomStringConvertible {
	fileprivate var description: String {
		return "\(dependency) @ \(proposedVersion))"
	}
}

/// Reference type tracking when version incompatibilities are found, for skipping later permutations
private final class ErrorCache {
	typealias DependencyVersion = (dependency: Dependency, version: PinnedVersion)

	/// Nested lookup table for one nested dependency being incompatible with another
	private var incompatibilities: [Dependency: [PinnedVersion: [Dependency: Set<PinnedVersion>]]] = [:]
	private var rootIncompatibilites: [Dependency: Set<PinnedVersion>] = [:]

	/// Adds a conflict with the root version specifiers
	func addRootIncompatibility(for depVersion: DependencyVersion) {
		var versions = rootIncompatibilites.removeValue(forKey: depVersion.dependency) ?? Set()
		versions.insert(depVersion.version)
		rootIncompatibilites[depVersion.dependency] = versions
	}

	/// Add a conflict between two dependency versions
	func addIncompatibilityBetween(_ dependencyVersion1: DependencyVersion, _ dependencyVersion2: DependencyVersion) {
		addIncompatibility(for: dependencyVersion1, to: dependencyVersion2)
		addIncompatibility(for: dependencyVersion2, to: dependencyVersion1)
	}

	func graphIsValid(_ graph: DependencyGraph) -> Bool {
		let versions = graph.versions
		return !graph.allNodes.contains { !dependencyIsValid($0.dependency, given: versions) }
	}

	func dependencyIsValid(_ dependency: Dependency, given versions: [Dependency: PinnedVersion]) -> Bool {
		guard let currentVersion = versions[dependency] else {
			return true
		}

		if rootIncompatibilites[dependency]?.contains(currentVersion) ?? false {
			return false
		}

		if let incompatibleDependencies = incompatibilities[dependency]?[currentVersion] {
			return !versions.contains { otherDependency, otherVersion in
				return incompatibleDependencies[otherDependency]?.contains(otherVersion) ?? false
			}
		}

		return true
	}

	private func addIncompatibility(for depVersion1: DependencyVersion, to depVersion2: DependencyVersion) {
		// Dive down into the proper set for lookup
		var versionMap = incompatibilities.removeValue(forKey: depVersion1.dependency) ?? [:]
		var versionIncompatibilities = versionMap.removeValue(forKey: depVersion1.version) ?? [:]
		var versions = versionIncompatibilities.removeValue(forKey: depVersion2.dependency) ?? Set()

		versions.insert(depVersion2.version)

		// Assign all values back into the maps
		versionIncompatibilities[depVersion2.dependency] = versions
		versionMap[depVersion1.version] = versionIncompatibilities
		incompatibilities[depVersion1.dependency] = versionMap
	}
}
