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
/// A ◀─── B
/// ▲      ▲
/// │      │
/// C ◀─── D
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
public func topologicalSort<Node: Comparable>(var edges: Dictionary<Node, Set<Node>>) -> [Node]? {
	var queue: [Node] = edges
		.filter { _, edges in edges.isEmpty }
		.map { node, _ in node }

	queue.forEach { node in edges.removeValueForKey(node) }

	var sorted: [Node] = []

	while !queue.isEmpty {
		queue.sortInPlace(>)

		let lastNode = queue.removeLast()
		sorted.append(lastNode)

		for (node, inEdges) in edges {
			guard inEdges.contains(lastNode) else { continue }

			let filteredInEdges = inEdges.subtract([lastNode])
			edges[node] = filteredInEdges

			guard filteredInEdges.isEmpty else { continue }
			queue.append(node)
			edges.removeValueForKey(node)
		}
	}

	return edges.isEmpty ? sorted : nil
}
