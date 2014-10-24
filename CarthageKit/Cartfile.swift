//
//  Cartfile.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit

/// Represents a Cartfile, which is a specification of a project's dependencies
/// and any other settings Carthage needs to build it.
public struct Cartfile {
	/// The dependencies listed in the Cartfile.
	public var dependencies: [Dependency]
}

extension Cartfile: JSONDecodable {
	public static func fromJSON(JSON: AnyObject) -> Result<Cartfile> {
		if let array = JSON as? [AnyObject] {
			var deps: [Dependency] = []

			for elem in array {
				switch (Dependency.fromJSON(elem)) {
				case let .Success(value):
					deps.append(value.unbox)

				case let .Failure(error):
					return failure(error)
				}
			}

			return success(Cartfile(dependencies: deps))
		} else {
			return failure()
		}
	}
}

extension Cartfile: Printable {
	public var description: String {
		return "\(dependencies)"
	}
}

/// Represents a single dependency of a project.
public struct Dependency: Equatable {
	/// The GitHub repository in which this dependency lives.
	public var repository: Repository

	/// The version(s) that are required to satisfy this dependency.
	public var version: VersionSpecifier
}

public func ==(lhs: Dependency, rhs: Dependency) -> Bool {
	return lhs.repository == rhs.repository && lhs.version == rhs.version
}

extension Dependency: JSONDecodable {
	public static func fromJSON(JSON: AnyObject) -> Result<Dependency> {
		if let object = JSON as? [String: AnyObject] {
			let versionString = object["version"] as? String ?? ""
			let version = VersionSpecifier.fromJSON(versionString) ?? .Any

			if let repo = object["repo"] as? String {
				return Repository
					.fromJSON(repo)
					.map { Dependency(repository: $0, version: version) }
			} else {
				return failure()
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

/// A semantic version.
public struct Version: Comparable {
	/// The major version.
	///
	/// Increments to this component represent incompatible API changes.
	public let major: Int

	/// The minor version.
	///
	/// Increments to this component represent backwards-compatible
	/// enhancements.
	public let minor: Int

	/// The patch version.
	///
	/// Increments to this component represent backwards-compatible bug fixes.
	public let patch: Int

	/// A list of the version components, in order from most significant to
	/// least significant.
	public var components: [Int] {
		return [ major, minor, patch ]
	}

	public init(major: Int, minor: Int, patch: Int) {
		self.major = major
		self.minor = minor
		self.patch = patch
	}

	/// Attempts to parse a semantic version from a human-readable string of the
	/// form "a.b.c".
	static public func fromString(specifier: String) -> Result<Version> {
		let components = split(specifier, { $0 == "." }, allowEmptySlices: false)
		if components.count == 0 {
			return failure()
		}

		let major = components[0].toInt()
		if major == nil {
			return failure()
		}

		let minor = (components.count > 1 ? components[1].toInt() : 0)
		let patch = (components.count > 2 ? components[2].toInt() : 0)

		return success(self(major: major!, minor: minor ?? 0, patch: patch ?? 0))
	}
}

public func <(lhs: Version, rhs: Version) -> Bool {
    return lexicographicalCompare(lhs.components, rhs.components)
}

public func ==(lhs: Version, rhs: Version) -> Bool {
	return lhs.components == rhs.components
}

extension Version: Printable {
	public var description: String {
		return ".".join(components.map { $0.description })
	}
}

/// Describes which versions are acceptable for satisfying a dependency
/// requirement.
public enum VersionSpecifier: Equatable {
	case Any
	case Exactly(Version)
	case AtLeast(Version)
	case CompatibleWith(Version)
}

public func ==(lhs: VersionSpecifier, rhs: VersionSpecifier) -> Bool {
	switch (lhs, rhs) {
	case let (.Any, .Any):
		return true

	case let (.Exactly(left), .Exactly(right)):
		return left == right

	case let (.AtLeast(left), .AtLeast(right)):
		return left == right

	case let (.AtLeast(left), .AtLeast(right)):
		return left == right

	default:
		return false
	}
}

extension VersionSpecifier: JSONDecodable {
	public static func fromJSON(JSON: AnyObject) -> Result<VersionSpecifier> {
		if let specifier = JSON as? String {
			return Version.fromString(specifier).map { .Exactly($0) }
		} else {
			return failure()
		}
	}
}

extension VersionSpecifier: Printable {
	public var description: String {
		switch (self) {
		case let .Any:
			return "(any)"

		case let .Exactly(version):
			return "== \(version)"

		case let .AtLeast(version):
			return ">= \(version)"

		case let .CompatibleWith(version):
			return "~> \(version)"
		}
	}
}
