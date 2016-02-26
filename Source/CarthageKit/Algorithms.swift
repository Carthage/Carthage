//
//  Algorithms.swift
//  Carthage
//
//  Created by Eric Horacek on 2/19/16.
//  Copyright © 2016 Carthage. All rights reserved.
//

/// Returns an array containing the topologically sorted nodes of the provided
/// directed graph, or nil if the graph contains a cycle or is malformed.
///
/// The sort is performed using
/// [Khan's Algorithm](https://en.wikipedia.org/wiki/Topological_sorting#Kahn.27s_algorithm).
///
/// The provided graph should be encoded as a dictionary where:
/// - The keys are the nodes of the graph
/// - The values are the set of nodes that the key node has a incoming edge from
///
/// For example, the following graph:
/// ```
/// A <-- B
/// ^     ^
/// |     |
/// C <-- D
/// ```
/// should be encoded as:
/// ```
/// [ A: Set([B, C]), B: Set([D]), C: Set([D]), D: Set() ]
/// ```
/// and would be sorted as:
/// ```
/// [D, B, C, A]
/// ```
///
/// Nodes that are equal from a topological perspective are sorted by the
/// strict total order as defined by `Comparable`.
public func topologicalSort<Node: Comparable>(graph: Dictionary<Node, Set<Node>>) -> [Node]? {
	// Maintain a list of nodes with no incoming edges (sources).
	var sources = graph
		.filter { _, incomingEdges in incomingEdges.isEmpty }
		.map { node, _ in node }

	// Maintain a working graph with all sources removed.
	var workingGraph = graph
	sources.forEach { node in workingGraph.removeValueForKey(node) }

	var sorted: [Node] = []

	while !sources.isEmpty {
		sources.sortInPlace(>)

		let lastSource = sources.removeLast()
		sorted.append(lastSource)

		for (node, var incomingEdges) in workingGraph where incomingEdges.contains(lastSource) {
			incomingEdges.remove(lastSource)
			workingGraph[node] = incomingEdges

			if incomingEdges.isEmpty {
				sources.append(node)
				workingGraph.removeValueForKey(node)
			}
		}
	}

	return workingGraph.isEmpty ? sorted : nil
}

/// Performs a topological sort on the provided graph with its output sorted to
/// include only the provided set of nodes and their transitively incoming 
/// nodes (dependencies).
public func topologicalSort<Node: Comparable>(graph: Dictionary<Node, Set<Node>>, nodes: Set<Node>) -> [Node]? {
	if nodes.isEmpty { return topologicalSort(graph) }

	guard nodes.isSubsetOf(Set(graph.keys)) else { return nil }

	// Ensure that the graph has no cycles, otherwise determining the set of 
	// incoming nodes could infinitely recurse.
	guard let _ = topologicalSort(graph) else { return nil }

	func transitiveIncomingNodes(graph: Dictionary<Node, Set<Node>>, node: Node) -> Set<Node> {
		guard let nodes = graph[node] else { return Set() }
		return nodes.union(Set(nodes.flatMap { transitiveIncomingNodes(graph, node: $0) }))
	}

	let relevantNodes = Set(nodes.flatMap { node in Set([node]).union(transitiveIncomingNodes(graph, node: node)) })

	let irrelevantNodes = graph
		.filter { node, _ in return !relevantNodes.contains(node) }
		.map { node, _ in node }

	var filteredGraph = graph
	irrelevantNodes.forEach { node in filteredGraph.removeValueForKey(node) }

	return topologicalSort(filteredGraph)
}
