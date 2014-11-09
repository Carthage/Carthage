//
//  Cartfile.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa

/// Represents a Cartfile, which is a specification of a project's dependencies
/// and any other settings Carthage needs to build it.
public struct Cartfile {
	/// The dependencies listed in the Cartfile.
	public var dependencies: [Dependency<VersionSpecifier>]

	/// Attempts to parse Cartfile information from a string.
	public static func fromString(string: String) -> Result<Cartfile> {
		var cartfile = self(dependencies: [])
		var result = success(())

		let commentIndicator = "#"
		(string as NSString).enumerateLinesUsingBlock { (line, stop) in
			let scanner = NSScanner(string: line)
			if scanner.scanString(commentIndicator, intoString: nil) {
				// Skip the rest of the line.
				return
			}

			if scanner.atEnd {
				// The line was all whitespace.
				return
			}

			switch (Dependency<VersionSpecifier>.fromScanner(scanner)) {
			case let .Success(dep):
				cartfile.dependencies.append(dep.unbox)

			case let .Failure(error):
				result = failure(error)
				stop.memory = true
			}

			if scanner.scanString(commentIndicator, intoString: nil) {
				// Skip the rest of the line.
				return
			}

			if !scanner.atEnd {
				result = failure()
				stop.memory = true
			}
		}

		return result.map { _ in cartfile }
	}
}

extension Cartfile: Printable {
	public var description: String {
		return "\(dependencies)"
	}
}

/// Represents a parsed Cartfile.lock, which specifies which exact version was
/// checked out for each dependency.
public struct CartfileLock {
	public var dependencies: [Dependency<PinnedVersion>]

	public static func fromString(string: String) -> Result<CartfileLock> {
		var cartfile = self(dependencies: [])
		var result = success(())

		let scanner = NSScanner(string: string)
		scannerLoop: while !scanner.atEnd {
			switch (Dependency<PinnedVersion>.fromScanner(scanner)) {
			case let .Success(dep):
				cartfile.dependencies.append(dep.unbox)

			case let .Failure(error):
				result = failure(error)
				break scannerLoop
			}
		}

		return result.map { _ in cartfile }
	}
}

extension CartfileLock: Printable {
	public var description: String {
		return "\(dependencies)"
	}
}

/// Represents a single dependency of a project.
public struct Dependency<V: VersionType>: Equatable {
	/// The GitHub repository in which this dependency lives.
	public var repository: Repository

	/// The version(s) that are required to satisfy this dependency.
	public var version: V

	/// Maps over the `version` in the receiver.
	public func map<W: VersionType>(f: V -> W) -> Dependency<W> {
		return Dependency<W>(repository: repository, version: f(version))
	}
}

public func ==<V>(lhs: Dependency<V>, rhs: Dependency<V>) -> Bool {
	return lhs.repository == rhs.repository && lhs.version == rhs.version
}

extension Dependency: Scannable {
	/// Attempts to parse a Dependency specification.
	public static func fromScanner(scanner: NSScanner) -> Result<Dependency> {
		if !scanner.scanString("github", intoString: nil) {
			return failure()
		}

		if !scanner.scanString("\"", intoString: nil) {
			return failure()
		}

		var repoNWO: NSString? = nil
		if !scanner.scanUpToString("\"", intoString: &repoNWO) || !scanner.scanString("\"", intoString: nil) {
			return failure()
		}

		if let repoNWO = repoNWO {
			return Repository.fromNWO(repoNWO).flatMap { repo in
				return V.fromScanner(scanner).map { specifier in self(repository: repo, version: specifier) }
			}
		} else {
			return failure()
		}
	}
}

extension Dependency: Printable {
	public var description: String {
		return "\(repository) @ \(version)"
	}
}

/// Sends each version available to choose from for the given dependency, in no
/// particular order.
private func versionsForDependency(dependency: Dependency<VersionSpecifier>) -> ColdSignal<SemanticVersion> {
	// TODO: Look up available tags in the repository.
	return .error(RACError.Empty.error)
}

/// Looks up the Cartfile for the given dependency and version combo.
///
/// If the specified version of the dependency does not have a Cartfile, the
/// returned signal will complete without sending any values.
private func dependencyCartfile(dependency: Dependency<SemanticVersion>) -> ColdSignal<Cartfile> {
	// TODO: Parse the contents of the Cartfile on the tag corresponding to
	// the specific input version.
	return .error(RACError.Empty.error)
}

typealias RepositoryVersionMap = [Repository: [SemanticVersion]]

/// Looks up all dependencies (and nested dependencies) from the given Cartfile,
/// and what versions are available for each.
private func versionMapForCartfile(cartfile: Cartfile) -> ColdSignal<RepositoryVersionMap> {
	return ColdSignal.fromValues(cartfile.dependencies)
		.map { dependency -> ColdSignal<RepositoryVersionMap> in
			return versionsForDependency(dependency)
				.map { version -> ColdSignal<RepositoryVersionMap> in
					let pinnedDependency = dependency.map { _ in version }
					let recursiveVersionMap = dependencyCartfile(pinnedDependency)
						.map { cartfile in versionMapForCartfile(cartfile) }
						.merge(identity)

					return ColdSignal.single([ dependency.repository: [ version ] ])
						.concat(recursiveVersionMap)
				}
				.merge(identity)
		}
		.merge(identity)
		.reduce(initial: [:]) { (var left, right) -> RepositoryVersionMap in
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
	var versionMap: RepositoryVersionMap

	var intersectedSpecifiers: [Repository: VersionSpecifier] = [:]
	var chosenVersions: [Repository: SemanticVersion] = [:]
	
	init(versionMap: RepositoryVersionMap) {
		self.versionMap = versionMap
	}
}

/// Attempts to determine the latest valid version to use for each dependency
/// specified in the given Cartfile, and all nested dependencies thereof.
///
/// Sends each recursive dependency with its resolved version, in no particular
/// order.
public func resolveDependencesInCartfile(cartfile: Cartfile) -> ColdSignal<Dependency<SemanticVersion>> {
	return versionMapForCartfile(cartfile)
		.map { versionMap -> ColdSignal<Dependency<SemanticVersion>> in
			var state = ResolutionState(versionMap: versionMap)

			// Enumerate dependencies breadth-first and populate the version
			// specifiers that way.
			for dependency in cartfile.dependencies {
				if let versions = state.versionMap[dependency.repository] {
					let existingSpecifier = state.intersectedSpecifiers[dependency.repository] ?? .Any

					if let intersectedSpecifier = intersection(existingSpecifier, dependency.version) {
						state.intersectedSpecifiers[dependency.repository] = intersectedSpecifier

						if let satisfyingVersion = latestSatisfyingVersion(versions, intersectedSpecifier) {
							state.chosenVersions[dependency.repository] = satisfyingVersion
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
					return dependency.map { _ in state.chosenVersions[dependency.repository]! }
				}
		}
		.merge(identity)
}
