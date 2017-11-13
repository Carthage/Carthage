import CarthageKit
import Nimble
import Quick

class AlgorithmsSpec: QuickSpec {
	override func spec() {
		typealias Graph = [String: Set<String>]

		var validGraph: Graph = [:]
		var cycleGraph: Graph = [:]
		var malformedGraph: Graph = [:]

		beforeEach {
			validGraph["Argo"] = Set([])
			validGraph["Commandant"] = Set(["Result"])
			validGraph["PrettyColors"] = Set([])
			validGraph["Carthage"] = Set(["Argo", "Commandant", "PrettyColors", "ReactiveCocoa", "ReactiveTask"])
			validGraph["ReactiveCocoa"] = Set(["Result"])
			validGraph["ReactiveTask"] = Set(["ReactiveCocoa"])
			validGraph["Result"] = Set()

			cycleGraph["A"] = Set(["B"])
			cycleGraph["B"] = Set(["C"])
			cycleGraph["C"] = Set(["A"])

			malformedGraph["A"] = Set(["B"])
		}

		describe("sorting") {
			it("should sort first by dependency and second by comparability") {
				let sorted = topologicalSort(validGraph)

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

			context("when filtering") {
				it("should only include the provided node and its transitive dependencies") {
					let sorted = topologicalSort(validGraph, nodes: Set(["ReactiveTask"]))

					expect(sorted) == [
						"Result",
						"ReactiveCocoa",
						"ReactiveTask",
					]
				}

				it("should only include provided nodes and their transitive dependencies") {
					let sorted = topologicalSort(validGraph, nodes: Set(["ReactiveTask", "Commandant"]))

					expect(sorted) == [
						"Result",
						"Commandant",
						"ReactiveCocoa",
						"ReactiveTask",
					]
				}

				it("should only include provided nodes and their transitive dependencies") {
					let sorted = topologicalSort(validGraph, nodes: Set(["Carthage"]))

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

				it("should perform a topological sort on the provided graph when the set is empty") {
					let sorted = topologicalSort(validGraph, nodes: Set())

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
		}

		describe("cycles") {
			it("should fail when there is a cycle in the input graph") {
				let sorted = topologicalSort(cycleGraph)

				expect(sorted).to(beNil())
			}

			context("when filtering") {
				it("should fail when there is a cycle in the input graph") {
					let sorted = topologicalSort(cycleGraph, nodes: Set(["B"]))

					expect(sorted).to(beNil())
				}
			}
		}

		describe("malformed inputs") {
			it("should fail when the input graph is missing nodes") {
				let sorted = topologicalSort(malformedGraph)

				expect(sorted).to(beNil())
			}

			context("when filtering") {
				it("should fail when the input graph is missing nodes") {
					let sorted = topologicalSort(malformedGraph, nodes: Set(["A"]))

					expect(sorted).to(beNil())
				}
			}
		}
	}
}
