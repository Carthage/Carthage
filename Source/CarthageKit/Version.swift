// swiftlint:disable file_length

import Foundation
import Result
import ReactiveSwift

/// An abstract type representing a way to specify versions.
public protocol VersionType: Hashable {}

/// A semantic version.
public struct SemanticVersion: VersionType, Codable {
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

	/// The set of all characters present in valid semantic versions.
	fileprivate static let versionCharacterSet = CharacterSet(charactersIn: "0123456789.")

	/// Attempts to parse a semantic version from a PinnedVersion.
	public static func from(_ pinnedVersion: PinnedVersion) -> Result<SemanticVersion, ScannableError> {
		let scanner = Scanner(string: pinnedVersion.commitish)

		// Skip leading characters, like "v" or "version-" or anything like
		// that.
		scanner.scanUpToCharacters(from: versionCharacterSet, into: nil)

		return self.from(scanner).flatMap { version in
			if scanner.isAtEnd {
				return .success(version)
			} else {
				// Disallow versions like "1.0a5", because we only support
				// SemVer right now.
				return .failure(ScannableError(message: "syntax of version \"\(version)\" is unsupported", currentLine: scanner.currentLine))
			}
		}
	}
}

extension SemanticVersion: Scannable {
	/// Attempts to parse a semantic version from a human-readable string of the
	/// form "a.b.c".
	public static func from(_ scanner: Scanner) -> Result<SemanticVersion, ScannableError> {
		var version: NSString?
		guard scanner.scanCharacters(from: versionCharacterSet, into: &version), let unwrapped = version else {
			return .failure(ScannableError(message: "expected version", currentLine: scanner.currentLine))
		}

		let components = (unwrapped as String)
			.split(omittingEmptySubsequences: true) { $0 == "." }
		if components.isEmpty {
			return .failure(ScannableError(message: "expected version", currentLine: scanner.currentLine))
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

		let patch = parseVersion(at: 2) ?? 0

		return .success(self.init(major: major, minor: minor, patch: patch))
	}
}

extension SemanticVersion: Comparable {
	public static func < (_ lhs: SemanticVersion, _ rhs: SemanticVersion) -> Bool {
		return lhs.components.lexicographicallyPrecedes(rhs.components)
	}

	public static func == (_ lhs: SemanticVersion, _ rhs: SemanticVersion) -> Bool {
		return lhs.components == rhs.components
	}
}

extension SemanticVersion: Hashable {
	public var hashValue: Int {
		return components.reduce(0) { $0 ^ $1.hashValue }
	}
}

extension SemanticVersion: CustomStringConvertible {
	public var description: String {
		return components.map { $0.description }.joined(separator: ".")
	}
}

/// An immutable version that a project can be pinned to.
public struct PinnedVersion: VersionType {
	/// The commit SHA, or name of the tag, to pin to.
	public let commitish: String

	public init(_ commitish: String) {
		self.commitish = commitish
	}

	public var hashValue: Int {
		return commitish.hashValue
	}

	public static func == (_ lhs: PinnedVersion, _ rhs: PinnedVersion) -> Bool {
		return lhs.commitish == rhs.commitish
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

/// Describes which versions are acceptable for satisfying a dependency
/// requirement.
public enum VersionSpecifier: VersionType {
	case any
	case atLeast(SemanticVersion)
	case compatibleWith(SemanticVersion)
	case exactly(SemanticVersion)
	case gitReference(String)

	/// Determines whether the given version satisfies this version specifier.
	public func isSatisfied(by version: PinnedVersion) -> Bool {
		func withSemanticVersion(_ predicate: (SemanticVersion) -> Bool) -> Bool {
			if let semanticVersion = SemanticVersion.from(version).value {
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

	public var hashValue: Int {
		switch self {
		case .any:
			return 0

		case let .atLeast(version):
			return 1 + version.hashValue

		case let .compatibleWith(version):
			return 2 + version.hashValue

		case let .exactly(version):
			return 3 + version.hashValue

		case let .gitReference(commitish):
			return commitish.hashValue
		}
	}

	public static func == (_ lhs: VersionSpecifier, _ rhs: VersionSpecifier) -> Bool {
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
}

extension VersionSpecifier: Scannable {
	/// Attempts to parse a VersionSpecifier.
	public static func from(_ scanner: Scanner) -> Result<VersionSpecifier, ScannableError> {
		if scanner.scanString("==", into: nil) {
			return SemanticVersion.from(scanner).map { .exactly($0) }
		} else if scanner.scanString(">=", into: nil) {
			return SemanticVersion.from(scanner).map { .atLeast($0) }
		} else if scanner.scanString("~>", into: nil) {
			return SemanticVersion.from(scanner).map { .compatibleWith($0) }
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

private func intersection(atLeast: SemanticVersion, compatibleWith: SemanticVersion) -> VersionSpecifier? {
	if atLeast.major > compatibleWith.major {
		return nil
	} else if atLeast.major < compatibleWith.major {
		return .compatibleWith(compatibleWith)
	} else {
		return .compatibleWith(max(atLeast, compatibleWith))
	}
}

private func intersection(atLeast: SemanticVersion, exactly: SemanticVersion) -> VersionSpecifier? {
	if atLeast > exactly {
		return nil
	}

	return .exactly(exactly)
}

private func intersection(compatibleWith: SemanticVersion, exactly: SemanticVersion) -> VersionSpecifier? {
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
public func intersection<S: Sequence>(_ specs: S) -> VersionSpecifier? where S.Iterator.Element == VersionSpecifier {
	return specs.reduce(nil) { (left: VersionSpecifier?, right: VersionSpecifier) -> VersionSpecifier? in
		if let left = left {
			return intersection(left, right)
		} else {
			return right
		}
	}
}
