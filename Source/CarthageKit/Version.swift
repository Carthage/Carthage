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
/// - Note: See <http://semver.org/>
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
	
	/// The pre-release identifier
	///
	/// Indicates that the version is unstable
	public let preRelease : String?
	
	/// The build metadata
	///
	/// Build metadata is ignored when comparing versions
	public let buildMetadata : String?
	
	/// The pin from which this semantic version was derived.
	public var pinnedVersion: PinnedVersion?

	/// A list of the version components, in order from most significant to
	/// least significant.
	public var components: [Int] {
		return [ major, minor, patch ]
	}
	
	/// Whether this is a prerelease version
	public var isPreRelease : Bool {
		return self.preRelease != nil
	}

	public init(major: Int, minor: Int, patch: Int, preRelease: String? = nil, buildMetadata: String? = nil) {
		self.major = major
		self.minor = minor
		self.patch = patch
		self.preRelease = preRelease
		self.buildMetadata = buildMetadata
	}

	/// The set of all characters present in valid semantic versions.
	private static let versionCharacterSet = NSCharacterSet(charactersInString: "0123456789.")

	/// Attempts to parse a semantic version from a PinnedVersion.
	public static func fromPinnedVersion(pinnedVersion: PinnedVersion) -> Result<SemanticVersion, CarthageError> {
		let scanner = NSScanner(string: pinnedVersion.commitish)

		// Skip leading characters, like "v" or "version-" or anything like
		// that.
		scanner.scanUpToCharactersFromSet(versionCharacterSet, intoString: nil)

		return self.fromScanner(scanner).flatMap { version in
			if scanner.atEnd {
				var version = version
				version.pinnedVersion = pinnedVersion
				return .Success(version)
			} else {
				return .Failure(CarthageError.ParseError(description: "syntax of version \"\(version)\" is unsupported"))
			}
		}
	}
}

extension SemanticVersion: Scannable {
	/// Attempts to parse a semantic version from a human-readable string of the
	/// form "a.b.c".
	static public func fromScanner(scanner: NSScanner) -> Result<SemanticVersion, CarthageError> {
		var versionBuffer: NSString? = nil
		guard scanner.scanCharactersFromSet(versionCharacterSet, intoString: &versionBuffer), let version = versionBuffer as? String else {
			return .Failure(CarthageError.ParseError(description: "expected version in line: \(scanner.currentLine)"))
		}
		
		let components = version.characters.split(allowEmptySlices: false) { $0 == "." }.map(String.init)
		if components.count == 0 {
			return .Failure(CarthageError.ParseError(description: "expected version in line: \(scanner.currentLine)"))
		}

		let major = Int(components[0])
		if major == nil {
			return .Failure(CarthageError.ParseError(description: "expected major version number in \"\(version)\""))
		}

		let minor = (components.count > 1 ? Int(components[1]) : nil)
		if minor == nil {
			return .Failure(CarthageError.ParseError(description: "expected minor version number in \"\(version)\""))
		}

		let hasPatchComponent = components.count > 2
		let patch = (hasPatchComponent ? Int(components[2]) : 0)

		let preRelease = scanner.scanStringWithPrefix("-", until: "+")
		let buildMetadata = scanner.scanStringWithPrefix("+", until: "")

		guard (preRelease == nil && buildMetadata == nil) || hasPatchComponent else {
			return .Failure(CarthageError.ParseError(description: "can not have pre-release or build metadata without patch, in \"\(version)\""))
		}
		
		return .Success(self.init(major: major!,
			minor: minor ?? 0,
			patch: patch ?? 0,
			preRelease: preRelease,
			buildMetadata: buildMetadata))
	}
}

extension NSScanner {
	
	/// Scans a string that is supposed to start with the given prefix, until the given
	/// string is encountered.
	/// - returns: the scanned string without the prefix. If the string does not start with the prefix,
	/// or the scanner is at the end, it returns `nil`.
	private func scanStringWithPrefix(prefix: String, until: String) -> String? {
		if !self.atEnd {
			var buffer : NSString? = nil
			self.scanUpToString(until, intoString: &buffer)
			guard let stringWithPrefix = buffer as? String where stringWithPrefix.hasPrefix(prefix) else {
				return nil
			}
			return stringWithPrefix.substringFromIndex(stringWithPrefix.startIndex.advancedBy(prefix.characters.count))
		} else {
			return nil
		}
	}
}

public func <(lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
	if lhs.components == rhs.components {
		return lhs.isPreReleaseLesser(rhs.preRelease)
	}
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

extension SemanticVersion {
	
	/// Compares the pre-release component with the given pre-release
	/// assuming that the other components (major, minor, patch) are the same
	private func isPreReleaseLesser(preRelease: String?) -> Bool {
		
		// a non-pre-release is not lesser
		guard let selfPreRelease = self.preRelease else {
			return false
		}
		
		// a pre-release version is lesser than a non-pre-release
		guard let otherPreRelease = preRelease else {
			return true
		}
		
		// same pre-release version has no precedence. Build metadata could differ,
		// but there is no ordering defined on build metadata
		guard selfPreRelease != otherPreRelease else {
			return false // undefined ordering
		}
		
		// Compare dot separated components one by one
		// From http://semver.org/:
		// "Precedence for two pre-release versions with the same major, minor, and patch
		// version MUST be determined by comparing each dot separated identifier from left
		// to right until a difference is found [...]. A larger set of pre-release fields
		// has a higher precedence than a smaller set, if all of the preceding
		// identifiers are equal."

		let selfComponents = selfPreRelease.componentsSeparatedByString(".")
		let otherComponents = otherPreRelease.componentsSeparatedByString(".")
		let nonEqualComponents = zip(selfComponents, otherComponents)
			.filter { $0.0 != $0.1 }
		
		for (selfComponent, otherComponent) in nonEqualComponents {
			return selfComponent.lesserThanPreReleaseVersionComponent(otherComponent)
		}
		
		// if I got here, the two pre-release are not the same, but there are not non-equal
		// components, so one must have move pre-components than the other
		return selfComponents.count < otherComponents.count
	}
	
	/// Returns whether a version has the same numeric components (major, minor, patch)
	func hasSameNumericComponents(version: SemanticVersion) -> Bool {
		return self.components == version.components
	}
}

extension String {
	
	/// Returns the Int value of the string, if the string is only composed of digits
	private var numericValue : Int? {
		if !self.isEmpty && self.rangeOfCharacterFromSet(NSCharacterSet.decimalDigitCharacterSet().invertedSet) == nil {
			return Int(self)
		}
		return nil
	}
	
	/// Returns whether the string, considered a pre-release version component, should be
	/// considered lesser than another pre-release version component
	private func lesserThanPreReleaseVersionComponent(other: String) -> Bool {
		// From http://semver.org/:
		// "[the order is defined] as follows: identifiers consisting of only
		// digits are compared numerically and identifiers with letters or hyphens are
		// compared lexically in ASCII sort order. Numeric identifiers always have lower
		// precedence than non-numeric identifiers"
		
		guard let numericSelf = self.numericValue else {
			guard let _ = other.numericValue else {
				// other is not numeric, self is not numeric, compare strings
				return self.compare(other) == .OrderedAscending
			}
			// other is numeric, self is not numeric, other is lower
			return false
		}
		
		guard let numericOther = other.numericValue else {
			// other is not numeric, self is numeric, self is lower
			return true
		}
		
		return numericSelf < numericOther
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
	public static func fromScanner(scanner: NSScanner) -> Result<PinnedVersion, CarthageError> {
		if !scanner.scanString("\"", intoString: nil) {
			return .Failure(CarthageError.ParseError(description: "expected pinned version in line: \(scanner.currentLine)"))
		}

		var commitish: NSString? = nil
		if !scanner.scanUpToString("\"", intoString: &commitish) || commitish == nil {
			return .Failure(CarthageError.ParseError(description: "empty pinned version in line: \(scanner.currentLine)"))
		}

		if !scanner.scanString("\"", intoString: nil) {
			return .Failure(CarthageError.ParseError(description: "unterminated pinned version in line: \(scanner.currentLine)"))
		}

		return .Success(self.init(commitish! as String))
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
				// Consider non-semantic versions (e.g., branches) not to meet
				// any requirement as we can't guarantee any ordering nor
				// compatibility
				return false
			}
		}

		switch self {
		case .Any:
			return withSemanticVersion { !$0.isPreRelease }
		case .GitReference:
			return true
		case let .Exactly(requirement):
			return withSemanticVersion { $0 == requirement }

		case let .AtLeast(requirement):
			return withSemanticVersion { version in
				let versionIsNewer = version >= requirement
				
				// Only pick a pre-release version if the requirement is also
				// a pre-release of the same version
				let notPreReleaseOrSameComponents =	!version.isPreRelease
					|| (requirement.isPreRelease && version.hasSameNumericComponents(requirement))
				return notPreReleaseOrSameComponents && versionIsNewer
			}
		case let .CompatibleWith(requirement):
			return withSemanticVersion { version in
				
				let versionIsNewer = version >= requirement
				let notPreReleaseOrSameComponents =	!version.isPreRelease
					|| (requirement.isPreRelease && version.hasSameNumericComponents(requirement))
				
				// Only pick a pre-release version if the requirement is also 
				// a pre-release of the same version
				guard notPreReleaseOrSameComponents else {
					return false
				}
				
				// According to SemVer, any 0.x.y release may completely break the
				// exported API, so it's not safe to consider them compatible with one
				// another. Only patch versions are compatible under 0.x, meaning 0.1.1 is
				// compatible with 0.1.2, but not 0.2. This isn't according to the SemVer
				// spec but keeps ~> useful for 0.x.y versions.
				if version.major == 0 {
					return version.minor == requirement.minor && versionIsNewer
				}

				return version.major == requirement.major && versionIsNewer
			}
		}
	}
}

public func ==(lhs: VersionSpecifier, rhs: VersionSpecifier) -> Bool {
	switch (lhs, rhs) {
	case (.Any, .Any):
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
				return .Failure(CarthageError.ParseError(description: "expected Git reference name in line: \(scanner.currentLine)"))
			}

			if !scanner.scanString("\"", intoString: nil) {
				return .Failure(CarthageError.ParseError(description: "unterminated Git reference name in line: \(scanner.currentLine)"))
			}

			return .Success(.GitReference(refName! as String))
		} else {
			return .Success(Any)
		}
	}
}

extension VersionSpecifier: CustomStringConvertible {
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

private func intersection(atLeast atLeast: SemanticVersion, compatibleWith: SemanticVersion) -> VersionSpecifier? {
	if atLeast.major > compatibleWith.major {
		return nil
	} else if atLeast.major < compatibleWith.major {
		return .CompatibleWith(compatibleWith)
	} else {
		return .CompatibleWith(max(atLeast, compatibleWith))
	}
}

private func intersection(atLeast atLeast: SemanticVersion, exactly: SemanticVersion) -> VersionSpecifier? {
	if atLeast > exactly {
		return nil
	}

	return .Exactly(exactly)
}

private func intersection(compatibleWith compatibleWith: SemanticVersion, exactly: SemanticVersion) -> VersionSpecifier? {
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
public func intersection(lhs: VersionSpecifier, _ rhs: VersionSpecifier) -> VersionSpecifier? {
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
	return specs.reduce(nil) { (left: VersionSpecifier?, right: VersionSpecifier) -> VersionSpecifier? in
		if let left = left {
			return intersection(left, right)
		} else {
			return right
		}
	}
}
