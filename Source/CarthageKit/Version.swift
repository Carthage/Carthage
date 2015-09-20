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
	private static let versionCharacterSet = NSCharacterSet(charactersInString: "0123456789.")

	/// Attempts to parse a semantic version from a PinnedVersion.
	public static func fromPinnedVersion(pinnedVersion: PinnedVersion) -> Result<SemanticVersion, CarthageError> {
		let scanner = NSScanner(string: pinnedVersion.commitish)

		// Skip leading characters, like "v" or "version-" or anything like
		// that.
		scanner.scanUpToCharactersFromSet(versionCharacterSet, intoString: nil)

		return self.fromScanner(scanner).flatMap { (var version) in
			if scanner.atEnd {
				version.pinnedVersion = pinnedVersion
				return .success(version)
			} else {
				// Disallow versions like "1.0a5", because we only support
				// SemVer right now.
				return .failure(CarthageError.ParseError(description: "syntax of version \"\(version)\" is unsupported"))
			}
		}
	}
}

extension SemanticVersion: Scannable {
	/// Attempts to parse a semantic version from a human-readable string of the
	/// form "a.b.c".
	static public func fromScanner(scanner: NSScanner) -> Result<SemanticVersion, CarthageError> {
		var version: NSString? = nil
		if !scanner.scanCharactersFromSet(versionCharacterSet, intoString: &version) || version == nil {
			return .failure(CarthageError.ParseError(description: "expected version in line: \(scanner.currentLine)"))
		}

		let components = split(version! as String, allowEmptySlices: false) { $0 == "." }
		if components.count == 0 {
			return .failure(CarthageError.ParseError(description: "expected version in line: \(scanner.currentLine)"))
		}

		let major = components[0].toInt()
		if major == nil {
			return .failure(CarthageError.ParseError(description: "expected major version number in \"\(version!)\""))
		}

		let minor = (components.count > 1 ? components[1].toInt() : nil)
		if minor == nil {
			return .failure(CarthageError.ParseError(description: "expected minor version number in \"\(version!)\""))
		}

		let patch = (components.count > 2 ? components[2].toInt() : 0)

		return .success(self(major: major!, minor: minor ?? 0, patch: patch ?? 0))
	}
}

extension SemanticVersion: VersionType {}

public func <(lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
	return lexicographicalCompare(lhs.components, rhs.components)
}

public func ==(lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
	return lhs.components == rhs.components
}

extension SemanticVersion: Hashable {
	public var hashValue: Int {
		return reduce(components, 0) { $0 ^ $1.hashValue }
	}
}

extension SemanticVersion: Printable {
	public var description: String {
		return ".".join(components.map { $0.description })
	}
}

/// An immutable version that a project can be pinned to.
public struct PinnedVersion: Equatable {
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
	public static func fromScanner(scanner: NSScanner) -> Result<PinnedVersion, CarthageError> {
		if !scanner.scanString("\"", intoString: nil) {
			return .failure(CarthageError.ParseError(description: "expected pinned version in line: \(scanner.currentLine)"))
		}

		var commitish: NSString? = nil
		if !scanner.scanUpToString("\"", intoString: &commitish) || commitish == nil {
			return .failure(CarthageError.ParseError(description: "empty pinned version in line: \(scanner.currentLine)"))
		}

		if !scanner.scanString("\"", intoString: nil) {
			return .failure(CarthageError.ParseError(description: "unterminated pinned version in line: \(scanner.currentLine)"))
		}

		return .success(self(commitish! as String))
	}
}

extension PinnedVersion: VersionType {}

extension PinnedVersion: Printable {
	public var description: String {
		return "\"\(commitish)\""
	}
}

/// Describes which versions are acceptable for satisfying a dependency
/// requirement.
public enum VersionSpecifier: Equatable {
	case Any
	case AtLeast(SemanticVersion)
	case CompatibleWith(SemanticVersion)
	case Exactly(SemanticVersion)
	case GitReference(String)

	/// Determines whether the given version satisfies this version specifier.
	public func satisfiedBy(version: PinnedVersion) -> Bool {
		func withSemanticVersion(predicate: SemanticVersion -> Bool) -> Bool {
			if let semanticVersion = SemanticVersion.fromPinnedVersion(version).value {
				return predicate(semanticVersion)
			} else {
				// Consider non-semantic versions (e.g., branches) to meet every
				// version range requirement.
				return true
			}
		}

		switch self {
		case .Any, .GitReference:
			return true

		case let .Exactly(requirement):
			return withSemanticVersion { $0 == requirement }

		case let .AtLeast(requirement):
			return withSemanticVersion { $0 >= requirement }

		case let .CompatibleWith(requirement):
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
	case let (.Any, .Any):
		return true

	case let (.Exactly(left), .Exactly(right)):
		return left == right

	case let (.AtLeast(left), .AtLeast(right)):
		return left == right

	case let (.CompatibleWith(left), .CompatibleWith(right)):
		return left == right

	case let (.GitReference(left), .GitReference(right)):
		return left == right

	default:
		return false
	}
}

extension VersionSpecifier: Scannable {
	/// Attempts to parse a VersionSpecifier.
	public static func fromScanner(scanner: NSScanner) -> Result<VersionSpecifier, CarthageError> {
		if scanner.scanString("==", intoString: nil) {
			return SemanticVersion.fromScanner(scanner).map { Exactly($0) }
		} else if scanner.scanString(">=", intoString: nil) {
			return SemanticVersion.fromScanner(scanner).map { AtLeast($0) }
		} else if scanner.scanString("~>", intoString: nil) {
			return SemanticVersion.fromScanner(scanner).map { CompatibleWith($0) }
		} else if scanner.scanString("\"", intoString: nil) {
			var refName: NSString? = nil
			if !scanner.scanUpToString("\"", intoString: &refName) || refName == nil {
				return .failure(CarthageError.ParseError(description: "expected Git reference name in line: \(scanner.currentLine)"))
			}

			if !scanner.scanString("\"", intoString: nil) {
				return .failure(CarthageError.ParseError(description: "unterminated Git reference name in line: \(scanner.currentLine)"))
			}

			return .success(.GitReference(refName! as String))
		} else {
			return .success(Any)
		}
	}
}

extension VersionSpecifier: VersionType {}

extension VersionSpecifier: Printable {
	public var description: String {
		switch self {
		case .Any:
			return ""

		case let .Exactly(version):
			return "== \(version)"

		case let .AtLeast(version):
			return ">= \(version)"

		case let .CompatibleWith(version):
			return "~> \(version)"

		case let .GitReference(refName):
			return "\"\(refName)\""
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
	case (.Any, .Any), (.Any, .AtLeast), (.Any, .CompatibleWith), (.Any, .Exactly):
		return rhs

	case (.AtLeast, .Any), (.CompatibleWith, .Any), (.Exactly, .Any):
		return lhs

	case (.GitReference, .Any), (.GitReference, .AtLeast), (.GitReference, .CompatibleWith), (.GitReference, .Exactly):
		return lhs

	case (.Any, .GitReference), (.AtLeast, .GitReference), (.CompatibleWith, .GitReference), (.Exactly, .GitReference):
		return rhs

	case let (.GitReference(lv), .GitReference(rv)):
		if lv != rv {
			return nil
		}

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
