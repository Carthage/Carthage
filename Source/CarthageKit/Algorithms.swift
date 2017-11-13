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
public func topologicalSort<Node: Comparable>(_ graph: [Node: Set<Node>]) -> [Node]? {
	// Maintain a list of nodes with no incoming edges (sources).
	var sources = graph
		.filter { _, incomingEdges in incomingEdges.isEmpty }
		.map { node, _ in node }

	// Maintain a working graph with all sources removed.
	var workingGraph = graph
	for node in sources {
		workingGraph.removeValue(forKey: node)
	}

	var sorted: [Node] = []

	while !sources.isEmpty {
		sources.sort(by: >)

		let lastSource = sources.removeLast()
		sorted.append(lastSource)

		for (node, var incomingEdges) in workingGraph where incomingEdges.contains(lastSource) {
			incomingEdges.remove(lastSource)
			workingGraph[node] = incomingEdges

			if incomingEdges.isEmpty {
				sources.append(node)
				workingGraph.removeValue(forKey: node)
			}
		}
	}

	return workingGraph.isEmpty ? sorted : nil
}

/// Performs a topological sort on the provided graph with its output sorted to
/// include only the provided set of nodes and their transitively incoming 
/// nodes (dependencies).
///
/// If the provided `nodes` set is empty, returns the result of invoking
/// `topologicalSort()` with the provided graph.
///
/// Throws an exception if the provided node(s) are not contained within the 
/// given graph.
///
/// Returns nil if the provided graph has a cycle or is malformed.
public func topologicalSort<Node: Comparable>(_ graph: [Node: Set<Node>], nodes: Set<Node>) -> [Node]? {
	guard !nodes.isEmpty else {
		return topologicalSort(graph)
	}

	precondition(nodes.isSubset(of: Set(graph.keys)))

	// Ensure that the graph has no cycles, otherwise determining the set of 
	// transitive incoming nodes could infinitely recurse.
	guard let sorted = topologicalSort(graph) else {
		return nil
	}

	let relevantNodes = Set(nodes.flatMap { Set([$0]).union(transitiveIncomingNodes(graph, node: $0)) })

	return sorted.filter { node in relevantNodes.contains(node) }
}

/// Returns the set of nodes that the given node in the provided graph has as
/// its incoming nodes, both directly and transitively.
private func transitiveIncomingNodes<Node: Equatable>(_ graph: [Node: Set<Node>], node: Node) -> Set<Node> {
	guard let nodes = graph[node] else {
		return Set()
	}

	let incomingNodes = Set(nodes.flatMap { transitiveIncomingNodes(graph, node: $0) })

	return nodes.union(incomingNodes)
}
