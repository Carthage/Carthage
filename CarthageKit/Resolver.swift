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
			return versionsForDependency(dependency)
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

private struct ResolutionState {
	var versionMap: DependencyVersionMap

	var intersectedSpecifiers: [DependencyIdentifier: VersionSpecifier] = [:]
	var chosenVersions: [DependencyIdentifier: SemanticVersion] = [:]

	init(versionMap: DependencyVersionMap) {
		self.versionMap = versionMap
	}
}

/// Attempts to determine the latest valid version to use for each dependency
/// specified in the given Cartfile, and all nested dependencies thereof.
///
/// Sends each recursive dependency with its resolved version, in no particular
/// order.
public func resolveDependencesInCartfile(cartfile: Cartfile) -> ColdSignal<DependencyVersion<SemanticVersion>> {
	return versionMapForCartfile(cartfile)
		.map { versionMap -> ColdSignal<DependencyVersion<SemanticVersion>> in
			var state = ResolutionState(versionMap: versionMap)

			// Enumerate dependencies breadth-first and populate the version
			// specifiers that way.
			for dependency in cartfile.dependencies {
				if let versions = state.versionMap[dependency.identifier] {
					let existingSpecifier = state.intersectedSpecifiers[dependency.identifier] ?? .Any

					if let intersectedSpecifier = intersection(existingSpecifier, dependency.version) {
						state.intersectedSpecifiers[dependency.identifier] = intersectedSpecifier

						if let satisfyingVersion = latestSatisfyingVersion(versions, intersectedSpecifier) {
							state.chosenVersions[dependency.identifier] = satisfyingVersion
						} else {
							// TODO
						}
					} else {
						// TODO
					}
				} else {
					// TODO
				}
			}

			return ColdSignal.fromValues(cartfile.dependencies)
				.map { dependency in
					return dependency.map { _ in state.chosenVersions[dependency.identifier]! }
				}
		}
		.merge(identity)
}
