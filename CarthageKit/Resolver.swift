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
	private let versionsForDependency: DependencyIdentifier -> ColdSignal<SemanticVersion>
	private let cartfileForDependency: DependencyVersion<SemanticVersion> -> ColdSignal<Cartfile>

	/// Instantiates a dependency graph resolver with the given behaviors.
	///
	/// versionsForDependency - Sends a stream of available SemanticVersions
	///                         for a dependency.
	/// cartfileForDependency - Loads the Cartfile for a specific version of a
	///                         dependency.
	public init(versionsForDependency: DependencyIdentifier -> ColdSignal<SemanticVersion>, cartfileForDependency: DependencyVersion<SemanticVersion> -> ColdSignal<Cartfile>) {
		self.versionsForDependency = versionsForDependency
		self.cartfileForDependency = cartfileForDependency
	}

	/// Attempts to determine the latest valid version to use for each dependency
	/// specified in the given Cartfile, and all nested dependencies thereof.
	///
	/// Sends each recursive dependency with its resolved version, in no particular
	/// order.
	public func resolveDependencesInCartfile(cartfile: Cartfile) -> ColdSignal<DependencyVersion<SemanticVersion>> {
		// Dependency graph permutations for each of the root nodes' versions.
		let graphPermutations = nodePermutationsForCartfile(cartfile)
			.map { rootNodes in self.graphPermutationsForEachNode(rootNodes, dependencyOf: nil, basedOnGraph: DependencyGraph()) }
			.merge(identity)

		return graphPermutations
			// TODO: Real error here.
			.concat(.error(RACError.Empty.error))
			.take(1)
			.map { graph -> ColdSignal<DependencyVersion<SemanticVersion>> in
				return ColdSignal.fromValues(graph.allNodes.keys)
					.map { node in node.dependencyVersion }
			}
			.merge(identity)
	}

	private func nodePermutationsForCartfile(cartfile: Cartfile) -> ColdSignal<[DependencyNode]> {
		let nodeSignals = cartfile.dependencies.map { dependency -> ColdSignal<DependencyNode> in
			// TODO: If this signal is empty (because no version meets the
			// specifier), we'll never have any permutations, so we need to generate
			// an error.
			return self.versionsForDependency(dependency.identifier)
				.filter { dependency.version.satisfiedBy($0) }
				.map { DependencyNode(identifier: dependency.identifier, proposedVersion: $0, versionSpecifier: dependency.version) }
				.reduce(initial: []) { $0 + [ $1 ] }
				.map(sorted)
				.map(ColdSignal.fromValues)
				.concat(identity)
		}

		return permutations(nodeSignals)
	}

	private func graphPermutationsForDependenciesOfNode(node: DependencyNode, basedOnGraph inputGraph: DependencyGraph) -> ColdSignal<DependencyGraph> {
		return cartfileForDependency(node.dependencyVersion)
			.map { self.nodePermutationsForCartfile($0) }
			.merge(identity)
			.map { dependencyNodes in self.graphPermutationsForEachNode(dependencyNodes, dependencyOf: node, basedOnGraph: inputGraph) }
			.merge(identity)
	}

	private func graphPermutationsForEachNode(nodes: [DependencyNode], dependencyOf: DependencyNode?, basedOnGraph inputGraph: DependencyGraph) -> ColdSignal<DependencyGraph> {
		return ColdSignal.lazy {
			var result = success(inputGraph)

			for node in nodes {
				result = result.flatMap { (var graph) in
					return graph.addNode(node, dependencyOf: dependencyOf)
						.map { _ in graph }
				}
			}

			return ColdSignal.fromResult(result)
				// Discard impossible graphs.
				.catch { _ in .empty() }
				.map { graph -> ColdSignal<DependencyGraph> in
					// Each signal represents all evaluations of one subtree.
					let graphSignals = nodes.map { node in self.graphPermutationsForDependenciesOfNode(node, basedOnGraph: graph) }

					return permutations(graphSignals)
						.map { graphs -> ColdSignal<DependencyGraph> in
							let result = reduce(graphs, success(inputGraph)) { (result, graph) in
								return result.flatMap { mergeGraphs($0, graph) }
							}

							switch result {
							case let .Success(graph):
								return .single(graph.unbox)

							case .Failure:
								// Discard impossible graphs.
								return .empty()
							}
						}
						.merge(identity)
				}
				.merge(identity)
		}
	}
}

private class DependencyNode: Comparable {
	let identifier: DependencyIdentifier
	let proposedVersion: SemanticVersion
	var versionSpecifier: VersionSpecifier

	var dependencyVersion: DependencyVersion<SemanticVersion> {
		return DependencyVersion(identifier: identifier, version: proposedVersion)
	}

	init(identifier: DependencyIdentifier, proposedVersion: SemanticVersion, versionSpecifier: VersionSpecifier) {
		precondition(versionSpecifier.satisfiedBy(proposedVersion))

		self.identifier = identifier
		self.proposedVersion = proposedVersion
		self.versionSpecifier = versionSpecifier
	}
}

private func <(lhs: DependencyNode, rhs: DependencyNode) -> Bool {
	// Try higher versions first.
	return lhs.proposedVersion > rhs.proposedVersion
}

private func ==(lhs: DependencyNode, rhs: DependencyNode) -> Bool {
	return lhs.identifier == rhs.identifier
}

extension DependencyNode: Hashable {
	private var hashValue: Int {
		return identifier.hashValue
	}
}

extension DependencyNode: Printable {
	private var description: String {
		return "\(identifier) @ \(proposedVersion) (restricted to \(versionSpecifier))"
	}
}

private typealias DependencyNodeSet = [DependencyNode: ()]

private struct DependencyGraph: Equatable {
	var allNodes: DependencyNodeSet = [:]
	var edges: [DependencyNode: DependencyNodeSet] = [:]
	var roots: DependencyNodeSet = [:]

	init() {}

	mutating func addNode(var node: DependencyNode, dependencyOf: DependencyNode?) -> Result<DependencyNode> {
		if let index = allNodes.indexForKey(node) {
			let existingNode = allNodes[index].0

			if let newSpecifier = intersection(existingNode.versionSpecifier, node.versionSpecifier) {
				if newSpecifier.satisfiedBy(existingNode.proposedVersion) {
					node = existingNode
					node.versionSpecifier = newSpecifier
				} else {
					// TODO: Real error message.
					return failure()
				}
			} else {
				// TODO: Real error message.
				return failure()
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
			str += "\n\t\(node.identifier) ->"
			for (dep, _) in dependencies {
				str += "\n\t\t\(dep)"
			}
		}

		return str
	}
}
