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

private typealias SemanticVersionSet = [SemanticVersion: ()]
private typealias DependencyVersionMap = [DependencyIdentifier: SemanticVersionSet]

/// Looks up all dependencies (and nested dependencies) from the given Cartfile,
/// and what versions are available for each.
private func versionMapForCartfile(cartfile: Cartfile) -> ColdSignal<DependencyVersionMap> {
	return ColdSignal.fromValues(cartfile.dependencies)
		.map { dependency -> ColdSignal<DependencyVersionMap> in
			return versionsForDependency(dependency.identifier)
				.map { version -> ColdSignal<DependencyVersionMap> in
					let pinnedDependency = dependency.map { _ in version }
					let recursiveVersionMap = dependencyCartfile(pinnedDependency)
						.map { cartfile in versionMapForCartfile(cartfile) }
						.merge(identity)

					return ColdSignal.single([ dependency.identifier: [ version: () ] ])
						.concat(recursiveVersionMap)
				}
				.merge(identity)
		}
		.merge(identity)
		.reduce(initial: [:]) { (var left, right) -> DependencyVersionMap in
			for (repo, rightVersions) in right {
				left[repo] = combineDictionaries(left[repo] ?? [:], rightVersions)
			}

			return left
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
				} else {
					println("Couldn't reconcile \(existingNode) with \(node)")
					// TODO: Real error message.
					return failure()
				}
			} else {
				println("Couldn't reconcile \(existingNode) with \(node)")
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

extension ColdSignal {
	/// Sends each value that occurs on the receiver combined with each value
	/// that occurs on the given signal (repeats included).
	private func permuteWith<U>(signal: ColdSignal<U>) -> ColdSignal<(T, U)> {
		return ColdSignal<(T, U)> { subscriber in
			let queue = dispatch_queue_create("org.reactivecocoa.ReactiveCocoa.ColdSignal.recombineWith", DISPATCH_QUEUE_SERIAL)
			var selfValues: [T] = []
			var selfCompleted = false
			var otherValues: [U] = []
			var otherCompleted = false

			let selfDisposable = self.start(next: { value in
				dispatch_sync(queue) {
					selfValues.append(value)

					for otherValue in otherValues {
						subscriber.put(.Next(Box((value, otherValue))))
					}
				}
			}, error: { error in
				subscriber.put(.Error(error))
			}, completed: {
				dispatch_sync(queue) {
					selfCompleted = true
					if otherCompleted {
						subscriber.put(.Completed)
					}
				}
			})

			subscriber.disposable.addDisposable(selfDisposable)

			let otherDisposable = signal.start(next: { value in
				dispatch_sync(queue) {
					otherValues.append(value)

					for selfValue in selfValues {
						subscriber.put(.Next(Box((selfValue, value))))
					}
				}
			}, error: { error in
				subscriber.put(.Error(error))
			}, completed: {
				dispatch_sync(queue) {
					otherCompleted = true
					if selfCompleted {
						subscriber.put(.Completed)
					}
				}
			})

			subscriber.disposable.addDisposable(otherDisposable)
		}
	}
}

/// Sends all permutations of the values from the input signals, as they arrive.
///
/// If no input signals are given, sends a single empty array then completes.
private func permutations<T>(signals: [ColdSignal<T>]) -> ColdSignal<[T]> {
	var combined: ColdSignal<[T]> = .single([])

	for signal in signals {
		combined = combined.permuteWith(signal).map { (var array, value) in
			array.append(value)
			return array
		}
	}

	return combined
}

private func nodePermutationsForCartfile(cartfile: Cartfile) -> ColdSignal<[DependencyNode]> {
	let nodeSignals = cartfile.dependencies.map { dependency -> ColdSignal<DependencyNode> in
		// TODO: If this signal is empty (because no version meets the
		// specifier), we'll never have any permutations, so we need to generate
		// an error.
		return versionsForDependency(dependency.identifier)
			.filter { dependency.version.satisfiedBy($0) }
			.map { DependencyNode(identifier: dependency.identifier, proposedVersion: $0, versionSpecifier: dependency.version) }
			.reduce(initial: []) { $0 + [ $1 ] }
			.map(sorted)
			.map(ColdSignal.fromValues)
			.concat(identity)
	}

	return permutations(nodeSignals)
}

private func graphPermutationsForDependenciesOfNode(node: DependencyNode, inputGraph: DependencyGraph) -> ColdSignal<DependencyGraph> {
	return dependencyCartfile(node.dependencyVersion)
		.map(nodePermutationsForCartfile)
		.merge(identity)
		.map { dependencyNodes in graphPermutationsForEachNode(dependencyNodes, inputGraph, dependencyOf: node) }
		.merge(identity)
}

private func graphPermutationsForEachNode(nodes: [DependencyNode], inputGraph: DependencyGraph, #dependencyOf: DependencyNode?) -> ColdSignal<DependencyGraph> {
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
				let graphSignals = nodes.map { node in graphPermutationsForDependenciesOfNode(node, graph) }

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

/// Attempts to determine the latest valid version to use for each dependency
/// specified in the given Cartfile, and all nested dependencies thereof.
///
/// Sends each recursive dependency with its resolved version, in no particular
/// order.
public func resolveDependencesInCartfile(cartfile: Cartfile) -> ColdSignal<DependencyVersion<SemanticVersion>> {
	// Dependency graph permutations for each of the root nodes' versions.
	let graphPermutations = nodePermutationsForCartfile(cartfile)
		.map { rootNodes in graphPermutationsForEachNode(rootNodes, DependencyGraph(), dependencyOf: nil) }
		.merge(identity)

	return graphPermutations
		.on(next: { graph in
			println("*** POSSIBLE GRAPH ***\n\(graph)\n")
		})
		// TODO: Real error here.
		.concat(.error(RACError.Empty.error))
		.take(1)
		.map { graph -> ColdSignal<DependencyVersion<SemanticVersion>> in
			return ColdSignal.fromValues(graph.allNodes.keys)
				.map { node in node.dependencyVersion }
		}
		.merge(identity)
}
