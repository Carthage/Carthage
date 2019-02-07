import Foundation
import Result
import ReactiveSwift
import Utility

/// Protocol for resolving acyclic dependency graphs.
public protocol ResolverProtocol {
	init(
		versionsForDependency: @escaping (Dependency) -> SignalProducer<PinnedVersion, CarthageError>,
		dependenciesForDependency: @escaping (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>,
		resolvedGitReference: @escaping (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
	)

	func resolve(
		dependencies: [Dependency: VersionSpecifier],
		lastResolved: [Dependency: PinnedVersion]?,
		dependenciesToUpdate: [String]?
	) -> SignalProducer<[Dependency: PinnedVersion], CarthageError>
}

/// Responsible for resolving acyclic dependency graphs.
public struct Resolver: ResolverProtocol {
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
		return graphs(for: dependencies, dependencyOf: nil, basedOnGraph: DependencyGraph())
			.take(first: 1)
			.observe(on: QueueScheduler(qos: .default, name: "org.carthage.CarthageKit.Resolver.resolve"))
			.flatMap(.merge) { graph -> SignalProducer<(Dependency, PinnedVersion), CarthageError> in
				let orderedNodes = graph.orderedNodes.map { node -> DependencyNode in
					node.dependencies = graph.edges[node] ?? []
					return node
				}
				let orderedNodesProducer = SignalProducer<DependencyNode, CarthageError>(orderedNodes)

				guard
					let dependenciesToUpdate = dependenciesToUpdate,
					let lastResolved = lastResolved,
					!dependenciesToUpdate.isEmpty else {
					// All the dependencies are affected.
					return orderedNodesProducer.map { node in node.pinnedDependency }
				}

				// When target dependencies are specified
				return orderedNodesProducer.filterMap { node -> (Dependency, PinnedVersion)? in
					// A dependency included in the targets should be affected.
					if dependenciesToUpdate.contains(node.dependency.name) {
						return node.pinnedDependency
					}

					// Nested dependencies of the targets should also be affected.
					if graph.dependencies(dependenciesToUpdate, containsNestedDependencyOfNode: node) {
						return node.pinnedDependency
					}

					// The dependencies which are not related to the targets
					// should not be affected, so use the last resolved version.
					if let version = lastResolved[node.dependency] {
						return (node.dependency, version)
					}

					// Skip newly added nodes which are not in the targets.
					return nil
				}
			}
			.reduce(into: [:]) { (result: inout [Dependency: PinnedVersion], dependency) in
				result[dependency.0] = dependency.1
			}
	}

	/// Sends all permutations of valid DependencyNodes, corresponding to the
	/// given dependencies, in the order that they should be tried.
	///
	/// In other words, this will always send arrays equal in length to
	/// `dependencies`. Each array represents one possible permutation of those
	/// dependencies (chosen from among the versions that actually exist for
	/// each).
	private func nodePermutations(for dependencies: [Dependency: VersionSpecifier]) -> SignalProducer<[DependencyNode], CarthageError> {
		let scheduler = QueueScheduler(qos: .default, name: "org.carthage.CarthageKit.Resolver.nodePermutations")

		return SignalProducer(dependencies)
			.map { dependency -> SignalProducer<DependencyNode, CarthageError> in
				return SignalProducer<(key: Dependency, value: VersionSpecifier), CarthageError>(value: dependency)
					.flatMap(.concat) { dependency -> SignalProducer<PinnedVersion, CarthageError> in
						if case let .gitReference(refName) = dependency.value {
							return self.resolvedGitReference(dependency.key, refName)
						}

						return self
							.versionsForDependency(dependency.key)
							.filter { dependency.value.isSatisfied(by: $0) }
					}
					.start(on: scheduler)
					.observe(on: scheduler)
					.map { DependencyNode(dependency: dependency.key, proposedVersion: $0, versionSpecifier: dependency.value) }
					.collect()
					.map { $0.sorted() }
					.flatMap(.concat) { nodes -> SignalProducer<DependencyNode, CarthageError> in
						if nodes.isEmpty {
							return SignalProducer(error: CarthageError.requiredVersionNotFound(dependency.key, dependency.value))
						} else {
							return SignalProducer(nodes)
						}
					}
			}
			.observe(on: scheduler)
			.permute()
	}

	/// Sends all possible permutations of `inputGraph` oriented around the
	/// dependencies of `node`.
	///
	/// In other words, this attempts to create one transformed graph for each
	/// possible permutation of the dependencies for the given node (chosen from
	/// among the versions that actually exist for each).
	private func graphsForDependenciesOfNode(_ node: DependencyNode, basedOnGraph inputGraph: DependencyGraph) -> SignalProducer<DependencyGraph, CarthageError> {
		let scheduler = QueueScheduler(qos: .default, name: "org.carthage.CarthageKit.Resolver.graphsForDependenciesOfNode")

		return dependenciesForDependency(node.dependency, node.proposedVersion)
			.start(on: scheduler)
			.reduce(into: [:]) { result, dependency in
				result[dependency.0] = dependency.1
			}
			.concat(value: [:])
			.take(first: 1)
			.observe(on: scheduler)
			.flatMap(.concat) { dependencies in
				return self.graphs(for: dependencies, dependencyOf: node, basedOnGraph: inputGraph)
			}
	}

	/// Recursively permutes `dependencies` and all dependencies thereof,
	/// attaching each permutation to `inputGraph` as a dependency of the
	/// specified node (or as a root otherwise).
	///
	/// This is a helper method, and not meant to be called from outside.
	private func graphs(
		for dependencies: [Dependency: VersionSpecifier],
		dependencyOf: DependencyNode?,
		basedOnGraph inputGraph: DependencyGraph
	) -> SignalProducer<DependencyGraph, CarthageError> {
		return nodePermutations(for: dependencies)
			.flatMap(.concat) { (nodes: [DependencyNode]) -> SignalProducer<Signal<DependencyGraph, CarthageError>.Event, NoError> in
				return self
					.graphs(for: nodes, dependencyOf: dependencyOf, basedOnGraph: inputGraph)
					.materialize()
			}
			// Pass through resolution errors only if we never got
			// a valid graph.
			.dematerializeErrorsIfEmpty()
	}

	/// Recursively permutes each element in `nodes` and all dependencies
	/// thereof, attaching each permutation to `inputGraph` as a dependency of
	/// the specified node (or as a root otherwise).
	///
	/// This is a helper method, and not meant to be called from outside.
	private func graphs(
		for nodes: [DependencyNode],
		dependencyOf: DependencyNode?,
		basedOnGraph inputGraph: DependencyGraph
	) -> SignalProducer<DependencyGraph, CarthageError> {
		let scheduler = QueueScheduler(qos: .default, name: "org.carthage.CarthageKit.Resolver.graphs")

		return SignalProducer<(DependencyGraph, [DependencyNode]), CarthageError> { () -> Result<(DependencyGraph, [DependencyNode]), CarthageError> in
				var graph = inputGraph
				return graph
					.addNodes(nodes, dependenciesOf: dependencyOf)
					.map { newNodes in
						return (graph, newNodes)
					}
			}
			.flatMap(.concat) { graph, nodes -> SignalProducer<DependencyGraph, CarthageError> in
				return SignalProducer(nodes)
					// Each producer represents all evaluations of one subtree.
					.map { node in self.graphsForDependenciesOfNode(node, basedOnGraph: graph) }
					.observe(on: scheduler)
					.permute()
					.flatMap(.concat) { graphs -> SignalProducer<Signal<DependencyGraph, CarthageError>.Event, NoError> in
						return SignalProducer<DependencyGraph, CarthageError> {
								mergeGraphs([ inputGraph ] + graphs)
							}
							.materialize()
					}
					// Pass through resolution errors only if we never got
					// a valid graph.
					.dematerializeErrorsIfEmpty()
			}
	}
}

/// Represents an acyclic dependency graph in which each project appears at most
/// once.
///
/// Dependency graphs can exist in an incomplete state, but will never be
/// inconsistent (i.e., include versions that are known to be invalid given the
/// current graph).
private struct DependencyGraph {
	/// A full list of all nodes included in the graph.
	var allNodes: Set<DependencyNode> = []

	/// All nodes that have dependencies, associated with those lists of
	/// dependencies themselves including the intermediates.
	var edges: [DependencyNode: Set<DependencyNode>] = [:]

	/// The root nodes of the graph (i.e., those dependencies that are listed
	/// by the top-level project).
	var roots: Set<DependencyNode> = []

	/// Returns all of the graph nodes, in the order that they should be built.
	var orderedNodes: [DependencyNode] {
		return allNodes.sorted { lhs, rhs in
			let lhsDependencies = self.edges[lhs]
			let rhsDependencies = self.edges[rhs]

			if let rhsDependencies = rhsDependencies {
				// If the right node has a dependency on the left node, the
				// left node needs to be built first (and is thus ordered
				// first).
				if rhsDependencies.contains(lhs) {
					return true
				}
			}

			if let lhsDependencies = lhsDependencies {
				// If the left node has a dependency on the right node, the
				// right node needs to be built first.
				if lhsDependencies.contains(rhs) {
					return false
				}
			}

			// If neither node depends on each other, sort the one with the
			// fewer dependencies first.
			let lhsCount = lhsDependencies?.count ?? 0
			let rhsCount = rhsDependencies?.count ?? 0

			if lhsCount < rhsCount {
				return true
			} else if lhsCount > rhsCount {
				return false
			} else {
				// If all else fails, compare names.
				return lhs.dependency.name < rhs.dependency.name
			}
		}
	}

	init() {}

	/// Attempts to add the given node to the graph, optionally as a dependency
	/// of another.
	///
	/// If the given node refers to a project which already exists in the graph,
	/// this method will attempt to unify the version specifiers of both.
	///
	/// Returns the node as actually inserted into the graph (which may be
	/// different from the node passed in), or an error if this addition would
	/// make the graph inconsistent.
	mutating func addNode(_ node: DependencyNode, dependencyOf: DependencyNode?) -> Result<DependencyNode, CarthageError> {
		var node = node

		if let index = allNodes.index(of: node) {
			let existingNode = allNodes[index]

			if let newSpecifier = intersection(existingNode.versionSpecifier, node.versionSpecifier) {
				if newSpecifier.isSatisfied(by: existingNode.proposedVersion) {
					node = existingNode
					node.versionSpecifier = newSpecifier
				} else {
					return .failure(CarthageError.requiredVersionNotFound(node.dependency, newSpecifier))
				}
			} else if existingNode.proposedVersion != node.proposedVersion {
				// The guard condition above is required for enabling to build a
				// dependency graph in the cases such as: one node has a
				// `.gitReference` specifier of a branch name, and the other has
				// a `.gitReference` of a SHA which is the HEAD of that branch.
				// If the specifiers are not the same but the nodes have the same
				// proposed version, the graph should be valid.
				//
				// See https://github.com/Carthage/Carthage/issues/765.
				let existingDependencyOf = edges
					.filter { _, value in value.contains(existingNode) }
					.map { $0.0 }
					.first
				let first = (existingNode.versionSpecifier, existingDependencyOf?.dependency)
				let second = (node.versionSpecifier, dependencyOf?.dependency)
				return .failure(CarthageError.incompatibleRequirements(node.dependency, first, second))
			}
		} else {
			allNodes.insert(node)
		}

		if let dependencyOf = dependencyOf {
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
					itsDependencies.insert(node)
					edges[ancestor] = itsDependencies
				}
			}
		} else {
			roots.insert(node)
		}

		return .success(node)
	}

	/// Attempts to add the given nodes to the graph, optionally as a dependency
	/// of another.
	///
	/// If a given node refers to a project which already exists in the graph,
	/// this method will attempt to unify the version specifiers of both.
	///
	/// Returns the nodes as actually inserted into the graph (which may be
	/// different from the node passed in), or an error if this addition would
	/// make the graph inconsistent.
	mutating func addNodes
		<C: Collection>
		(_ nodes: C, dependenciesOf: DependencyNode?) -> Result<[DependencyNode], CarthageError>
		where C.Iterator.Element == DependencyNode {
		var newNodes: [DependencyNode] = []

		for node in nodes {
			switch self.addNode(node, dependencyOf: dependenciesOf) {
			case let .success(newNode):
				newNodes.append(newNode)

			case let .failure(error):
				return Result(error: error)
			}
		}

		return Result(value: newNodes)
	}

	/// Whether the given node is included or not in the nested dependencies of
	/// the given dependencies.
	func dependencies(_ dependencies: [String], containsNestedDependencyOfNode node: DependencyNode) -> Bool {
		return edges
			.first { edge, nodeSet in
				return dependencies.contains(edge.dependency.name) && nodeSet.contains(node)
			}
			.map { _ in true } ?? false
	}
}

extension DependencyGraph: Equatable {
	fileprivate static func == (_ lhs: DependencyGraph, _ rhs: DependencyGraph) -> Bool {
		if lhs.edges.count != rhs.edges.count || lhs.roots.count != rhs.roots.count {
			return false
		}

		for (edge, leftDeps) in lhs.edges {
			if let rightDeps = rhs.edges[edge] {
				if leftDeps.count != rightDeps.count {
					return false
				}

				for dep in leftDeps {
					if !rightDeps.contains(dep) {
						return false
					}
				}
			} else {
				return false
			}
		}

		for root in lhs.roots {
			if !rhs.roots.contains(root) {
				return false
			}
		}

		return true
	}
}

extension DependencyGraph: CustomStringConvertible {
	fileprivate var description: String {
		var str = "Roots:"

		for root in roots {
			str += "\n\t\(root)"
		}

		str += "\n\nEdges:"

		for (node, dependencies) in edges {
			str += "\n\t\(node.dependency) ->"
			for dep in dependencies {
				str += "\n\t\t\(dep)"
			}
		}

		return str
	}
}

/// Attempts to unify a collection of graphs.
///
/// Returns the new graph, or an error if the graphs specify inconsistent
/// versions for one or more dependencies.
private func mergeGraphs
	<C: Collection>
	(_ graphs: C) -> Result<DependencyGraph, CarthageError>
	where C.Iterator.Element == DependencyGraph {
	precondition(!graphs.isEmpty)

	var result: Result<DependencyGraph, CarthageError> = .success(graphs.first!)

	for next in graphs {
		for root in next.roots {
			result = result.flatMap { graph in
				var graph = graph
				return graph.addNode(root, dependencyOf: nil).map { _ in graph }
			}
		}

		for (node, dependencies) in next.edges {
			for dependency in dependencies {
				result = result.flatMap { graph in
					var graph = graph
					return graph.addNode(dependency, dependencyOf: node).map { _ in graph }
				}
			}
		}
	}

	return result
}

/// A node in, or being considered for, an acyclic dependency graph.
private final class DependencyNode {
	/// The dependency that this node refers to.
	let dependency: Dependency

	/// The version of the dependency that this node represents.
	///
	/// This version is merely "proposed" because it depends on the final
	/// resolution of the graph, as well as whether any "better" graphs exist.
	let proposedVersion: PinnedVersion

	/// The current requirements applied to this dependency.
	///
	/// This specifier may change as the graph is added to, and the requirements
	/// become more stringent.
	var versionSpecifier: VersionSpecifier

	/// The dependencies of this node.
	var dependencies: Set<DependencyNode> = []

	/// A Dependency equivalent to this node.
	var pinnedDependency: (Dependency, PinnedVersion) {
		return (dependency, proposedVersion)
	}

	init(dependency: Dependency, proposedVersion: PinnedVersion, versionSpecifier: VersionSpecifier) {
		precondition(versionSpecifier.isSatisfied(by: proposedVersion))

		self.dependency = dependency
		self.proposedVersion = proposedVersion
		self.versionSpecifier = versionSpecifier
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
		return "\(dependency) @ \(proposedVersion) (restricted to \(versionSpecifier))"
	}
}
