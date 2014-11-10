//
//  Resolver.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-09.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
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

private func graphsForDependencyVersion(dependency: DependencyVersion<SemanticVersion>, versionMap: DependencyVersionMap) -> ColdSignal<DependencyNode> {
	return dependencyCartfile(dependency)
		.map { cartfile in
			return ColdSignal<DependencyNode> { subscriber in
				for dependency in cartfile.dependencies {
					if let versions = versionMap[dependency.identifier] {
					} else {
						// TODO
					}
				}
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
