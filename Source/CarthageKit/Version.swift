//
//  Version.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-08.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import Result
import ReactiveCocoa

/// An abstract type representing a way to specify versions.
public protocol VersionType: Equatable {}

/// A semantic version.
public struct SemanticVersion: VersionType, Comparable {
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

	/// The pin from which this semantic version was derived.
	public var pinnedVersion: PinnedVersion?

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

	/// The set of all characters present in valid semantic versions.
	private static let versionCharacterSet = CharacterSet(charactersIn: "0123456789.")

	/// Attempts to parse a semantic version from a PinnedVersion.
	public static func fromPinnedVersion(pinnedVersion: PinnedVersion) -> Result<SemanticVersion, CarthageError> {
		let scanner = Scanner(string: pinnedVersion.commitish)

		// Skip leading characters, like "v" or "version-" or anything like
		// that.
		scanner.scanUpToCharacters(from: versionCharacterSet, into: nil)

		return self.fromScanner(scanner).flatMap { version in
			if scanner.isAtEnd {
				var version = version
				version.pinnedVersion = pinnedVersion
				return .success(version)
			} else {
				// Disallow versions like "1.0a5", because we only support
				// SemVer right now.
				return .failure(CarthageError.parseError(description: "syntax of version \"\(version)\" is unsupported"))
			}
		}
	}
}

extension SemanticVersion: Scannable {
	/// Attempts to parse a semantic version from a human-readable string of the
	/// form "a.b.c".
	static public func fromScanner(scanner: Scanner) -> Result<SemanticVersion, CarthageError> {
		var version: NSString? = nil
		if !scanner.scanCharacters(from: versionCharacterSet, into: &version) || version == nil {
			return .failure(CarthageError.parseError(description: "expected version in line: \(scanner.currentLine)"))
		}

		let components = (version! as String).characters.split(allowEmptySlices: false) { $0 == "." }.map(String.init)
		if components.count == 0 {
			return .failure(CarthageError.parseError(description: "expected version in line: \(scanner.currentLine)"))
		}

		let major = Int(components[0])
		if major == nil {
			return .failure(CarthageError.parseError(description: "expected major version number in \"\(version!)\""))
		}

		let minor = (components.count > 1 ? Int(components[1]) : nil)
		if minor == nil {
			return .failure(CarthageError.parseError(description: "expected minor version number in \"\(version!)\""))
		}

		let patch = (components.count > 2 ? Int(components[2]) : 0)

		return .success(self.init(major: major!, minor: minor ?? 0, patch: patch ?? 0))
	}
}

public func <(lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
	return lhs.components.lexicographicalCompare(rhs.components)
}

public func ==(lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
	return lhs.components == rhs.components
}

extension SemanticVersion: Hashable {
	public var hashValue: Int {
		return components.reduce(0) { $0 ^ $1.hashValue }
	}
}

extension SemanticVersion: CustomStringConvertible {
	public var description: String {
		return components.map { $0.description }.joinWithSeparator(".")
	}
}

/// An immutable version that a project can be pinned to.
public struct PinnedVersion: VersionType {
	/// The commit SHA, or name of the tag, to pin to.
	public let commitish: String

	public init(_ commitish: String) {
		self.commitish = commitish
	}
}

public func ==(lhs: PinnedVersion, rhs: PinnedVersion) -> Bool {
	return lhs.commitish == rhs.commitish
}

extension PinnedVersion: Scannable {
	public static func fromScanner(scanner: Scanner) -> Result<PinnedVersion, CarthageError> {
		if !scanner.scanString("\"", into: nil) {
			return .failure(CarthageError.parseError(description: "expected pinned version in line: \(scanner.currentLine)"))
		}

		var commitish: NSString? = nil
		if !scanner.scanUpTo("\"", into: &commitish) || commitish == nil {
			return .failure(CarthageError.parseError(description: "empty pinned version in line: \(scanner.currentLine)"))
		}

		if !scanner.scanString("\"", into: nil) {
			return .failure(CarthageError.parseError(description: "unterminated pinned version in line: \(scanner.currentLine)"))
		}

		return .success(self.init(commitish! as String))
	}
}

extension PinnedVersion: CustomStringConvertible {
	public var description: String {
		return "\"\(commitish)\""
	}
}

/// Describes which versions are acceptable for satisfying a dependency
/// requirement.
public enum VersionSpecifier: VersionType {
	case any
	case atLeast(SemanticVersion)
	case compatibleWith(SemanticVersion)
	case exactly(SemanticVersion)
	case gitReference(String)

	/// Determines whether the given version satisfies this version specifier.
	public func satisfiedBy(version: PinnedVersion) -> Bool {
		func withSemanticVersion(predicate: (SemanticVersion) -> Bool) -> Bool {
			if let semanticVersion = SemanticVersion.fromPinnedVersion(version).value {
				return predicate(semanticVersion)
			} else {
				// Consider non-semantic versions (e.g., branches) to meet every
				// version range requirement.
				return true
			}
		}

		switch self {
		case .any, .gitReference:
			return true

		case let .exactly(requirement):
			return withSemanticVersion { $0 == requirement }

		case let .atLeast(requirement):
			return withSemanticVersion { $0 >= requirement }

		case let .compatibleWith(requirement):
			return withSemanticVersion { version in
				// According to SemVer, any 0.x.y release may completely break the
				// exported API, so it's not safe to consider them compatible with one
				// another. Only patch versions are compatible under 0.x, meaning 0.1.1 is
				// compatible with 0.1.2, but not 0.2. This isn't according to the SemVer
				// spec but keeps ~> useful for 0.x.y versions.
				if version.major == 0 {
					return version.minor == requirement.minor && version >= requirement
				}

				return version.major == requirement.major && version >= requirement
			}
		}
	}
}

public func ==(lhs: VersionSpecifier, rhs: VersionSpecifier) -> Bool {
	switch (lhs, rhs) {
	case (.any, .any):
		return true

	case let (.exactly(left), .exactly(right)):
		return left == right

	case let (.atLeast(left), .atLeast(right)):
		return left == right

	case let (.compatibleWith(left), .compatibleWith(right)):
		return left == right

	case let (.gitReference(left), .gitReference(right)):
		return left == right

	default:
		return false
	}
}

extension VersionSpecifier: Scannable {
	/// Attempts to parse a VersionSpecifier.
	public static func fromScanner(scanner: Scanner) -> Result<VersionSpecifier, CarthageError> {
		if scanner.scanString("==", into: nil) {
			return SemanticVersion.fromScanner(scanner).map { .exactly($0) }
		} else if scanner.scanString(">=", into: nil) {
			return SemanticVersion.fromScanner(scanner).map { .atLeast($0) }
		} else if scanner.scanString("~>", into: nil) {
			return SemanticVersion.fromScanner(scanner).map { .compatibleWith($0) }
		} else if scanner.scanString("\"", into: nil) {
			var refName: NSString? = nil
			if !scanner.scanUpTo("\"", into: &refName) || refName == nil {
				return .failure(CarthageError.parseError(description: "expected Git reference name in line: \(scanner.currentLine)"))
			}

			if !scanner.scanString("\"", into: nil) {
				return .failure(CarthageError.parseError(description: "unterminated Git reference name in line: \(scanner.currentLine)"))
			}

			return .success(.gitReference(refName! as String))
		} else {
			return .success(.any)
		}
	}
}

extension VersionSpecifier: CustomStringConvertible {
	public var description: String {
		switch self {
		case .any:
			return ""

		case let .exactly(version):
			return "== \(version)"

		case let .atLeast(version):
			return ">= \(version)"

		case let .compatibleWith(version):
			return "~> \(version)"

		case let .gitReference(refName):
			return "\"\(refName)\""
		}
	}
}

private func intersection(atLeast atLeast: SemanticVersion, compatibleWith: SemanticVersion) -> VersionSpecifier? {
	if atLeast.major > compatibleWith.major {
		return nil
	} else if atLeast.major < compatibleWith.major {
		return .compatibleWith(compatibleWith)
	} else {
		return .compatibleWith(max(atLeast, compatibleWith))
	}
}

private func intersection(atLeast atLeast: SemanticVersion, exactly: SemanticVersion) -> VersionSpecifier? {
	if atLeast > exactly {
		return nil
	}

	return .exactly(exactly)
}

private func intersection(compatibleWith compatibleWith: SemanticVersion, exactly: SemanticVersion) -> VersionSpecifier? {
	if exactly.major != compatibleWith.major || compatibleWith > exactly {
		return nil
	}

	return .exactly(exactly)
}

/// Attempts to determine a version specifier that accurately describes the
/// intersection between the two given specifiers.
///
/// In other words, any version that satisfies the returned specifier will
/// satisfy _both_ of the given specifiers.
public func intersection(lhs: VersionSpecifier, _ rhs: VersionSpecifier) -> VersionSpecifier? {
	switch (lhs, rhs) {
	// Unfortunately, patterns with a wildcard _ are not considered exhaustive,
	// so do the same thing manually.
	case (.any, .any), (.any, .atLeast), (.any, .compatibleWith), (.any, .exactly):
		return rhs

	case (.atLeast, .any), (.compatibleWith, .any), (.exactly, .any):
		return lhs

	case (.gitReference, .any), (.gitReference, .atLeast), (.gitReference, .compatibleWith), (.gitReference, .exactly):
		return lhs

	case (.any, .gitReference), (.atLeast, .gitReference), (.compatibleWith, .gitReference), (.exactly, .gitReference):
		return rhs

	case let (.gitReference(lv), .gitReference(rv)):
		if lv != rv {
			return nil
		}

		return lhs

	case let (.atLeast(lv), .atLeast(rv)):
		return .atLeast(max(lv, rv))

	case let (.atLeast(lv), .compatibleWith(rv)):
		return intersection(atLeast: lv, compatibleWith: rv)

	case let (.atLeast(lv), .exactly(rv)):
		return intersection(atLeast: lv, exactly: rv)

	case let (.compatibleWith(lv), .atLeast(rv)):
		return intersection(atLeast: rv, compatibleWith: lv)

	case let (.compatibleWith(lv), .compatibleWith(rv)):
		if lv.major != rv.major {
			return nil
		}

		// According to SemVer, any 0.x.y release may completely break the
		// exported API, so it's not safe to consider them compatible with one
		// another. Only patch versions are compatible under 0.x, meaning 0.1.1 is
		// compatible with 0.1.2, but not 0.2. This isn't according to the SemVer
		// spec but keeps ~> useful for 0.x.y versions.
		if lv.major == 0 && rv.major == 0 {
			if lv.minor != rv.minor {
				return nil
			}
		}

		return .compatibleWith(max(lv, rv))

	case let (.compatibleWith(lv), .exactly(rv)):
		return intersection(compatibleWith: lv, exactly: rv)

	case let (.exactly(lv), .atLeast(rv)):
		return intersection(atLeast: rv, exactly: lv)

	case let (.exactly(lv), .compatibleWith(rv)):
		return intersection(compatibleWith: rv, exactly: lv)

	case let (.exactly(lv), .exactly(rv)):
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
	return specs.reduce(nil) { (left: VersionSpecifier?, right: VersionSpecifier) -> VersionSpecifier? in
		if let left = left {
			return intersection(left, right)
		} else {
			return right
		}
	}
}
