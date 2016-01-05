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
	public func resolveDependenciesInCartfile(cartfile: Cartfile, lastResolved: ResolvedCartfile? = nil, dependenciesToUpdate: [String]? = nil) -> SignalProducer<Dependency<PinnedVersion>, CarthageError> {
		return resolveDependenciesFromNodePermutations(nodePermutationsForCartfile(cartfile))
			.flatMap(.Merge) { graph -> SignalProducer<Dependency<PinnedVersion>, CarthageError> in
				let orderedNodes = graph.orderedNodes.map { node -> DependencyNode in
					node.dependencies = graph.edges[node] ?? []
					return node
				}
				let orderedNodesProducer = SignalProducer<DependencyNode, CarthageError>(values: orderedNodes)

				guard
					let dependenciesToUpdate = dependenciesToUpdate,
					let lastResolved = lastResolved
					where !dependenciesToUpdate.isEmpty else {
					// All the dependencies are affected.
					return orderedNodesProducer.map { node in node.dependencyVersion }
				}

				// When target dependencies are specified
				return orderedNodesProducer.map { node -> Dependency<PinnedVersion>? in
					// A dependency included in the targets should be affected.
					if dependenciesToUpdate.contains(node.project.name) {
						return node.dependencyVersion
					}

					// Nested dependencies of the targets should also be affected.
					if graph.dependencies(dependenciesToUpdate, containsNestedDependencyOfNode: node) {
						return node.dependencyVersion
					}

					// The dependencies which are not related to the targets
					// should not be affected, so use the version in the last
					// Cartfile.resolved.
					if let dependencyForProject = lastResolved.dependencyForProject(node.project) {
						return dependencyForProject
					}

					// Skip newly added nodes which are not in the targets.
					return nil
				}
				.ignoreNil()
			}
	}

	/// Attempts to determine the build order for the resolved dependencies,
	/// optionally they are limited by the given list of dependency names.
	///
	/// Sends each recursive dependency with its already resolved version, in the
	/// order that they should be built.
	public func resolveDependenciesInResolvedCartfile(resolvedCartfile: ResolvedCartfile, dependenciesToResolve: [String]? = nil) -> SignalProducer<Dependency<PinnedVersion>, CarthageError> {
		let nodes = resolvedCartfile.dependencies.map {
			DependencyNode(
				project: $0.project,
				proposedVersion: $0.version,
				versionSpecifier: .GitReference($0.version.commitish)
			)
		}
		return resolveDependenciesFromNodePermutations(SignalProducer(value: nodes))
			.flatMap(.Merge) { graph -> SignalProducer<Dependency<PinnedVersion>, CarthageError> in
				let dependencies = graph.orderedNodes.map { node -> DependencyNode in
					node.dependencies = graph.edges[node] ?? []
					return node
				}

				guard let dependenciesToResolve = dependenciesToResolve where !dependenciesToResolve.isEmpty else {
					return .init(values: dependencies.map { $0.dependencyVersion })
				}

				var toResolve = Set(dependenciesToResolve)

				dependencies
					.filter { toResolve.contains($0.project.name) }
					.forEach { toResolve.unionInPlace($0.dependencies.map { $0.project.name }) }

				let filtered = dependencies
					.filter { toResolve.contains($0.project.name) }
					.map { $0.dependencyVersion }
				return .init(values: filtered)
			}
	}

	private func resolveDependenciesFromNodePermutations(permutationsProducer: SignalProducer<[DependencyNode], CarthageError>) -> SignalProducer<DependencyGraph, CarthageError> {
		return permutationsProducer
			.flatMap(.Concat) { rootNodes -> SignalProducer<Event<DependencyGraph, CarthageError>, CarthageError> in
				return self.graphPermutationsForEachNode(rootNodes, dependencyOf: nil, basedOnGraph: DependencyGraph())
					.promoteErrors(CarthageError.self)
			}
			// Pass through resolution errors only if we never got
			// a valid graph.
			.dematerializeErrorsIfEmpty()
			.take(1)
			.observeOn(QueueScheduler(queue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), name: "org.carthage.CarthageKit.Resolver.resolveDependencesInCartfile"))
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
		let scheduler = QueueScheduler(queue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), name: "org.carthage.CarthageKit.Resolver.nodePermutationsForCartfile")

		return SignalProducer(values: cartfile.dependencies)
			.map { dependency -> SignalProducer<DependencyNode, CarthageError> in
				let allowedVersions = SignalProducer<String?, CarthageError>.attempt {
						switch dependency.version {
						case let .GitReference(refName):
							return .Success(refName)

						default:
							return .Success(nil)
						}
					}
					.flatMap(.Concat) { refName -> SignalProducer<PinnedVersion, CarthageError> in
						if let refName = refName {
							return self.resolvedGitReference(dependency.project, refName)
						}

						return self.versionsForDependency(dependency.project)
							.collect()
							.flatMap(.Merge) { nodes -> SignalProducer<PinnedVersion, CarthageError> in
								if nodes.isEmpty {
									return SignalProducer(error: CarthageError.TaggedVersionNotFound(dependency.project))
								} else {
									return SignalProducer(values: nodes)
								}
							}
							.filter { dependency.version.satisfiedBy($0) }
					}

				return allowedVersions
					.startOn(scheduler)
					.observeOn(scheduler)
					.map { DependencyNode(project: dependency.project, proposedVersion: $0, versionSpecifier: dependency.version) }
					.collect()
					.map { $0.sort() }
					.flatMap(.Concat) { nodes -> SignalProducer<DependencyNode, CarthageError> in
						if nodes.isEmpty {
							return SignalProducer(error: CarthageError.RequiredVersionNotFound(dependency.project, dependency.version))
						} else {
							return SignalProducer(values: nodes)
						}
					}
			}
			.collect()
			.observeOn(scheduler)
			.flatMap(.Concat) { nodeProducers in permutations(nodeProducers) }
	}

	/// Sends all possible permutations of `inputGraph` oriented around the
	/// dependencies of `node`.
	///
	/// In other words, this attempts to create one transformed graph for each
	/// possible permutation of the dependencies for the given node (chosen from
	/// among the verisons that actually exist for each).
	private func graphPermutationsForDependenciesOfNode(node: DependencyNode, basedOnGraph inputGraph: DependencyGraph) -> SignalProducer<DependencyGraph, CarthageError> {
		let scheduler = QueueScheduler(queue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), name: "org.carthage.CarthageKit.Resolver.graphPermutationsForDependenciesOfNode")

		return cartfileForDependency(node.dependencyVersion)
			.startOn(scheduler)
			.concat(SignalProducer(value: Cartfile(dependencies: [])))
			.take(1)
			.observeOn(scheduler)
			.flatMap(.Merge) { self.nodePermutationsForCartfile($0) }
			.flatMap(.Concat) { dependencyNodes in
				return self.graphPermutationsForEachNode(dependencyNodes, dependencyOf: node, basedOnGraph: inputGraph)
					.promoteErrors(CarthageError.self)
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
	private func graphPermutationsForEachNode(nodes: [DependencyNode], dependencyOf: DependencyNode?, basedOnGraph inputGraph: DependencyGraph) -> SignalProducer<Event<DependencyGraph, CarthageError>, NoError> {
		return SignalProducer<(DependencyGraph, [DependencyNode]), CarthageError> { observer, disposable in
				var graph = inputGraph
				var newNodes: [DependencyNode] = []

				for node in nodes {
					if disposable.disposed {
						return
					}

					switch graph.addNode(node, dependencyOf: dependencyOf) {
					case let .Success(newNode):
						newNodes.append(newNode)

					case let .Failure(error):
						observer.sendFailed(error)
						return
					}
				}

				observer.sendNext((graph, newNodes))
				observer.sendCompleted()
			}
			.flatMap(.Concat) { graph, nodes -> SignalProducer<DependencyGraph, CarthageError> in
				return SignalProducer(values: nodes)
					// Each producer represents all evaluations of one subtree.
					.map { node in self.graphPermutationsForDependenciesOfNode(node, basedOnGraph: graph) }
					.collect()
					.observeOn(QueueScheduler(queue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), name: "org.carthage.CarthageKit.Resolver.graphPermutationsForEachNode"))
					.flatMap(.Concat) { graphProducers in permutations(graphProducers) }
					.flatMap(.Concat) { graphs -> SignalProducer<Event<DependencyGraph, CarthageError>, CarthageError> in
						let mergedGraphs = SignalProducer(values: graphs)
							.scan(Result<DependencyGraph, CarthageError>.Success(inputGraph)) { result, nextGraph in
								return result.flatMap { previousGraph in mergeGraphs(previousGraph, nextGraph) }
							}
							.attemptMap { $0 }

						return SignalProducer(value: inputGraph)
							.concat(mergedGraphs)
							.takeLast(1)
							.materialize()
							.promoteErrors(CarthageError.self)
					}
					// Pass through resolution errors only if we never got
					// a valid graph.
					.dematerializeErrorsIfEmpty()
			}
			.materialize()
	}
}

/// Represents an acyclic dependency graph in which each project appears at most
/// once.
///
/// Dependency graphs can exist in an incomplete state, but will never be
/// inconsistent (i.e., include versions that are known to be invalid given the
/// current graph).
private struct DependencyGraph: Equatable {
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
		return allNodes.sort { lhs, rhs in
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
	mutating func addNode(node: DependencyNode, dependencyOf: DependencyNode?) -> Result<DependencyNode, CarthageError> {
		var node = node

		if let index = allNodes.indexOf(node) {
			let existingNode = allNodes[index]

			if let newSpecifier = intersection(existingNode.versionSpecifier, node.versionSpecifier) {
				if newSpecifier.satisfiedBy(existingNode.proposedVersion) {
					node = existingNode
					node.versionSpecifier = newSpecifier
				} else {
					return .Failure(CarthageError.RequiredVersionNotFound(node.project, newSpecifier))
				}
			} else {
				return .Failure(CarthageError.IncompatibleRequirements(node.project, existingNode.versionSpecifier, node.versionSpecifier))
			}
		} else {
			allNodes.insert(node)
		}

		if let dependencyOf = dependencyOf {
			var nodeSet = edges[dependencyOf] ?? Set()
			nodeSet.insert(node)

			// If the given node has its dependencies, add them also to the list.
			if let dependenciesOfNode = edges[node] {
				nodeSet.unionInPlace(dependenciesOfNode)
			}

			edges[dependencyOf] = nodeSet

			// Add a nested dependency to the list of its ancestor.
			let edgesCopy = edges
			for (ancestor, itsDependencies) in edgesCopy {
				var itsDependencies = itsDependencies
				if itsDependencies.contains(dependencyOf) {
					itsDependencies.insert(node)
					edges[ancestor] = itsDependencies
				}
			}
		} else {
			roots.insert(node)
		}

		return .Success(node)
	}

	/// Whether the given node is included or not in the nested dependencies of
	/// the given dependencies.
	func dependencies(dependencies: [String], containsNestedDependencyOfNode node: DependencyNode) -> Bool {
		return edges.lazy
			.filter { edge, nodeSet in
				return dependencies.contains(edge.project.name) && nodeSet.contains(node)
			}
			.map { _ in true }
			.first ?? false
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

extension DependencyGraph: CustomStringConvertible {
	private var description: String {
		var str = "Roots:"

		for root in roots {
			str += "\n\t\(root)"
		}

		str += "\n\nEdges:"

		for (node, dependencies) in edges {
			str += "\n\t\(node.project) ->"
			for dep in dependencies {
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
private func mergeGraphs(lhs: DependencyGraph, _ rhs: DependencyGraph) -> Result<DependencyGraph, CarthageError> {
	var result: Result<DependencyGraph, CarthageError> = .Success(lhs)

	for root in rhs.roots {
		result = result.flatMap { graph in
			var graph = graph
			return graph.addNode(root, dependencyOf: nil).map { _ in graph }
		}
	}

	for (node, dependencies) in rhs.edges {
		for dependency in dependencies {
			result = result.flatMap { graph in
				var graph = graph
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

	/// The dependencies of this node.
	var dependencies: Set<DependencyNode> = []

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

extension DependencyNode: CustomStringConvertible {
	private var description: String {
		return "\(project) @ \(proposedVersion) (restricted to \(versionSpecifier))"
	}
}
