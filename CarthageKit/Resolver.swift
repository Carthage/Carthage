//
//  Resolver.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-09.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa

/// Responsible for resolving acyclic dependency graphs.
public struct Resolver {
	private let versionsForDependency: ProjectIdentifier -> ColdSignal<SemanticVersion>
	private let cartfileForDependency: Dependency<SemanticVersion> -> ColdSignal<Cartfile>

	/// Instantiates a dependency graph resolver with the given behaviors.
	///
	/// versionsForDependency - Sends a stream of available SemanticVersions
	///                         for a dependency.
	/// cartfileForDependency - Loads the Cartfile for a specific version of a
	///                         dependency.
	public init(versionsForDependency: ProjectIdentifier -> ColdSignal<SemanticVersion>, cartfileForDependency: Dependency<SemanticVersion> -> ColdSignal<Cartfile>) {
		self.versionsForDependency = versionsForDependency
		self.cartfileForDependency = cartfileForDependency
	}

	/// Attempts to determine the latest valid version to use for each dependency
	/// specified in the given Cartfile, and all nested dependencies thereof.
	///
	/// Sends each recursive dependency with its resolved version, in the order
	/// that they should be built.
	public func resolveDependenciesInCartfile(cartfile: Cartfile) -> ColdSignal<Dependency<SemanticVersion>> {
		return nodePermutationsForCartfile(cartfile)
			.map { rootNodes in self.graphPermutationsForEachNode(rootNodes, dependencyOf: nil, basedOnGraph: DependencyGraph()) }
			.concat(identity)
			// Pass through resolution errors only if we never got
			// a valid graph.
			.dematerializeErrorsIfEmpty(identity)
			.take(1)
			.map { graph -> ColdSignal<Dependency<SemanticVersion>> in
				return ColdSignal.fromValues(graph.orderedNodes)
					.map { node in node.dependencyVersion }
			}
			.merge(identity)
	}

	/// Sends all permutations of valid DependencyNodes, corresponding to the
	/// dependencies listed in the given Cartfile, in the order that they should
	/// be tried.
	///
	/// In other words, this will always send arrays equal in length to
	/// `cartfile.dependencies`. Each array represents one possible permutation
	/// of those dependencies (chosen from among the versions that actually
	/// exist for each).
	private func nodePermutationsForCartfile(cartfile: Cartfile) -> ColdSignal<[DependencyNode]> {
		let nodeSignals = cartfile.dependencies.map { dependency -> ColdSignal<DependencyNode> in
			return self.versionsForDependency(dependency.project)
				.filter { dependency.version.satisfiedBy($0) }
				.map { DependencyNode(project: dependency.project, proposedVersion: $0, versionSpecifier: dependency.version) }
				.reduce(initial: []) { $0 + [ $1 ] }
				.map(sorted)
				.map { nodes -> ColdSignal<DependencyNode> in
					if nodes.isEmpty {
						return .error(CarthageError.RequiredVersionNotFound(dependency.project, dependency.version).error)
					} else {
						return .fromValues(nodes)
					}
				}
				.concat(identity)
		}

		return permutations(nodeSignals)
	}

	/// Sends all possible permutations of `inputGraph` oriented around the
	/// dependencies of `node`.
	///
	/// In other words, this attempts to create one transformed graph for each
	/// possible permutation of the dependencies for the given node (chosen from
	/// among the verisons that actually exist for each).
	private func graphPermutationsForDependenciesOfNode(node: DependencyNode, basedOnGraph inputGraph: DependencyGraph) -> ColdSignal<DependencyGraph> {
		return cartfileForDependency(node.dependencyVersion)
			.concat(.single(Cartfile(dependencies: [])))
			.take(1)
			.map { self.nodePermutationsForCartfile($0) }
			.merge(identity)
			.map { dependencyNodes in self.graphPermutationsForEachNode(dependencyNodes, dependencyOf: node, basedOnGraph: inputGraph) }
			.concat(identity)
			// Pass through resolution errors only if we never got
			// a valid graph.
			.dematerializeErrorsIfEmpty(identity)
	}

	/// Recursively permutes each element in `nodes` and all dependencies
	/// thereof, attaching each permutation to `inputGraph` as a dependency of
	/// the specified node (or as a root otherwise).
	///
	/// This is a helper method, and not meant to be called from outside.
	private func graphPermutationsForEachNode(nodes: [DependencyNode], dependencyOf: DependencyNode?, basedOnGraph inputGraph: DependencyGraph) -> ColdSignal<Event<DependencyGraph>> {
		return ColdSignal.lazy {
			var result = success(inputGraph)

			for node in nodes {
				result = result.flatMap { (var graph) in
					return graph.addNode(node, dependencyOf: dependencyOf)
						.map { _ in graph }
				}
			}

			return ColdSignal.fromResult(result)
				.map { graph -> ColdSignal<DependencyGraph> in
					// Each signal represents all evaluations of one subtree.
					let graphSignals = nodes.map { node in self.graphPermutationsForDependenciesOfNode(node, basedOnGraph: graph) }

					return permutations(graphSignals)
						.map { graphs -> ColdSignal<Event<DependencyGraph>> in
							let result = reduce(graphs, success(inputGraph)) { (result, graph) in
								return result.flatMap { mergeGraphs($0, graph) }
							}

							switch result {
							case let .Success(graph):
								return ColdSignal.single(graph.unbox).materialize()

							case let .Failure(error):
								// Discard impossible graphs.
								return .single(.Error(error))
							}
						}
						.concat(identity)
						// Pass through resolution errors only if we never got
						// a valid graph.
						.dematerializeErrorsIfEmpty(identity)
				}
				.merge(identity)
				.materialize()
		}
	}
}

/// A poor person's Set.
private typealias DependencyNodeSet = [DependencyNode: ()]

/// Represents an acyclic dependency graph in which each project appears at most
/// once.
///
/// Dependency graphs can exist in an incomplete state, but will never be
/// inconsistent (i.e., include versions that are known to be invalid given the
/// current graph).
private struct DependencyGraph: Equatable {
	/// A full list of all nodes included in the graph.
	var allNodes: DependencyNodeSet = [:]

	/// All nodes that have dependencies, associated with those lists of
	/// dependencies themselves.
	var edges: [DependencyNode: DependencyNodeSet] = [:]

	/// The root nodes of the graph (i.e., those dependencies that are listed
	/// by the top-level project).
	var roots: DependencyNodeSet = [:]

	/// Returns all of the graph nodes, in the order that they should be built.
	var orderedNodes: [DependencyNode] {
		return sorted(allNodes.keys) { (lhs, rhs) in
			let leftDeps = self.edges[lhs]
			let rightDeps = self.edges[rhs]

			if let rightDeps = rightDeps {
				// If the right node has a dependency on the left node, the
				// left node needs to be built first (and is thus ordered
				// first).
				if contains(rightDeps.keys, lhs) {
					return true
				}
			}

			if let leftDeps = leftDeps {
				// If the left node has a dependency on the right node, the
				// right node needs to be built first.
				if contains(leftDeps.keys, rhs) {
					return false
				}
			}

			if leftDeps != nil || rightDeps != nil {
				// If neither node depends on each other, sort the one with the
				// fewer dependencies first.
				return (leftDeps?.count ?? 0) < (rightDeps?.count ?? 0)
			}

			// If all else fails, compare names.
			return lhs.project.name < rhs.project.name
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
	mutating func addNode(var node: DependencyNode, dependencyOf: DependencyNode?) -> Result<DependencyNode> {
		if let index = allNodes.indexForKey(node) {
			let existingNode = allNodes[index].0

			if let newSpecifier = intersection(existingNode.versionSpecifier, node.versionSpecifier) {
				if newSpecifier.satisfiedBy(existingNode.proposedVersion) {
					node = existingNode
					node.versionSpecifier = newSpecifier
				} else {
					return failure(CarthageError.RequiredVersionNotFound(node.project, newSpecifier).error)
				}
			} else {
				return failure(CarthageError.IncompatibleRequirements(node.project, existingNode.versionSpecifier, node.versionSpecifier).error)
			}
		} else {
			allNodes[node] = ()
		}

		if let dependencyOf = dependencyOf {
			var nodeSet = edges[dependencyOf] ?? DependencyNodeSet()
			nodeSet[node] = ()
			edges[dependencyOf] = nodeSet
		} else {
			roots[node] = ()
		}

		return success(node)
	}
}

private func ==(lhs: DependencyGraph, rhs: DependencyGraph) -> Bool {
	if lhs.edges.count != rhs.edges.count || lhs.roots.count != rhs.roots.count {
		return false
	}

	for (edge, leftDeps) in lhs.edges {
		if let rightDeps = rhs.edges[edge] {
			if leftDeps.count != rightDeps.count {
				return false
			}

			for (dep, _) in leftDeps {
				if rightDeps[dep] == nil {
					return false
				}
			}
		} else {
			return false
		}
	}

	for (root, _) in lhs.roots {
		if rhs.roots[root] == nil {
			return false
		}
	}

	return true
}

extension DependencyGraph: Printable {
	private var description: String {
		var str = "Roots:"

		for (root, _) in roots {
			str += "\n\t\(root)"
		}

		str += "\n\nEdges:"

		for (node, dependencies) in edges {
			str += "\n\t\(node.project) ->"
			for (dep, _) in dependencies {
				str += "\n\t\t\(dep)"
			}
		}

		return str
	}
}

/// Attempts to unify two graphs.
///
/// Returns the new graph, or an error if the graphs specify inconsistent
/// versions for one or more dependencies.
private func mergeGraphs(lhs: DependencyGraph, rhs: DependencyGraph) -> Result<DependencyGraph> {
	var result = success(lhs)

	for (root, _) in rhs.roots {
		result = result.flatMap { (var graph) in
			return graph.addNode(root, dependencyOf: nil).map { _ in graph }
		}
	}

	for (node, dependencies) in rhs.edges {
		for (dependency, _) in dependencies {
			result = result.flatMap { (var graph) in
				return graph.addNode(dependency, dependencyOf: node).map { _ in graph }
			}
		}
	}

	return result
}

/// A node in, or being considered for, an acyclic dependency graph.
private class DependencyNode: Comparable {
	/// The project that this node refers to.
	let project: ProjectIdentifier

	/// The version of the dependency that this node represents.
	///
	/// This version is merely "proposed" because it depends on the final
	/// resolution of the graph, as well as whether any "better" graphs exist.
	let proposedVersion: SemanticVersion

	/// The current requirements applied to this dependency.
	///
	/// This specifier may change as the graph is added to, and the requirements
	/// become more stringent.
	var versionSpecifier: VersionSpecifier

	/// A Dependency equivalent to this node.
	var dependencyVersion: Dependency<SemanticVersion> {
		return Dependency(project: project, version: proposedVersion)
	}

	init(project: ProjectIdentifier, proposedVersion: SemanticVersion, versionSpecifier: VersionSpecifier) {
		precondition(versionSpecifier.satisfiedBy(proposedVersion))

		self.project = project
		self.proposedVersion = proposedVersion
		self.versionSpecifier = versionSpecifier
	}
}

private func <(lhs: DependencyNode, rhs: DependencyNode) -> Bool {
	// Try higher versions first.
	return lhs.proposedVersion > rhs.proposedVersion
}

private func ==(lhs: DependencyNode, rhs: DependencyNode) -> Bool {
	return lhs.project == rhs.project
}

extension DependencyNode: Hashable {
	private var hashValue: Int {
		return project.hashValue
	}
}

extension DependencyNode: Printable {
	private var description: String {
		return "\(project) @ \(proposedVersion) (restricted to \(versionSpecifier))"
	}
}
