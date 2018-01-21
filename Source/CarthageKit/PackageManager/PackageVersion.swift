/// A struct representing a semver version.
public struct PackageVersion {
	
	/// The major version.
	public let major: Int
	
	/// The minor version.
	public let minor: Int
	
	/// The patch version.
	public let patch: Int
	
	/// The pre-release identifier.
	public let prereleaseIdentifiers: [String]
	
	/// The build metadata.
	public let buildMetadataIdentifiers: [String]
	
	/// Create a version object.
	public init(
		_ major: Int,
		_ minor: Int,
		_ patch: Int,
		prereleaseIdentifiers: [String] = [],
		buildMetadataIdentifiers: [String] = []
		) {
		precondition(major >= 0 && minor >= 0 && patch >= 0, "Negative versioning is invalid.")
		self.major = major
		self.minor = minor
		self.patch = patch
		self.prereleaseIdentifiers = prereleaseIdentifiers
		self.buildMetadataIdentifiers = buildMetadataIdentifiers
	}
}

extension PackageVersion: Hashable {
	
	static public func == (lhs: PackageVersion, rhs: PackageVersion) -> Bool {
		return lhs.major == rhs.major &&
			lhs.minor == rhs.minor &&
			lhs.patch == rhs.patch &&
			lhs.prereleaseIdentifiers == rhs.prereleaseIdentifiers &&
			lhs.buildMetadataIdentifiers == rhs.buildMetadataIdentifiers
	}
	
	public var hashValue: Int {
		// FIXME: We need Swift hashing utilities; this is based on CityHash
		// inspired code inside the Swift stdlib.
		let mul: UInt64 = 0x9ddfea08eb382d69
		var result: UInt64 = 0
		result = (result &* mul) ^ UInt64(bitPattern: Int64(major.hashValue))
		result = (result &* mul) ^ UInt64(bitPattern: Int64(minor.hashValue))
		result = (result &* mul) ^ UInt64(bitPattern: Int64(patch.hashValue))
		result = prereleaseIdentifiers.reduce(result, { ($0 &* mul) ^ UInt64(bitPattern: Int64($1.hashValue)) })
		result = buildMetadataIdentifiers.reduce(result, { ($0 &* mul) ^ UInt64(bitPattern: Int64($1.hashValue)) })
		return Int(truncatingIfNeeded: result)
	}
}

extension PackageVersion: Comparable {
	
	func isEqualWithoutPrerelease(_ other: PackageVersion) -> Bool {
		return major == other.major && minor == other.minor && patch == other.patch
	}
	
	public static func < (lhs: PackageVersion, rhs: PackageVersion) -> Bool {
		let lhsComparators = [lhs.major, lhs.minor, lhs.patch]
		let rhsComparators = [rhs.major, rhs.minor, rhs.patch]
		
		if lhsComparators != rhsComparators {
			return lhsComparators.lexicographicallyPrecedes(rhsComparators)
		}
		
		guard lhs.prereleaseIdentifiers.count > 0 else {
			return false // Non-prerelease lhs >= potentially prerelease rhs
		}
		
		guard rhs.prereleaseIdentifiers.count > 0 else {
			return true // Prerelease lhs < non-prerelease rhs
		}
		
		let zippedIdentifiers = zip(lhs.prereleaseIdentifiers, rhs.prereleaseIdentifiers)
		for (lhsPrereleaseIdentifier, rhsPrereleaseIdentifier) in zippedIdentifiers {
			if lhsPrereleaseIdentifier == rhsPrereleaseIdentifier {
				continue
			}
			
			let typedLhsIdentifier: Any = Int(lhsPrereleaseIdentifier) ?? lhsPrereleaseIdentifier
			let typedRhsIdentifier: Any = Int(rhsPrereleaseIdentifier) ?? rhsPrereleaseIdentifier
			
			switch (typedLhsIdentifier, typedRhsIdentifier) {
			case let (int1 as Int, int2 as Int): return int1 < int2
			case let (string1 as String, string2 as String): return string1 < string2
			case (is Int, is String): return true // Int prereleases < String prereleases
			case (is String, is Int): return false
			default:
				return false
			}
		}
		
		return lhs.prereleaseIdentifiers.count < rhs.prereleaseIdentifiers.count
	}
}

extension PackageVersion: CustomStringConvertible {
	public var description: String {
		var base = "\(major).\(minor).\(patch)"
		if !prereleaseIdentifiers.isEmpty {
			base += "-" + prereleaseIdentifiers.joined(separator: ".")
		}
		if !buildMetadataIdentifiers.isEmpty {
			base += "+" + buildMetadataIdentifiers.joined(separator: ".")
		}
		return base
	}
}

public extension PackageVersion {
	
	/// Create a version object from string.
	///
	/// - Parameters:
	///   - string: The string to parse.
	init?(string: String) {
		let prereleaseStartIndex = string.index(of: "-")
		let metadataStartIndex = string.index(of: "+")
		
		let requiredEndIndex = prereleaseStartIndex ?? metadataStartIndex ?? string.endIndex
		let requiredCharacters = string.prefix(upTo: requiredEndIndex)
		let requiredComponents = requiredCharacters
			.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
			.map(String.init).flatMap({ Int($0) }).filter({ $0 >= 0 })
		
		guard requiredComponents.count == 3 else { return nil }
		
		self.major = requiredComponents[0]
		self.minor = requiredComponents[1]
		self.patch = requiredComponents[2]
		
		func identifiers(start: String.Index?, end: String.Index) -> [String] {
			guard let start = start else { return [] }
			let identifiers = string[string.index(after: start)..<end]
			return identifiers.split(separator: ".").map(String.init)
		}
		
		self.prereleaseIdentifiers = identifiers(
			start: prereleaseStartIndex,
			end: metadataStartIndex ?? string.endIndex)
		self.buildMetadataIdentifiers = identifiers(
			start: metadataStartIndex,
			end: string.endIndex)
	}
}

extension PackageVersion: ExpressibleByStringLiteral {
	
	public init(stringLiteral value: String) {
		guard let version = PackageVersion(string: value) else {
			fatalError("\(value) is not a valid version")
		}
		self = version
	}
	
	public init(extendedGraphemeClusterLiteral value: String) {
		self.init(stringLiteral: value)
	}
	
	public init(unicodeScalarLiteral value: String) {
		self.init(stringLiteral: value)
	}
}

// MARK:- Range operations
extension ClosedRange where Bound == PackageVersion {
	/// Marked as unavailable because we have custom rules for contains.
	public func contains(_ element: PackageVersion) -> Bool {
		// Unfortunately, we can't use unavailable here.
		fatalError("contains(_:) is unavailable, use contains(version:)")
	}
}

// Disabled because compiler hits an assertion https://bugs.swift.org/browse/SR-5014
#if false
	extension CountableRange where Bound == Version {
		/// Marked as unavailable because we have custom rules for contains.
		public func contains(_ element: Version) -> Bool {
			// Unfortunately, we can't use unavailable here.
			fatalError("contains(_:) is unavailable, use contains(version:)")
		}
	}
#endif

extension Range where Bound == PackageVersion {
	/// Marked as unavailable because we have custom rules for contains.
	public func contains(_ element: PackageVersion) -> Bool {
		// Unfortunately, we can't use unavailable here.
		fatalError("contains(_:) is unavailable, use contains(version:)")
	}
}

extension Range where Bound == PackageVersion {
	
	public func contains(version: PackageVersion) -> Bool {
		// Special cases if version contains prerelease identifiers.
		if !version.prereleaseIdentifiers.isEmpty {
			// If the ranage does not contain prerelease identifiers, return false.
			if lowerBound.prereleaseIdentifiers.isEmpty && upperBound.prereleaseIdentifiers.isEmpty {
				return false
			}
			
			// At this point, one of the bounds contains prerelease identifiers.
			//
			// Reject 2.0.0-alpha when upper bound is 2.0.0.
			if upperBound.prereleaseIdentifiers.isEmpty && upperBound.isEqualWithoutPrerelease(version) {
				return false
			}
		}
		
		// Otherwise, apply normal contains rules.
		return version >= lowerBound && version < upperBound
	}
}
