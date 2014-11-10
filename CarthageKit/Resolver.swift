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

typealias DependencyVersionMap = [DependencyIdentifier: [SemanticVersion]]

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

					return ColdSignal.single([ dependency.identifier: [ version ] ])
						.concat(recursiveVersionMap)
				}
				.merge(identity)
		}
		.merge(identity)
		.reduce(initial: [:]) { (var left, right) -> DependencyVersionMap in
			for (repo, rightVersions) in right {
				if let leftVersions = left[repo] {
					// FIXME: We should just use a set.
					left[repo] = leftVersions + rightVersions.filter { !contains(leftVersions, $0) }
				} else {
					left[repo] = rightVersions
				}
			}

			return left
		}
}

/// Represents a node in a dependency resolution graph, which consists of
/// _proposed_ versions for dependencies, and may therefore specify combinations
/// that could eventually be disallowed (due to conflicting requirements).
///
/// Completed graphs should contain exactly one node for each dependency.
private class DependencyNode: Equatable {
	/// The dependency represented by this node.
	let identifier: DependencyIdentifier

	/// The version chosen for this node, which may or may not be a valid
	/// selection.
	let version: SemanticVersion

	/// The dependencies that this node has.
	var dependencies: [DependencyNode] = []

	/// The DependencyVersion corresponding to this node.
	var dependencyVersion: DependencyVersion<SemanticVersion> {
		return DependencyVersion(identifier: identifier, version: version)
	}

	init(identifier: DependencyIdentifier, version: SemanticVersion) {
		self.identifier = identifier
		self.version = version
	}
}

private func ==(lhs: DependencyNode, rhs: DependencyNode) -> Bool {
	return lhs.identifier == rhs.identifier && lhs.version == rhs.version
}

extension DependencyNode: Hashable {
	private var hashValue: Int {
		return identifier.hashValue
	}
}

extension DependencyNode: Printable {
	private var description: String {
		var str = "\(identifier) @ \(version)"

		if dependencies.count > 0 {
			str += " ->"

			for dependency in dependencies {
				(dependency.description as NSString).enumerateLinesUsingBlock { (line, stop) in
					str += "\n\t\(line)"
				}
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

/// Creates one or more dependency graphs for the given dependency,
/// incorporating all known versions of each recursive dependency.
private func graphsForDependencyVersion(dependency: DependencyVersion<SemanticVersion>, versionMap: DependencyVersionMap) -> ColdSignal<DependencyNode> {
	let templateNode = DependencyNode(identifier: dependency.identifier, version: dependency.version)

	return dependencyCartfile(dependency)
		.map { cartfile -> ColdSignal<DependencyNode> in
			let nodeSignals = cartfile.dependencies.map { dependency -> ColdSignal<DependencyNode> in
				let versions = versionMap[dependency.identifier]!

				return ColdSignal.fromValues(versions)
					.map { version -> ColdSignal<DependencyNode> in
						let dependencyVersion = dependency.map { _ in version }
						return graphsForDependencyVersion(dependencyVersion, versionMap)
					}
					.merge(identity)
			}

			return permutations(nodeSignals)
				.map { dependencyNodes in
					var parentNode = templateNode
					parentNode.dependencies = dependencyNodes
					return parentNode
				}
		}
		.merge(identity)
}

private func graphsForVersionMap(versionMap: DependencyVersionMap, roots: [DependencyIdentifier]) -> ColdSignal<DependencyNode> {
	let dependencies = versionMap.keys

	return ColdSignal { subscriber in
		var remainingVersions = versionMap

		while !subscriber.disposable.disposed && !remainingVersions.isEmpty {
			var nodes: [DependencyIdentifier: DependencyNode] = [:]

			for root in roots {
			}
		}

		subscriber.put(.Completed)
	}
}

/// Attempts to determine the latest valid version to use for each dependency
/// specified in the given Cartfile, and all nested dependencies thereof.
///
/// Sends each recursive dependency with its resolved version, in no particular
/// order.
public func resolveDependencesInCartfile(cartfile: Cartfile) -> ColdSignal<DependencyVersion<SemanticVersion>> {
	return .error(RACError.Empty.error)
}
