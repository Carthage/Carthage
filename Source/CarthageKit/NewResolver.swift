import Foundation
import Result
import ReactiveSwift
import Utility

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
		in baseGraph: DependencyGraph,
		withParent parentNode: DependencyNode?
		) -> Result<NodePermutations, CarthageError> {
		return SignalProducer<(key: Dependency, value: VersionSpecifier), CarthageError>(dependencies)
			.flatMap(.concat) { dependency, specifier -> SignalProducer<[DependencyNode], CarthageError> in
				let versionProducer: SignalProducer<PinnedVersion, CarthageError>
				if case let .gitReference(refName) = specifier {
					versionProducer = self.resolvedGitReference(dependency, refName)
				} else if let existingNode = baseGraph.node(for: dependency) {
					// We still 'permute' over all dependencies to properly account for the graph edges
					// but if it has already been pinned, the only possible value is that pinned version
					versionProducer = SignalProducer(value: existingNode.proposedVersion)
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
					baseGraph: baseGraph,
					nodesToPermute: nodesToPermute,
					errorCache: self.errorCache)
			}
			.first()!
	}

	/// Permutes `dependencies`, attaching each permutation to `baseGraph`, as a dependency of the
	/// specified node (or as a root otherwise). It then recursively processes each graph
	///
	/// This is a helper method, and not meant to be called from outside.
	private func process(
		dependencies: [Dependency: VersionSpecifier],
		in baseGraph: DependencyGraph,
		withParent parent: DependencyNode? = nil
		) -> Result<DependencyGraph, CarthageError> {
		return self.nodePermutations(for: dependencies, in: baseGraph, withParent: parent)
			.flatMap { permutations in
				// Only throw an error if no valid graph was produced by any of the permutations
				var errResult: Result<DependencyGraph, CarthageError>?
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
			.attempt { child, newSpecifier -> Result<(), CarthageError> in
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
	func addNode(_ node: DependencyNode) -> Result<DependencyGraph, CarthageError> {
		if allNodes.contains(node) {
			// It already exists, only update the edge list
			return self.updateEdges(with: node)
		}

		var newGraph = self
		newGraph.allNodes.insert(node)
		newGraph.unvisitedNodes.append(node)

		return newGraph.updateEdges(with: node)
	}

	/// Adds the given nodes to the graph
	///
	/// Adds the nodes to the unvisited nodes list, in the order given
	/// Returns self if successful
	func addNodes<C: Collection>(_ nodes: C) -> Result<DependencyGraph, CarthageError>
		where C.Iterator.Element == DependencyNode {
			return nodes.reduce(.success(self)) { graph, node in
				return graph.flatMap { $0.addNode(node) }
			}
	}

	/// Produces a new graph with an updated the edge list for the given node
	private func updateEdges(with node: DependencyNode) -> Result<DependencyGraph, CarthageError> {
		guard let parent = node.parent else {
			return .success(self)
		}

		var newGraph = self
		var nodeSet = edges[parent] ?? Set()
		nodeSet.insert(node)

		// If the given node already has dependencies, add them to the list.
		if let dependenciesOfNode = edges[node] {
			nodeSet.formUnion(dependenciesOfNode)
		}

		newGraph.edges[parent] = nodeSet

		// Add a nested dependency to the list of its ancestor.
		for (ancestor, var itsDependencies) in edges {
			if itsDependencies.contains(parent) {
				itsDependencies.formUnion(nodeSet)
				newGraph.edges[ancestor] = itsDependencies
			}
		}

		return .success(newGraph)
	}
}

/// Custom iterator to perform permutations. Used in tandem with the `ErrorCache', 
/// allowing us to short circuit permutations before generating them, rather than
/// filtering results as they come.
private struct NodePermutations: Sequence, IteratorProtocol {
	private let baseGraph: DependencyGraph
	private var currentNodeValues: [Dimension]
	private let errorCache: ErrorCache
	private var hasNext = true

	/// Instantiates a permutation sequence for `nodesToPermute`. Each permutation
	/// creates a new graph from `baseGraph`, with the nodes added to the graph.
	init(
		baseGraph: DependencyGraph,
		nodesToPermute: [[DependencyNode]],
		errorCache: ErrorCache
	) {
		self.baseGraph = baseGraph
		self.currentNodeValues = nodesToPermute.map { Dimension($0) }
		self.errorCache = errorCache
	}

	/// Generates the next permutation, skipping over any combinations which are deemed
	/// invalid by the error cache
	mutating func next() -> Result<DependencyGraph, CarthageError>? {
		guard hasNext else { return nil }

		// In case incompatibilities came in for a higher level in the recursion, skip the entire sequence
		guard errorCache.graphIsValid(baseGraph) else { return nil }

		guard let graph = nextValidGraph() else { return nil }

		incrementIndexes()
		return graph
	}

	/// Creates a new graph from the indexes stored in the currentNodeValues array
	private func generateGraph() -> Result<DependencyGraph, CarthageError> {
		let newNodes = currentNodeValues.map { $0.node }
		return baseGraph.addNodes(newNodes)
	}

	/// Generates the next valid graph, skipping over invalid permutations
	/// Returns an error if any graph generation results in an error
	private mutating func nextValidGraph() -> Result<DependencyGraph, CarthageError>? {
		var result: Result<DependencyGraph, CarthageError>?
		// Skip any invalid permutations
		while hasNext && result == nil {
			result = generateGraph()
			guard case let .success(generatedGraph) = generateGraph() else { break }

			let versions = generatedGraph.versions
			// swiftlint:disable:next identifier_name
			for i in (currentNodeValues.startIndex..<currentNodeValues.endIndex).reversed() {
				let node = currentNodeValues[i].node
				if !errorCache.dependencyIsValid(node.dependency, given: versions) {
					incrementIndexes(startingAt: currentNodeValues.index(after: i))
					result = nil
					break
				}
			}
		}

		return result
	}

	/// Basic permutation increment
	private mutating func incrementIndexes(startingAt startingIndex: Array<Dimension>.Index? = nil) {
		guard hasNext else { return }

		// 'skip' any permutations as defined by 'startingIndex' by setting all subsequent values to their max. We don't count this as an 'incremented' occurrence.
		if let startingIndex = startingIndex {
			// swiftlint:disable:next identifier_name
			for i in (startingIndex..<currentNodeValues.endIndex) {
				currentNodeValues[i].skipRemaining()
			}
		}

		// If we 'reset' for every dimension, we've hit the end
		hasNext = false
		// swiftlint:disable:next identifier_name
		for i in (currentNodeValues.startIndex..<currentNodeValues.endIndex).reversed() {
			if currentNodeValues[i].increment() == .incremented {
				hasNext = true
				break
			}
		}
	}
}

/// Helper struct to track a single axis of a permutation
extension NodePermutations {
	enum IncrementResult {
		case incremented
		case reset
	}

	struct Dimension {
		let nodes: [DependencyNode]
		var index: Array<DependencyNode>.Index

		init(_ nodes: [DependencyNode]) {
			self.nodes = nodes
			self.index = nodes.startIndex
		}

		var node: DependencyNode {
			return nodes[index]
		}

		mutating func skipRemaining() {
			index = nodes.index(before: nodes.endIndex)
		}

		mutating func increment() -> IncrementResult {
			index = nodes.index(after: index)
			if index < nodes.endIndex {
				return .incremented
			} else {
				index = nodes.startIndex
				return .reset
			}
		}
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
		let leftSemantic = Version.from(lhs.proposedVersion).value ?? Version(0, 0, 0)
		let rightSemantic = Version.from(rhs.proposedVersion).value ?? Version(0, 0, 0)

		// Try higher versions first.
		return leftSemantic > rightSemantic
	}

	fileprivate static func == (_ lhs: DependencyNode, _ rhs: DependencyNode) -> Bool {
		guard lhs.dependency == rhs.dependency else { return false }

		let leftSemantic = Version.from(lhs.proposedVersion).value ?? Version(0, 0, 0)
		let rightSemantic = Version.from(rhs.proposedVersion).value ?? Version(0, 0, 0)
		return leftSemantic == rightSemantic
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
