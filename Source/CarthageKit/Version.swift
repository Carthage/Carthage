// swiftlint:disable file_length

import Foundation
import Result
import ReactiveSwift
import Utility

extension Version {
	/// Attempts to parse a semantic version from a PinnedVersion.
	public static func from(_ pinnedVersion: PinnedVersion) -> Result<Version, ScannableError> {
		let scanner = Scanner(string: pinnedVersion.commitish)

		// Skip leading characters, like "v" or "version-" or anything like
		// that.
		scanner.scanUpToCharacters(from: versionCharacterSet, into: nil)

		return self.from(scanner).flatMap { version in
			if scanner.isAtEnd {
				return .success(version)
			} else {
				return .failure(ScannableError(message: "syntax of version \"\(version)\" is unsupported", currentLine: scanner.currentLine))
			}
		}
	}

	/// Set of valid digts for SemVer versions
	/// - note: Please use this instead of `CharacterSet.decimalDigits`, as
	/// `decimalDigits` include more characters that are not contemplated in
	/// the SemVer spects (e.g. `FULLWIDTH` version of digits, like `４`)
	fileprivate static let semVerDecimalDigits = CharacterSet(charactersIn: "0123456789")

	/// Set of valid characters for SemVer major.minor.patch section
	fileprivate static let versionCharacterSet = CharacterSet(charactersIn: ".")
		.union(Version.semVerDecimalDigits)

	fileprivate static let asciiAlphabeth = CharacterSet(
		charactersIn: "abcdefghijklmnopqrstuvxyzABCDEFGHIJKLMNOPQRSTUVXYZ"
	)

	/// Set of valid character for SemVer build metadata section
	fileprivate static let invalidBuildMetadataCharacters = asciiAlphabeth
		.union(Version.semVerDecimalDigits)
		.union(CharacterSet(charactersIn: "-"))
		.inverted

	/// Separator of pre-release components
	fileprivate static let preReleaseComponentsSeparator = "."
}

extension Version: Scannable {
	/// Attempts to parse a semantic version from a human-readable string of the
	/// form "a.b.c" from a string scanner.
	public static func from(_ scanner: Scanner) -> Result<Version, ScannableError> {
		var versionBuffer: NSString?
		guard scanner.scanCharacters(from: versionCharacterSet, into: &versionBuffer),
			let version = versionBuffer as String? else {
			return .failure(ScannableError(message: "expected version", currentLine: scanner.currentLine))
		}

		let components = version
			.split(omittingEmptySubsequences: false) { $0 == "." }
		guard !components.isEmpty else {
			return .failure(ScannableError(message: "expected version", currentLine: scanner.currentLine))
		}
		guard components.count <= 3 else {
			return .failure(ScannableError(message: "found more than 3 dot-separated components in version", currentLine: scanner.currentLine))
		}

		func parseVersion(at index: Int) -> Int? {
			return components.count > index ? Int(components[index]) : nil
		}

		guard let major = parseVersion(at: 0) else {
			return .failure(ScannableError(message: "expected major version number", currentLine: scanner.currentLine))
		}

		guard let minor = parseVersion(at: 1) else {
			return .failure(ScannableError(message: "expected minor version number", currentLine: scanner.currentLine))
		}

		let hasPatchComponent = components.count > 2
		let patch = parseVersion(at: 2)
		guard !hasPatchComponent || patch != nil else {
			return .failure(ScannableError(message: "invalid patch version", currentLine: scanner.currentLine))
		}

		let preRelease = scanner.scanStringWithPrefix("-", until: "+")
		let buildMetadata = scanner.scanStringWithPrefix("+", until: "")
		guard scanner.isAtEnd else {
			return .failure(ScannableError(message: "expected valid version", currentLine: scanner.currentLine))
		}

		if
			let buildMetadata = buildMetadata,
			let error = Version.validateBuildMetadata(buildMetadata, fullVersion: version)
		{
			return .failure(error)
		}

		if
			let preRelease = preRelease,
			let error = Version.validatePreRelease(preRelease, fullVersion: version)
		{
			return .failure(error)
		}

		guard (preRelease == nil && buildMetadata == nil) || hasPatchComponent else {
			return .failure(ScannableError(message: "can not have pre-release or build metadata without patch, in \"\(version)\""))
		}

		return .success(self.init(
			major,
			minor,
			patch ?? 0,
			prereleaseIdentifiers: preRelease?.split(separator: ".").map(String.init) ?? [],
			buildMetadataIdentifiers: buildMetadata?.split(separator: ".").map(String.init) ?? []
		))
	}

	/// Checks validity of a build metadata string and returns an error if not valid
	static private func validateBuildMetadata(_ buildMetadata: String, fullVersion: String) -> ScannableError? {
		guard !buildMetadata.isEmpty else {
			return ScannableError(message: "Build metadata is empty after '+', in \"\(fullVersion)\"")
		}
		guard !buildMetadata.containsAny(invalidBuildMetadataCharacters) else {
			return ScannableError(message: "Build metadata contains invalid characters, in \"\(fullVersion)\"")
		}
		return nil
	}

	/// Checks validity of a pre-release string and returns an error if not valid
	static private func validatePreRelease(_ preRelease: String, fullVersion: String) -> ScannableError? {
		guard !preRelease.isEmpty else {
			return ScannableError(message: "Pre-release is empty after '-', in \"\(fullVersion)\"")
		}

		let components = preRelease.components(separatedBy: preReleaseComponentsSeparator)
		guard components.first(where: { $0.containsAny(invalidBuildMetadataCharacters) }) == nil else {
			return ScannableError(message: "Pre-release contains invalid characters, in \"\(fullVersion)\"")
		}

		guard components.first(where: { $0.isEmpty }) == nil else {
			return ScannableError(message: "Pre-release component is empty, in \"\(fullVersion)\"")
		}

		// swiftlint:disable:next first_where
		guard components
			.filter({ !$0.containsAny(Version.semVerDecimalDigits.inverted) && $0 != "0" })
			// MUST NOT include leading zeros
			.first(where: { $0.hasPrefix("0") }) == nil else {
				return ScannableError(message: "Pre-release contains leading zero component, in \"\(fullVersion)\"")
		}
		return nil
	}
}

extension Scanner {

	/// Scans a string that is supposed to start with the given prefix, until the given
	/// string is encountered.
	/// - returns: the scanned string without the prefix. If the string does not start with the prefix,
	/// or the scanner is at the end, it returns `nil` without advancing the scanner.
	fileprivate func scanStringWithPrefix(_ prefix: Character, until: String) -> String? {
		guard !self.isAtEnd, self.remainingSubstring?.first == prefix else { return nil }

		var buffer: NSString?
		self.scanUpTo(until, into: &buffer)
		guard let stringWithPrefix = buffer as String?, stringWithPrefix.first == prefix else {
			return nil
		}

		return String(stringWithPrefix.dropFirst())
	}

	/// The string (as `Substring?`) that is left to scan.
	///
	/// Accessing this variable will not advance the scanner location.
	///
	/// - returns: `nil` in the unlikely event `self.scanLocation` splits an extended grapheme cluster.
	var remainingSubstring: Substring? {
		return Range(
			NSRange(
				location: self.scanLocation /* our UTF-16 offset */,
				length: (self.string as NSString).length - self.scanLocation
			),
			in: self.string
		).map {
			self.string[$0]
		}
	}
}

extension String {

	/// Returns the Int value of the string, if the string is only composed of digits
	private var numericValue: Int? {
		if !self.isEmpty && self.rangeOfCharacter(from: Version.semVerDecimalDigits.inverted) == nil {
			return Int(self)
		}
		return nil
	}

	/// Returns whether the string, considered a pre-release version component, should be
	/// considered lesser than another pre-release version component
	fileprivate func lesserThanPreReleaseVersionComponent(other: String) -> Bool {
		// From http://semver.org/:
		// "[the order is defined] as follows: identifiers consisting of only
		// digits are compared numerically and identifiers with letters or hyphens are
		// compared lexically in ASCII sort order. Numeric identifiers always have lower
		// precedence than non-numeric identifiers"

		guard let numericSelf = self.numericValue else {
			guard other.numericValue != nil else {
				// other is not numeric, self is not numeric, compare strings
				return self.compare(other) == .orderedAscending
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
public struct PinnedVersion: Hashable {
	/// The commit SHA, or name of the tag, to pin to.
	public let commitish: String

	public init(_ commitish: String) {
		self.commitish = commitish
	}
}

extension PinnedVersion: Scannable {
	public static func from(_ scanner: Scanner) -> Result<PinnedVersion, ScannableError> {
		if !scanner.scanString("\"", into: nil) {
			return .failure(ScannableError(message: "expected pinned version", currentLine: scanner.currentLine))
		}

		var commitish: NSString?
		if !scanner.scanUpTo("\"", into: &commitish) || commitish == nil {
			return .failure(ScannableError(message: "empty pinned version", currentLine: scanner.currentLine))
		}

		if !scanner.scanString("\"", into: nil) {
			return .failure(ScannableError(message: "unterminated pinned version", currentLine: scanner.currentLine))
		}

		return .success(self.init(commitish! as String))
	}
}

extension PinnedVersion: CustomStringConvertible {
	public var description: String {
		return "\"\(commitish)\""
	}
}

extension Version {
	fileprivate var isPreRelease: Bool {
		return !prereleaseIdentifiers.isEmpty
	}

	fileprivate var discardingBuildMetadata: Version {
		return Version(major, minor, patch, prereleaseIdentifiers: prereleaseIdentifiers)
	}

	fileprivate func hasSameNumericComponents(version: Version) -> Bool {
		return major == version.major
			&& minor == version.minor
			&& patch == version.patch
	}
}

/// Describes which versions are acceptable for satisfying a dependency
/// requirement.
public enum VersionSpecifier: Hashable {
	case any
	case atLeast(Version)
	case compatibleWith(Version)
	case exactly(Version)
	case gitReference(String)

	/// Determines whether the given version satisfies this version specifier.
	public func isSatisfied(by version: PinnedVersion) -> Bool {
		func withVersion(_ predicate: (Version) -> Bool) -> Bool {
			if let semanticVersion = Version.from(version).value {
				return predicate(semanticVersion)
			} else {
				// Consider non-semantic versions (e.g., branches) to meet every
				// version range requirement
				return true
			}
		}

		switch self {
		case .any:
			return withVersion { !$0.isPreRelease }
		case .gitReference:
			return true
		case let .exactly(requirement):
			return withVersion { $0 == requirement }

		case let .atLeast(requirement):
			return withVersion { version in
				let versionIsNewer = version >= requirement

				// Only pick a pre-release version if the requirement is also
				// a pre-release of the same version
				let notPreReleaseOrSameComponents =	!version.isPreRelease
					|| (requirement.isPreRelease && version.hasSameNumericComponents(version: requirement))
				return notPreReleaseOrSameComponents && versionIsNewer
			}
		case let .compatibleWith(requirement):
			return withVersion { version in

				let versionIsNewer = version >= requirement
				let notPreReleaseOrSameComponents =	!version.isPreRelease
					|| (requirement.isPreRelease && version.hasSameNumericComponents(version: requirement))

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

extension VersionSpecifier: Scannable {
	/// Attempts to parse a VersionSpecifier.
	public static func from(_ scanner: Scanner) -> Result<VersionSpecifier, ScannableError> {
		if scanner.scanString("==", into: nil) {
			return Version.from(scanner).map { .exactly($0) }
		} else if scanner.scanString(">=", into: nil) {
			return Version.from(scanner).map { .atLeast($0) }
		} else if scanner.scanString("~>", into: nil) {
			return Version.from(scanner).map { .compatibleWith($0) }
		} else if scanner.scanString("\"", into: nil) {
			var refName: NSString?
			if !scanner.scanUpTo("\"", into: &refName) || refName == nil {
				return .failure(ScannableError(message: "expected Git reference name", currentLine: scanner.currentLine))
			}

			if !scanner.scanString("\"", into: nil) {
				return .failure(ScannableError(message: "unterminated Git reference name", currentLine: scanner.currentLine))
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

private func intersection(atLeast: Version, compatibleWith: Version) -> VersionSpecifier? {
	if atLeast.major > compatibleWith.major {
		return nil
	} else if atLeast.major < compatibleWith.major {
		return .compatibleWith(compatibleWith)
	} else {
		return .compatibleWith(max(atLeast, compatibleWith))
	}
}

private func intersection(atLeast: Version, exactly: Version) -> VersionSpecifier? {
	if atLeast > exactly {
		return nil
	}

	return .exactly(exactly)
}

private func intersection(compatibleWith: Version, exactly: Version) -> VersionSpecifier? {
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
public func intersection(_ lhs: VersionSpecifier, _ rhs: VersionSpecifier) -> VersionSpecifier? { // swiftlint:disable:this cyclomatic_complexity
	switch (lhs, rhs) {
	// Unfortunately, patterns with a wildcard _ are not considered exhaustive,
	// so do the same thing manually. – swiftlint:disable:this vertical_whitespace_between_cases
	case (.any, .any), (.any, .exactly):
		return rhs

	case let (.any, .atLeast(rv)):
		return .atLeast(rv.discardingBuildMetadata)

	case let (.any, .compatibleWith(rv)):
		return .compatibleWith(rv.discardingBuildMetadata)

	case (.exactly, .any):
		return lhs

	case let (.compatibleWith(lv), .any):
		return .compatibleWith(lv.discardingBuildMetadata)

	case let (.atLeast(lv), .any):
		return .atLeast(lv.discardingBuildMetadata)

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
		return .atLeast(max(lv.discardingBuildMetadata, rv.discardingBuildMetadata))

	case let (.atLeast(lv), .compatibleWith(rv)):
		return intersection(atLeast: lv.discardingBuildMetadata, compatibleWith: rv.discardingBuildMetadata)

	case let (.atLeast(lv), .exactly(rv)):
		return intersection(atLeast: lv.discardingBuildMetadata, exactly: rv)

	case let (.compatibleWith(lv), .atLeast(rv)):
		return intersection(atLeast: rv.discardingBuildMetadata, compatibleWith: lv.discardingBuildMetadata)

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

		return .compatibleWith(max(lv.discardingBuildMetadata, rv.discardingBuildMetadata))

	case let (.compatibleWith(lv), .exactly(rv)):
		return intersection(compatibleWith: lv.discardingBuildMetadata, exactly: rv)

	case let (.exactly(lv), .atLeast(rv)):
		return intersection(atLeast: rv.discardingBuildMetadata, exactly: lv)

	case let (.exactly(lv), .compatibleWith(rv)):
		return intersection(compatibleWith: rv.discardingBuildMetadata, exactly: lv)

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
public func intersection<S: Sequence>(_ specs: S) -> VersionSpecifier? where S.Iterator.Element == VersionSpecifier {
	return specs.reduce(nil) { (left: VersionSpecifier?, right: VersionSpecifier) -> VersionSpecifier? in
		if let left = left {
			return intersection(left, right)
		} else {
			return right
		}
	}
}

extension String {

	/// Returns true if self contain any of the characters from the given set
	fileprivate func containsAny(_ characterSet: CharacterSet) -> Bool {
		return self.rangeOfCharacter(from: characterSet) != nil
	}
}
