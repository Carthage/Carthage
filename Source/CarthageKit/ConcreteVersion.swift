import Foundation
import Result
import Utility

/**
Wrapper around PinnedVersion/SementicVersion that can be ordered on relevance and avoids multiple invocations of the parsing logic for the Version from a string.

Semantic versions are first, ordered descending, then versions that do not comply with the semantic structure (*.*.*).
*/

// swiftlint:disable vertical_parameter_alignment
struct ConcreteVersion: Comparable, Hashable, CustomStringConvertible {
	public let pinnedVersion: PinnedVersion
	public let semanticVersion: Version?

	public init(string: String) {
		self.init(pinnedVersion: PinnedVersion(string))
	}

	public init(pinnedVersion: PinnedVersion) {
		self.pinnedVersion = pinnedVersion
		let result = Version.from(pinnedVersion)
		switch result {
		case .success(let semanticVersion):
			self.semanticVersion = semanticVersion
		default:
			self.semanticVersion = nil
		}
	}

	public init(semanticVersion: Version) {
		self.pinnedVersion = PinnedVersion(semanticVersion.description)
		self.semanticVersion = semanticVersion
	}

	private static func compare(lhs: ConcreteVersion, rhs: ConcreteVersion) -> ComparisonResult {
		let leftVersion = lhs.semanticVersion
		let rightVersion = rhs.semanticVersion

		if leftVersion != nil && rightVersion != nil {
			let v1 = leftVersion!
			let v2 = rightVersion!
			return v1 < v2 ? .orderedDescending : v2 < v1 ? .orderedAscending : .orderedSame
		} else if leftVersion != nil {
			return .orderedAscending
		} else if rightVersion != nil {
			return .orderedDescending
		}

		let s1 = lhs.pinnedVersion.commitish
		let s2 = rhs.pinnedVersion.commitish
		return s1 < s2 ? .orderedAscending : s2 < s1 ? .orderedDescending : .orderedSame
	}

	// All the comparison methods are intentionally defined inline (while the protocol only requires '<' and '==') to increase performance (requires 1 function call instead of 2 function calls this way).
	public static func == (lhs: ConcreteVersion, rhs: ConcreteVersion) -> Bool {
		return compare(lhs: lhs, rhs: rhs) == .orderedSame
	}

	public static func < (lhs: ConcreteVersion, rhs: ConcreteVersion) -> Bool {
		return compare(lhs: lhs, rhs: rhs) == .orderedAscending
	}

	public static func > (lhs: ConcreteVersion, rhs: ConcreteVersion) -> Bool {
		return compare(lhs: lhs, rhs: rhs) == .orderedDescending
	}

	public static func >= (lhs: ConcreteVersion, rhs: ConcreteVersion) -> Bool {
		let comparisonResult = compare(lhs: lhs, rhs: rhs)
		return comparisonResult == .orderedSame || comparisonResult == .orderedDescending
	}

	public static func <= (lhs: ConcreteVersion, rhs: ConcreteVersion) -> Bool {
		let comparisonResult = compare(lhs: lhs, rhs: rhs)
		return comparisonResult == .orderedSame || comparisonResult == .orderedAscending
	}

	public var description: String {
		return pinnedVersion.description
	}

	public var hashValue: Int {
		return pinnedVersion.hashValue
	}
}

/**
A Dependency with a concrete version.
*/
struct ConcreteVersionedDependency: Hashable {
	public let dependency: Dependency
	public let concreteVersion: ConcreteVersion

	public var hashValue: Int {
		return 37 &* dependency.hashValue &+ concreteVersion.hashValue
	}

	public static func == (lhs: ConcreteVersionedDependency, rhs: ConcreteVersionedDependency) -> Bool {
		return lhs.dependency == rhs.dependency && lhs.concreteVersion == rhs.concreteVersion
	}
}

/**
A version specification as was defined by a concrete versioned dependency, or nil if it was defined at the top level (i.e. Cartfile)
*/
struct ConcreteVersionSetDefinition {
	public let definingDependency: ConcreteVersionedDependency?
	public let versionSpecifier: VersionSpecifier
}

/**
Optimized set to keep track of a resolved set of concrete versions which are valid according to the current specifications.

The set conforms to Sequence to be iteratable and always maintains its natural sorting order.

Additions/removals/lookups have O(log(N)) time complexity.

This is intentionally a class instead of a struct to have control over when and how a copy is made of this set.
*/
final class ConcreteVersionSet: Sequence, CustomStringConvertible {
	public typealias Element = ConcreteVersion
	public typealias Iterator = ConcreteVersionSetIterator

	// MARK: - Public properties

	/**
	The collection of definitions that define the versions in this set.
	*/
	public private(set) var definitions: [ConcreteVersionSetDefinition]
	public var pinnedVersionSpecifier: VersionSpecifier?

	public var isPinned: Bool {
		return pinnedVersionSpecifier != nil
	}

	// MARK: - Private properties

	private var semanticVersions: SortedSet<ConcreteVersion>
	private var nonVersions: SortedSet<ConcreteVersion>
	private var preReleaseVersions: SortedSet<ConcreteVersion>

	// MARK: - Initializers

	public convenience init() {
		self.init(semanticVersions: SortedSet<ConcreteVersion>(),
				  nonVersions: SortedSet<ConcreteVersion>(),
				  preReleaseVersions: SortedSet<ConcreteVersion>(),
				  definitions: [ConcreteVersionSetDefinition]())
	}

	private init(semanticVersions: SortedSet<ConcreteVersion>,
				 nonVersions: SortedSet<ConcreteVersion>,
				 preReleaseVersions: SortedSet<ConcreteVersion>,
				 definitions: [ConcreteVersionSetDefinition],
				 pinnedVersionSpecifier: VersionSpecifier? = nil) {
		self.semanticVersions = semanticVersions
		self.nonVersions = nonVersions
		self.preReleaseVersions = preReleaseVersions
		self.definitions = definitions
		self.pinnedVersionSpecifier = pinnedVersionSpecifier
	}

	// MARK: - Public methods

	/**
	Creates a copy of this set.
	*/
	public var copy: ConcreteVersionSet {
		return ConcreteVersionSet(
			semanticVersions: semanticVersions,
			nonVersions: nonVersions,
			preReleaseVersions: preReleaseVersions,
			definitions: definitions,
			pinnedVersionSpecifier: pinnedVersionSpecifier
		)
	}

	/**
	Number of elements in the set.
	*/
	public var count: Int {
		return semanticVersions.count + nonVersions.count + preReleaseVersions.count
	}

	/**
	Whether the set has elements or not.
	*/
	public var isEmpty: Bool {
		return semanticVersions.isEmpty && nonVersions.isEmpty && preReleaseVersions.isEmpty
	}

	/**
	First version in the set.
	*/
	public var first: ConcreteVersion? {
		return self.semanticVersions.first ?? (self.preReleaseVersions.first ?? self.nonVersions.first)
	}

	/**
	Adds a dependency tree specification to the list of origins for the versions in this set.
	*/
	public func addDefinition(_ definition: ConcreteVersionSetDefinition) {
		definitions.append(definition)
	}

	/**
	Inserts the specified version in this set.
	*/
	@discardableResult
	public func insert(_ version: ConcreteVersion) -> Bool {
		if let semanticVersion = version.semanticVersion {
			if semanticVersion.isPreRelease {
				return preReleaseVersions.insert(version)
			} else {
				return semanticVersions.insert(version)
			}
		} else {
			return nonVersions.insert(version)
		}
	}

	/**
	Removes the sepecified version from this set.
	*/
	@discardableResult
	public func remove(_ version: ConcreteVersion) -> Bool {
		if let semanticVersion = version.semanticVersion {
			if semanticVersion.isPreRelease {
				return preReleaseVersions.remove(version)
			} else {
				return semanticVersions.remove(version)
			}
		} else {
			return nonVersions.remove(version)
		}
	}

	/**
	Removes all elements from the set.
	*/
	public func removeAll(except version: ConcreteVersion) {
		if let semanticVersion = version.semanticVersion {
			if semanticVersion.isPreRelease {
				semanticVersions.removeAll()
				preReleaseVersions.removeAll(except: version)
			} else {
				preReleaseVersions.removeAll()
				semanticVersions.removeAll(except: version)
			}
			nonVersions.removeAll()
		} else {
			semanticVersions.removeAll()
			nonVersions.removeAll(except: version)
			preReleaseVersions.removeAll(except: version)
		}
	}

	/**
	Retains all versions in this set which are compatible with the specified version specifier.
	*/
	public func retainVersions(compatibleWith versionSpecifier: VersionSpecifier) {
		// This is an optimization to achieve O(log(N)) time complexity for this method instead of O(N)
		// Should be kept in sync with implementation of VersionSpecifier (better to move it there)
		var range: Range<Int>?
		var preReleaseRange: Range<Int>?

		switch versionSpecifier {
		case .any:
			preReleaseVersions.removeAll()
			return
		case .gitReference:
			return
		case .exactly(let requirement):
			let fixedVersion = ConcreteVersion(semanticVersion: requirement)
			range = self.range(for: semanticVersions, from: fixedVersion, to: fixedVersion)
			preReleaseRange = self.range(for: preReleaseVersions, from: fixedVersion, to: fixedVersion)
		case .atLeast(let requirement):
			let lowerBound = ConcreteVersion(semanticVersion: requirement)
			let preReleaseUpperBound = ConcreteVersion(semanticVersion:
				Version(requirement.major, requirement.minor, requirement.patch + 1))
			range = self.range(for: semanticVersions, from: lowerBound, to: nil)
			// Prerelease versions require exactly the same numeric components (major/minor/patch)
			preReleaseRange = self.range(for: preReleaseVersions, from: lowerBound, to: preReleaseUpperBound)
		case .compatibleWith(let requirement):
			let lowerBound = ConcreteVersion(semanticVersion: requirement)
			let upperBound = requirement.major > 0 ?
				ConcreteVersion(semanticVersion: Version(requirement.major + 1, 0, 0)) :
				ConcreteVersion(semanticVersion: Version(0, requirement.minor + 1, 0))
			let preReleaseUpperBound = ConcreteVersion(semanticVersion:
				Version(requirement.major, requirement.minor, requirement.patch + 1))
			range = self.range(for: semanticVersions, from: lowerBound, to: upperBound)
			preReleaseRange = self.range(for: preReleaseVersions, from: lowerBound, to: preReleaseUpperBound)
		}

		if let nonNilRange = range {
			semanticVersions.retain(range: nonNilRange)
		} else {
			semanticVersions.removeAll()
		}

		if let nonNilRange = preReleaseRange {
			preReleaseVersions.retain(range: nonNilRange)
		} else {
			preReleaseVersions.removeAll()
		}
	}

	/**
	Returns the conflicting definition for the specified versionSpecifier, or nil if no conflict could be found.
	*/
	public func conflictingDefinition(for versionSpecifier: VersionSpecifier) -> ConcreteVersionSetDefinition? {
		return definitions.first { intersection($0.versionSpecifier, versionSpecifier) == nil }
	}

	// MARK: - Sequence implementation

	public func makeIterator() -> Iterator {
		return ConcreteVersionSetIterator(self)
	}

	public struct ConcreteVersionSetIterator: IteratorProtocol {
		// swiftlint:disable next nesting
		typealias Element = ConcreteVersion

		private let versionSet: ConcreteVersionSet
		private var iteratingVersions = true
		private var iteratingPreReleaseVersions = false
		private var currentIterator: SortedSet<ConcreteVersion>.Iterator

		fileprivate init(_ versionSet: ConcreteVersionSet) {
			self.versionSet = versionSet
			self.currentIterator = versionSet.semanticVersions.makeIterator()
		}

		public mutating func next() -> Element? {
			var ret = currentIterator.next()
			if ret == nil && iteratingVersions {
				iteratingVersions = false
				iteratingPreReleaseVersions = true
				currentIterator = versionSet.preReleaseVersions.makeIterator()
				ret = currentIterator.next()
			}
			if ret == nil && iteratingPreReleaseVersions {
				iteratingPreReleaseVersions = false
				currentIterator = versionSet.nonVersions.makeIterator()
				ret = currentIterator.next()
			}
			return ret
		}
	}

	// MARK: - CustomStringConvertible

	public var description: String {
		var s = "["
		var first = true
		for concreteVersion in self {
			if !first {
				s += ", "
			}
			s += concreteVersion.description
			first = false
		}
		s += "]"
		return s
	}

	// MARK: - Private methods

	private func range(for versions: SortedSet<ConcreteVersion>, from lowerBound: ConcreteVersion, to upperBound: ConcreteVersion?) -> Range<Int>? {
		var lowerIndex = 0
		let upperIndex: Int
		let fixed = lowerBound == upperBound

		switch versions.search(lowerBound) {
		case .notFound(let i):
			upperIndex = i
			if fixed {
				lowerIndex = i
			}

		case .found(let i):
			upperIndex = i + 1
			if fixed {
				lowerIndex = i
			}
		}

		if !fixed, let definedUpperBound = upperBound {
			switch versions.search(definedUpperBound) {
			case .notFound(let i):
				lowerIndex = i
			case .found(let i):
				lowerIndex = i + 1
			}
		}

		if upperIndex > lowerIndex {
			return lowerIndex..<upperIndex
		} else {
			return nil
		}
	}
}
