//
//  AlgorithmsSpec.swift
//  Carthage
//
//  Created by Eric Horacek on 2/19/16.
//  Copyright © 2016 Carthage. All rights reserved.
//

import CarthageKit
import Nimble
import Quick

class AlgorithmsSpec: QuickSpec {
	override func spec() {
		describe("sorting") {
			it("should sort first by dependency and second by comparability") {
				var graph: [String: Set<String>] = [:]

				graph["Argo"] = Set([])
				graph["Commandant"] = Set(["Result"])
				graph["PrettyColors"] = Set([])
				graph["Carthage"] = Set(["Argo", "Commandant", "ReactiveCocoa", "ReactiveTask"])
				graph["ReactiveCocoa"] = Set(["Result"])
				graph["ReactiveTask"] = Set(["ReactiveCocoa"])
				graph["Result"] = Set()

				let sorted = topologicalSort(graph)

				expect(sorted) == [
					"Argo",
					"PrettyColors",
					"Result",
					"Commandant",
					"ReactiveCocoa",
					"ReactiveTask",
					"Carthage",
				]
			}
		}

		describe("filtered sorting") {
			it("should only include the provided nodes and their dependencies") {
				var graph: [String: Set<String>] = [:]

				graph["Argo"] = Set([])
				graph["Commandant"] = Set(["Result"])
				graph["PrettyColors"] = Set([])
				graph["Carthage"] = Set(["Argo", "Commandant", "ReactiveCocoa", "ReactiveTask"])
				graph["ReactiveCocoa"] = Set(["Result"])
				graph["ReactiveTask"] = Set(["ReactiveCocoa"])
				graph["Result"] = Set()

				let sorted = topologicalSort(graph, nodes: Set(["ReactiveTask"]))

				expect(sorted) == [
					"Result",
					"ReactiveCocoa",
					"ReactiveTask",
				]
			}
		}

		describe("cycles") {
			it("should fail when there is a cycle in the input graph", closure: {
				var graph: [String: Set<String>] = [:]

				graph["A"] = Set(["B"])
				graph["B"] = Set(["C"])
				graph["C"] = Set(["A"])

				let sorted = topologicalSort(graph)

				expect(sorted).to(beNil())
			})
		}

		describe("malformed inputs") {
			it("should fail when the input graph is missing nodes", closure: {
				var graph: [String: Set<String>] = [:]

				graph["A"] = Set(["B"])

				let sorted = topologicalSort(graph)

				expect(sorted).to(beNil())
			})
		}
	}
}
