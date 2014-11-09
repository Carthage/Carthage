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
	public var dependencies: [DependencyVersion<VersionSpecifier>]

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

			switch (DependencyVersion<VersionSpecifier>.fromScanner(scanner)) {
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
	public var dependencies: [DependencyVersion<PinnedVersion>]

	public static func fromString(string: String) -> Result<CartfileLock> {
		var cartfile = self(dependencies: [])
		var result = success(())

		let scanner = NSScanner(string: string)
		scannerLoop: while !scanner.atEnd {
			switch (DependencyVersion<PinnedVersion>.fromScanner(scanner)) {
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

/// Uniquely identifies a dependency that can be used in projects.
public enum DependencyIdentifier: Equatable {
	/// A repository hosted on GitHub.com.
	case GitHub(Repository)
}

public func ==(lhs: DependencyIdentifier, rhs: DependencyIdentifier) -> Bool {
	switch (lhs, rhs) {
	case let (.GitHub(left), .GitHub(right)):
		return left == right
	}
}

/// Represents a single dependency of a project.
public struct DependencyVersion<V: VersionType>: Equatable {
	/// The unique identifier for this dependency.
	public let identifier: DependencyIdentifier

	/// The version(s) that are required to satisfy this dependency.
	public var version: V

	/// Maps over the `version` in the receiver.
	public func map<W: VersionType>(f: V -> W) -> DependencyVersion<W> {
		return DependencyVersion<W>(repository: repository, version: f(version))
	}
}

public func ==<V>(lhs: DependencyVersion<V>, rhs: DependencyVersion<V>) -> Bool {
	return lhs.identifier == rhs.identifier && lhs.version == rhs.version
}

extension DependencyVersion: Scannable {
	/// Attempts to parse a DependencyVersion specification.
	public static func fromScanner(scanner: NSScanner) -> Result<DependencyVersion> {
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

extension DependencyVersion: Printable {
	public var description: String {
		return "\(repository) @ \(version)"
	}
}

/// Sends each version available to choose from for the given dependency, in no
/// particular order.
internal func versionsForDependency(dependency: DependencyVersion<VersionSpecifier>) -> ColdSignal<SemanticVersion> {
	// TODO: Look up available tags in the repository.
	return .error(RACError.Empty.error)
}

/// Looks up the Cartfile for the given dependency and version combo.
///
/// If the specified version of the dependency does not have a Cartfile, the
/// returned signal will complete without sending any values.
internal func dependencyCartfile(dependency: DependencyVersion<SemanticVersion>) -> ColdSignal<Cartfile> {
	// TODO: Parse the contents of the Cartfile on the tag corresponding to
	// the specific input version.
	return .error(RACError.Empty.error)
}
