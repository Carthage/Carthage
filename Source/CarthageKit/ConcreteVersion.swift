import Foundation

/**
Wrapper around PinnedVersion/SementicVersion that can be ordered on relevance and avoids multiple invocations of the parsing logic for the SemanticVersion from a string.

Semantic versions are first, ordered descending, then versions that do not comply with the semantic structure (*.*.*).
*/

// swiftlint:disable vertical_parameter_alignment
struct ConcreteVersion: Comparable, CustomStringConvertible {
	public let pinnedVersion: PinnedVersion
	public let semanticVersion: SemanticVersion?

	public init(string: String) {
		self.init(pinnedVersion: PinnedVersion(string))
	}

	public init(pinnedVersion: PinnedVersion) {
		self.pinnedVersion = pinnedVersion
		let result = SemanticVersion.from(pinnedVersion)
		switch result {
		case .success(let semanticVersion):
			self.semanticVersion = semanticVersion
		default:
			self.semanticVersion = nil
		}
	}

	public init(semanticVersion: SemanticVersion) {
		self.pinnedVersion = PinnedVersion(semanticVersion.description)
		self.semanticVersion = semanticVersion
	}

	private static func compare(lhs: ConcreteVersion, rhs: ConcreteVersion) -> ComparisonResult {
		let leftSemanticVersion = lhs.semanticVersion
		let rightSemanticVersion = rhs.semanticVersion

		if leftSemanticVersion != nil && rightSemanticVersion != nil {
			let v1 = leftSemanticVersion!
			let v2 = rightSemanticVersion!
			return v1 < v2 ? .orderedDescending : v2 < v1 ? .orderedAscending : .orderedSame
		} else if leftSemanticVersion != nil {
			return .orderedAscending
		} else if rightSemanticVersion != nil {
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
}

/**
A Dependency with a concrete version.
*/
struct ConcreteVersionedDependency {
	let dependency: Dependency
	let concreteVersion: ConcreteVersion
}

/**
A version specification as was defined by a concrete versioned dependency, or nil if it was defined at the top level (i.e. Cartfile)
*/
struct ConcreteVersionSetDefinition {
	let definingDependency: ConcreteVersionedDependency?
	let versionSpecifier: VersionSpecifier
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
	private var nonSemanticVersions: SortedSet<ConcreteVersion>

	// MARK: - Initializers

	public convenience init() {
		self.init(semanticVersions: SortedSet<ConcreteVersion>(), nonSemanticVersions: SortedSet<ConcreteVersion>(), definitions: [ConcreteVersionSetDefinition]())
	}
	
	private init(semanticVersions: SortedSet<ConcreteVersion>,
				 nonSemanticVersions: SortedSet<ConcreteVersion>,
				 definitions: [ConcreteVersionSetDefinition],
				 pinnedVersionSpecifier: VersionSpecifier? = nil) {
		self.semanticVersions = semanticVersions
		self.nonSemanticVersions = nonSemanticVersions
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
			nonSemanticVersions: nonSemanticVersions,
			definitions: definitions,
			pinnedVersionSpecifier: pinnedVersionSpecifier
		)
	}

	/**
	Number of elements in the set.
	*/
	public var count: Int {
		return semanticVersions.count + nonSemanticVersions.count
	}

	/**
	Whether the set has elements or not.
	*/
	public var isEmpty: Bool {
		return semanticVersions.isEmpty && nonSemanticVersions.isEmpty
	}

	/**
	First version in the set.
	*/
	public var first: ConcreteVersion? {
		return self.semanticVersions.first ?? self.nonSemanticVersions.first
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
		if version.semanticVersion != nil {
			return semanticVersions.insert(version)
		} else {
			return nonSemanticVersions.insert(version)
		}
	}

	/**
	Removes the sepecified version from this set.
	*/
	@discardableResult
	public func remove(_ version: ConcreteVersion) -> Bool {
		if version.semanticVersion != nil {
			return semanticVersions.remove(version)
		} else {
			return nonSemanticVersions.remove(version)
		}
	}

	/**
	Removes all elements from the set.
	*/
	public func removeAll(except version: ConcreteVersion) {
		if version.semanticVersion != nil {
			semanticVersions.removeAll(except: version)
			nonSemanticVersions.removeAll()
		} else {
			semanticVersions.removeAll()
			nonSemanticVersions.removeAll(except: version)
		}
	}

	/**
	Retains all versions in this set which are compatible with the specified version specifier.
	*/
	public func retainVersions(compatibleWith versionSpecifier: VersionSpecifier) {
		// This is an optimization to achieve O(log(N)) time complexity for this method instead of O(N)
		var range: Range<Int>?

		switch versionSpecifier {
		case .any, .gitReference:
			return
		case .exactly(let requirement):
			let fixedVersion = ConcreteVersion(semanticVersion: requirement)
			range = self.range(for: semanticVersions, from: fixedVersion, to: fixedVersion)
		case .atLeast(let requirement):
			range = self.range(for: semanticVersions, from: ConcreteVersion(semanticVersion: requirement), to: nil)
		case .compatibleWith(let requirement):
			let lowerBound = ConcreteVersion(semanticVersion: requirement)
			let upperBound = requirement.major > 0 ?
				ConcreteVersion(semanticVersion: SemanticVersion(major: requirement.major + 1, minor: 0, patch: 0)) :
				ConcreteVersion(semanticVersion: SemanticVersion(major: 0, minor: requirement.minor + 1, patch: 0))
			range = self.range(for: semanticVersions, from: lowerBound, to: upperBound)
		}

		if let nonNilRange = range {
			semanticVersions.retain(range: nonNilRange)
		} else {
			semanticVersions.removeAll()
		}
	}

	// MARK: - Sequence implementation

	public func makeIterator() -> Iterator {
		return ConcreteVersionSetIterator(self)
	}

	public struct ConcreteVersionSetIterator: IteratorProtocol {
		typealias Element = ConcreteVersion

		private let versionSet: ConcreteVersionSet
		private var iteratingSemanticVersions = true
		private var currentIterator: SortedSet<ConcreteVersion>.Iterator

		fileprivate init(_ versionSet: ConcreteVersionSet) {
			self.versionSet = versionSet
			self.currentIterator = versionSet.semanticVersions.makeIterator()
		}

		public mutating func next() -> Element? {
			var ret = currentIterator.next()
			if ret == nil && iteratingSemanticVersions {
				iteratingSemanticVersions = false
				currentIterator = versionSet.nonSemanticVersions.makeIterator()
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
