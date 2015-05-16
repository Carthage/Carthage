//
//  Resolver.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-09.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import Result
import ReactiveCocoa

/// Responsible for resolving acyclic dependency graphs.
public struct Resolver {
	private let versionsForDependency: ProjectIdentifier -> SignalProducer<PinnedVersion, CarthageError>
	private let resolvedGitReference: (ProjectIdentifier, String) -> SignalProducer<PinnedVersion, CarthageError>
	private let cartfileForDependency: Dependency<PinnedVersion> -> SignalProducer<Cartfile, CarthageError>

	/// Instantiates a dependency graph resolver with the given behaviors.
	///
	/// versionsForDependency - Sends a stream of available versions for a
	///                         dependency.
	/// cartfileForDependency - Loads the Cartfile for a specific version of a
	///                         dependency.
	/// resolvedGitReference  - Resolves an arbitrary Git reference to the
	///                         latest object.
	public init(versionsForDependency: ProjectIdentifier -> SignalProducer<PinnedVersion, CarthageError>, cartfileForDependency: Dependency<PinnedVersion> -> SignalProducer<Cartfile, CarthageError>, resolvedGitReference: (ProjectIdentifier, String) -> SignalProducer<PinnedVersion, CarthageError>) {
		self.versionsForDependency = versionsForDependency
		self.cartfileForDependency = cartfileForDependency
		self.resolvedGitReference = resolvedGitReference
	}

	/// Attempts to determine the latest valid version to use for each dependency
	/// specified in the given Cartfile, and all nested dependencies thereof.
	///
	/// Sends each recursive dependency with its resolved version, in the order
	/// that they should be built.
	public func resolveDependenciesInCartfile(cartfile: Cartfile) -> SignalProducer<Dependency<PinnedVersion>, CarthageError> {
		return nodePermutationsForCartfile(cartfile)
			|> map { rootNodes -> SignalProducer<Event<DependencyGraph, CarthageError>, CarthageError> in
				return self.graphPermutationsForEachNode(rootNodes, dependencyOf: nil, basedOnGraph: DependencyGraph())
					|> promoteErrors(CarthageError.self)
			}
			|> flatten(.Concat)
			// Pass through resolution errors only if we never got
			// a valid graph.
			|> dematerializeErrorsIfEmpty
			|> take(1)
			|> map { graph -> SignalProducer<Dependency<PinnedVersion>, CarthageError> in
				return SignalProducer(values: graph.orderedNodes)
					|> map { node in node.dependencyVersion }
			}
			|> flatten(.Merge)
	}

	/// Sends all permutations of valid DependencyNodes, corresponding to the
	/// dependencies listed in the given Cartfile, in the order that they should
	/// be tried.
	///
	/// In other words, this will always send arrays equal in length to
	/// `cartfile.dependencies`. Each array represents one possible permutation
	/// of those dependencies (chosen from among the versions that actually
	/// exist for each).
	private func nodePermutationsForCartfile(cartfile: Cartfile) -> SignalProducer<[DependencyNode], CarthageError> {
		let nodeProducers = cartfile.dependencies.map { dependency -> SignalProducer<DependencyNode, CarthageError> in
			let allowedVersions: SignalProducer<PinnedVersion, CarthageError> = {
				switch dependency.version {
				case let .GitReference(refName):
					return self.resolvedGitReference(dependency.project, refName)

				default:
					return self.versionsForDependency(dependency.project)
						|> reduce([]) { $0 + [ $1 ] }
						|> map { nodes -> SignalProducer<PinnedVersion, CarthageError> in
							if nodes.isEmpty {
								return SignalProducer(error: CarthageError.TaggedVersionNotFound(dependency.project))
							} else {
								return SignalProducer(values: nodes)
							}
						}
						|> flatten(.Merge)
						|> filter { dependency.version.satisfiedBy($0) }
				}
			}()

			return allowedVersions
				|> map { DependencyNode(project: dependency.project, proposedVersion: $0, versionSpecifier: dependency.version) }
				|> reduce([]) { $0 + [ $1 ] }
				|> map(sorted)
				|> map { nodes -> SignalProducer<DependencyNode, CarthageError> in
					if nodes.isEmpty {
						return SignalProducer(error: CarthageError.RequiredVersionNotFound(dependency.project, dependency.version))
					} else {
						return SignalProducer(values: nodes)
					}
				}
				|> flatten(.Concat)
		}

		return permutations(nodeProducers)
	}

	/// Sends all possible permutations of `inputGraph` oriented around the
	/// dependencies of `node`.
	///
	/// In other words, this attempts to create one transformed graph for each
	/// possible permutation of the dependencies for the given node (chosen from
	/// among the verisons that actually exist for each).
	private func graphPermutationsForDependenciesOfNode(node: DependencyNode, basedOnGraph inputGraph: DependencyGraph) -> SignalProducer<DependencyGraph, CarthageError> {
		return cartfileForDependency(node.dependencyVersion)
			|> concat(SignalProducer(value: Cartfile(dependencies: [])))
			|> take(1)
			|> map { self.nodePermutationsForCartfile($0) }
			|> flatten(.Merge)
			|> map { dependencyNodes in
				return self.graphPermutationsForEachNode(dependencyNodes, dependencyOf: node, basedOnGraph: inputGraph)
					|> promoteErrors(CarthageError.self)
			}
			|> flatten(.Concat)
			// Pass through resolution errors only if we never got
			// a valid graph.
			|> dematerializeErrorsIfEmpty
	}

	/// Recursively permutes each element in `nodes` and all dependencies
	/// thereof, attaching each permutation to `inputGraph` as a dependency of
	/// the specified node (or as a root otherwise).
	///
	/// This is a helper method, and not meant to be called from outside.
	private func graphPermutationsForEachNode(nodes: [DependencyNode], dependencyOf: DependencyNode?, basedOnGraph inputGraph: DependencyGraph) -> SignalProducer<Event<DependencyGraph, CarthageError>, NoError> {
		return SignalProducer<(DependencyGraph, [DependencyNode]), CarthageError>.try {
				let initial: (DependencyGraph, [DependencyNode]) = (inputGraph, [])
				var result: Result<(DependencyGraph, [DependencyNode]), CarthageError> = .success(initial)

				for node in nodes {
					result = result.flatMap { (var graph, var newNodes) in
						switch graph.addNode(node, dependencyOf: dependencyOf) {
						case let .Success(newNode):
							newNodes.append(newNode.value)

							let updated = (graph, newNodes)
							return .success(updated)

						case let .Failure(error):
							return .failure(error.value)
						}
					}
				}

				return result
			}
			|> map { graph, nodes -> SignalProducer<DependencyGraph, CarthageError> in
				// Each producer represents all evaluations of one subtree.
				let graphProducers = nodes.map { node in self.graphPermutationsForDependenciesOfNode(node, basedOnGraph: graph) }

				return permutations(graphProducers)
					|> map { graphs -> SignalProducer<Event<DependencyGraph, CarthageError>, CarthageError> in
						let result: Result<DependencyGraph, CarthageError> = reduce(graphs, .success(inputGraph)) { (result, graph) in
							return result.flatMap { mergeGraphs($0, graph) }
						}

						switch result {
						case let .Success(graph):
							return SignalProducer(values: [
								Event.Next(graph),
								Event.Completed
							])

						case let .Failure(error):
							// Discard impossible graphs.
							return SignalProducer(value: .Error(error))
						}
					}
					|> flatten(.Concat)
					// Pass through resolution errors only if we never got
					// a valid graph.
					|> dematerializeErrorsIfEmpty
			}
			|> flatten(.Merge)
			|> materialize
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
			let lhsDependencies = self.edges[lhs]
			let rhsDependencies = self.edges[rhs]

			if let rhsDependencies = rhsDependencies {
				// If the right node has a dependency on the left node, the
				// left node needs to be built first (and is thus ordered
				// first).
				if contains(rhsDependencies.keys, lhs) {
					return true
				}
			}

			if let lhsDependencies = lhsDependencies {
				// If the left node has a dependency on the right node, the
				// right node needs to be built first.
				if contains(lhsDependencies.keys, rhs) {
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
				return lhs.project.name < rhs.project.name
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
	mutating func addNode(var node: DependencyNode, dependencyOf: DependencyNode?) -> Result<DependencyNode, CarthageError> {
		if let index = allNodes.indexForKey(node) {
			let existingNode = allNodes[index].0

			if let newSpecifier = intersection(existingNode.versionSpecifier, node.versionSpecifier) {
				if newSpecifier.satisfiedBy(existingNode.proposedVersion) {
					node = existingNode
					node.versionSpecifier = newSpecifier
				} else {
					return .failure(CarthageError.RequiredVersionNotFound(node.project, newSpecifier))
				}
			} else {
				return .failure(CarthageError.IncompatibleRequirements(node.project, existingNode.versionSpecifier, node.versionSpecifier))
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

		return .success(node)
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
private func mergeGraphs(lhs: DependencyGraph, rhs: DependencyGraph) -> Result<DependencyGraph, CarthageError> {
	var result: Result<DependencyGraph, CarthageError> = .success(lhs)

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
	let proposedVersion: PinnedVersion

	/// The current requirements applied to this dependency.
	///
	/// This specifier may change as the graph is added to, and the requirements
	/// become more stringent.
	var versionSpecifier: VersionSpecifier

	/// A Dependency equivalent to this node.
	var dependencyVersion: Dependency<PinnedVersion> {
		return Dependency(project: project, version: proposedVersion)
	}

	init(project: ProjectIdentifier, proposedVersion: PinnedVersion, versionSpecifier: VersionSpecifier) {
		precondition(versionSpecifier.satisfiedBy(proposedVersion))

		self.project = project
		self.proposedVersion = proposedVersion
		self.versionSpecifier = versionSpecifier
	}
}

private func <(lhs: DependencyNode, rhs: DependencyNode) -> Bool {
	let leftSemantic = SemanticVersion.fromPinnedVersion(lhs.proposedVersion).value ?? SemanticVersion(major: 0, minor: 0, patch: 0)
	let rightSemantic = SemanticVersion.fromPinnedVersion(rhs.proposedVersion).value ?? SemanticVersion(major: 0, minor: 0, patch: 0)

	// Try higher versions first.
	return leftSemantic > rightSemantic
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
