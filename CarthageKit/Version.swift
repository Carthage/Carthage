//
//  Version.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-08.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa

/// An abstract type representing a way to specify versions.
public protocol VersionType: Scannable, Equatable {}

/// A semantic version.
public struct SemanticVersion: Comparable {
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
}

extension SemanticVersion: Scannable {
	/// Attempts to parse a semantic version from a human-readable string of the
	/// form "a.b.c".
	static public func fromScanner(scanner: NSScanner) -> Result<SemanticVersion> {
		var version: NSString? = nil
		if !scanner.scanCharactersFromSet(NSCharacterSet(charactersInString: "0123456789."), intoString: &version) || version == nil {
			return failure()
		}

		let components = split(version! as String, { $0 == "." }, allowEmptySlices: false)
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

extension SemanticVersion: VersionType {}

public func <(lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
	return lexicographicalCompare(lhs.components, rhs.components)
}

public func ==(lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
	return lhs.components == rhs.components
}

extension SemanticVersion: Printable {
	public var description: String {
		return ".".join(components.map { $0.description })
	}
}

/// An immutable version that a project can be pinned to.
public struct PinnedVersion: Equatable {
	/// The name of the tag to pin to.
	public let tag: String

	public init(tag: String) {
		self.tag = tag
	}
}

public func ==(lhs: PinnedVersion, rhs: PinnedVersion) -> Bool {
	return lhs.tag == rhs.tag
}

extension PinnedVersion: Scannable {
	public static func fromScanner(scanner: NSScanner) -> Result<PinnedVersion> {
		if !scanner.scanString("\"", intoString: nil) {
			return failure()
		}

		var tag: NSString? = nil
		if !scanner.scanUpToString("\"", intoString: &tag) || tag == nil {
			return failure()
		}

		if !scanner.scanString("\"", intoString: nil) {
			return failure()
		}

		return success(self(tag: tag!))
	}
}

extension PinnedVersion: VersionType {}

extension PinnedVersion: Printable {
	public var description: String {
		return tag
	}
}

/// Describes which versions are acceptable for satisfying a dependency
/// requirement.
public enum VersionSpecifier: Equatable {
	case Any
	case AtLeast(SemanticVersion)
	case CompatibleWith(SemanticVersion)
	case Exactly(SemanticVersion)

	/// Determines whether the given version satisfies this version specifier.
	public func satisfiedBy(version: SemanticVersion) -> Bool {
		switch (self) {
		case .Any:
			return true

		case let .Exactly(requirement):
			return version == requirement

		case let .AtLeast(requirement):
			return version >= requirement

		case let .CompatibleWith(requirement):
			return version.major == requirement.major && version >= requirement
		}
	}
}

public func ==(lhs: VersionSpecifier, rhs: VersionSpecifier) -> Bool {
	switch (lhs, rhs) {
	case let (.Any, .Any):
		return true

	case let (.Exactly(left), .Exactly(right)):
		return left == right

	case let (.AtLeast(left), .AtLeast(right)):
		return left == right

	case let (.CompatibleWith(left), .CompatibleWith(right)):
		return left == right

	default:
		return false
	}
}

extension VersionSpecifier: Scannable {
	/// Attempts to parse a VersionSpecifier.
	public static func fromScanner(scanner: NSScanner) -> Result<VersionSpecifier> {
		if scanner.scanString("==", intoString: nil) {
			return SemanticVersion.fromScanner(scanner).map { Exactly($0) }
		} else if scanner.scanString(">=", intoString: nil) {
			return SemanticVersion.fromScanner(scanner).map { AtLeast($0) }
		} else if scanner.scanString("~>", intoString: nil) {
			return SemanticVersion.fromScanner(scanner).map { CompatibleWith($0) }
		} else {
			return success(Any)
		}
	}
}

extension VersionSpecifier: VersionType {}

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

private func intersection(#atLeast: SemanticVersion, #compatibleWith: SemanticVersion) -> VersionSpecifier? {
	if atLeast.major > compatibleWith.major {
		return nil
	} else if atLeast.major < compatibleWith.major {
		return .CompatibleWith(compatibleWith)
	} else {
		return .CompatibleWith(max(atLeast, compatibleWith))
	}
}

private func intersection(#atLeast: SemanticVersion, #exactly: SemanticVersion) -> VersionSpecifier? {
	if atLeast > exactly {
		return nil
	}

	return .Exactly(exactly)
}

private func intersection(#compatibleWith: SemanticVersion, #exactly: SemanticVersion) -> VersionSpecifier? {
	if exactly.major != compatibleWith.major || compatibleWith > exactly {
		return nil
	}

	return .Exactly(exactly)
}

/// Attempts to determine a version specifier that accurately describes the
/// intersection between the two given specifiers.
///
/// In other words, any version that satisfies the returned specifier will
/// satisfy _both_ of the given specifiers.
public func intersection(lhs: VersionSpecifier, rhs: VersionSpecifier) -> VersionSpecifier? {
	switch (lhs, rhs) {
	// Unfortunately, patterns with a wildcard _ are not considered exhaustive,
	// so do the same thing manually.
	case (.Any, .Any): fallthrough
	case (.Any, .AtLeast): fallthrough
	case (.Any, .CompatibleWith): fallthrough
	case (.Any, .Exactly):
		return rhs

	case (.AtLeast, .Any): fallthrough
	case (.CompatibleWith, .Any): fallthrough
	case (.Exactly, .Any):
		return lhs

	case let (.AtLeast(lv), .AtLeast(rv)):
		return .AtLeast(max(lv, rv))

	case let (.AtLeast(lv), .CompatibleWith(rv)):
		return intersection(atLeast: lv, compatibleWith: rv)

	case let (.AtLeast(lv), .Exactly(rv)):
		return intersection(atLeast: lv, exactly: rv)

	case let (.CompatibleWith(lv), .AtLeast(rv)):
		return intersection(atLeast: rv, compatibleWith: lv)

	case let (.CompatibleWith(lv), .CompatibleWith(rv)):
		if lv.major != rv.major {
			return nil
		}

		return .CompatibleWith(max(lv, rv))

	case let (.CompatibleWith(lv), .Exactly(rv)):
		return intersection(compatibleWith: lv, exactly: rv)

	case let (.Exactly(lv), .AtLeast(rv)):
		return intersection(atLeast: rv, exactly: lv)

	case let (.Exactly(lv), .CompatibleWith(rv)):
		return intersection(compatibleWith: rv, exactly: lv)

	case let (.Exactly(lv), .Exactly(rv)):
		if lv != rv {
			return nil
		}

		return lhs
	}
}

/// Attempts to determine a version specifier that accurately describes the
/// intersection between the given specifiers.
///
/// In other words, any version that satisfies the returned specifier will
/// satisfy _all_ of the given specifiers.
public func intersection<S: SequenceType where S.Generator.Element == VersionSpecifier>(specs: S) -> VersionSpecifier? {
	return reduce(specs, nil) { (left: VersionSpecifier?, right: VersionSpecifier) -> VersionSpecifier? in
		if let left = left {
			return intersection(left, right)
		} else {
			return right
		}
	}
}

/// Attempts to determine the highest (latest) version from the given sequence
/// that will satisfy the given version specifier.
public func latestSatisfyingVersion<S: SequenceType where S.Generator.Element == SemanticVersion>(versions: S, specifier: VersionSpecifier) -> SemanticVersion? {
	// TODO: We could improve performance here by not actually sorting the
	// collection (and just testing successively lesser elements from the
	// original input).
	let sortedVersions: [SemanticVersion] = sorted(versions)

	for version in sortedVersions {
		if specifier.satisfiedBy(version) {
			return version
		}
	}

	return nil
}
