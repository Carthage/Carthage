import Foundation
import Result
import ReactiveSwift

// swiftlint:disable missing_docs
// swiftlint:disable vertical_parameter_alignment_on_call
// swiftlint:disable vertical_parameter_alignment
typealias DependencyEntry = (key: Dependency, value: VersionSpecifier)

/// Responsible for resolving acyclic dependency graphs.
public final class FastResolver: ResolverProtocol {
	private let versionsForDependency: (Dependency) -> SignalProducer<PinnedVersion, CarthageError>
	private let resolvedGitReference: (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
	private let dependenciesForDependency: (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>

	private enum ResolverState {
		case rejected, accepted
	}

	/// Instantiates a dependency graph resolver with the given behaviors.
	///
	/// versionsForDependency - Sends a stream of available versions for a
	///                         dependency.
	/// dependenciesForDependency - Loads the dependencies for a specific
	///                             version of a dependency.
	/// resolvedGitReference - Resolves an arbitrary Git reference to the
	///                        latest object.
	public init(
		versionsForDependency: @escaping (Dependency) -> SignalProducer<PinnedVersion, CarthageError>,
		dependenciesForDependency: @escaping (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>,
		resolvedGitReference: @escaping (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
		) {
		self.versionsForDependency = versionsForDependency
		self.dependenciesForDependency = dependenciesForDependency
		self.resolvedGitReference = resolvedGitReference
	}

	/// Attempts to determine the latest valid version to use for each
	/// dependency in `dependencies`, and all nested dependencies thereof.
	///
	/// Sends a dictionary with each dependency and its resolved version.
	public func resolve(
		dependencies: [Dependency: VersionSpecifier],
		lastResolved: [Dependency: PinnedVersion]? = nil,
		dependenciesToUpdate: [String]? = nil
		) -> SignalProducer<[Dependency: PinnedVersion], CarthageError> {
		let result: Result<[Dependency: PinnedVersion], CarthageError>

		let start = Date()

		// Ensure we start and finish with a clean slate
		let pinnedVersions = lastResolved ?? [Dependency: PinnedVersion]()
		let dependencyRetriever = DependencyRetriever(versionsForDependency: versionsForDependency,
													  dependenciesForDependency: dependenciesForDependency,
													  resolvedGitReference: resolvedGitReference,
													  pinnedVersions: pinnedVersions)
		let updatableDependencyNames = dependenciesToUpdate.map { Set($0) } ?? Set()

		let requiredDependencies: AnySequence<DependencyEntry>
		let hasSpecificDepedenciesToUpdate = !updatableDependencyNames.isEmpty

		if hasSpecificDepedenciesToUpdate {
			requiredDependencies = AnySequence(dependencies.filter { dependency, _ in
				updatableDependencyNames.contains(dependency.name) || pinnedVersions[dependency] != nil
			})
		} else {
			requiredDependencies = AnySequence(dependencies)
		}

		do {
			let dependencySet = try DependencySet(requiredDependencies: requiredDependencies,
												  updatableDependencyNames: updatableDependencyNames,
												  retriever: dependencyRetriever)
			let resolverResult = try backtrack(dependencySet: dependencySet)

			switch resolverResult.state {
			case .accepted:
				break
			case .rejected:
				throw CarthageError.unresolvedDependencies(dependencySet.unresolvedDependencies.map { $0.name })
			}

			result = .success(resolverResult.dependencySet.resolvedDependencies)
		} catch let error {
			let carthageError: CarthageError = (error as? CarthageError) ?? CarthageError.internalError(description: error.localizedDescription)
			result = .failure(carthageError)
		}

		let end = Date()

		print("Fast resolver took: \(end.timeIntervalSince(start)) s.")

		return SignalProducer(result: result)
	}

	/**
	Backtracking algorithm to resolve the dependency set.
	
	See: https://en.wikipedia.org/wiki/Backtracking
	*/
	private func backtrack(dependencySet: DependencySet) throws -> (state: ResolverState, dependencySet: DependencySet) {
		if dependencySet.isRejected {
			return (.rejected, dependencySet)
		} else if dependencySet.isComplete {
			return (.accepted, dependencySet)
		}

		var result: (state: ResolverState, dependencySet: DependencySet)? = nil
		while result == nil {
			try autoreleasepool {
				if let subSet = try dependencySet.popSubSet() {
					// Backtrack again with this subset
					let nestedResult = try backtrack(dependencySet: subSet)

					switch nestedResult.state {
					case .rejected:
						break
					case .accepted:
						// Set contains all dependencies, we've got a winner
						result = (.accepted, nestedResult.dependencySet)
					}
				} else {
					// All done
					result = (.rejected, dependencySet)
				}
			}
		}

		return result!
	}
}

final class DependencyRetriever {
	private var pinnedVersions: [Dependency: PinnedVersion]
	private let versionsForDependency: (Dependency) -> SignalProducer<PinnedVersion, CarthageError>
	private let resolvedGitReference: (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
	private let dependenciesForDependency: (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>

	private var dependencyCache = [PinnedDependency: [DependencyEntry]]()
	private var versionsCache = [VersionedDependency: ConcreteVersionSet]()

	init(
		versionsForDependency: @escaping (Dependency) -> SignalProducer<PinnedVersion, CarthageError>,
		dependenciesForDependency: @escaping (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>,
		resolvedGitReference: @escaping (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>,
		pinnedVersions: [Dependency: PinnedVersion]
		) {
		self.versionsForDependency = versionsForDependency
		self.dependenciesForDependency = dependenciesForDependency
		self.resolvedGitReference = resolvedGitReference
		self.pinnedVersions = pinnedVersions
	}

	private struct PinnedDependency: Hashable {
		let dependency: Dependency
		let pinnedVersion: PinnedVersion

		public var hashValue: Int {
			return 37 &* dependency.hashValue &+ pinnedVersion.hashValue
		}

		public static func == (lhs: PinnedDependency, rhs: PinnedDependency) -> Bool {
			return lhs.dependency == rhs.dependency && lhs.pinnedVersion == rhs.pinnedVersion
		}
	}

	private struct VersionedDependency: Hashable {
		let dependency: Dependency
		let versionSpecifier: VersionSpecifier
		let isUpdatable: Bool

		public var hashValue: Int {
			var hash = dependency.hashValue
			hash = 37 &* hash &+ versionSpecifier.hashValue
			hash = 37 &* hash &+ isUpdatable.hashValue
			return hash
		}

		public static func == (lhs: VersionedDependency, rhs: VersionedDependency) -> Bool {
			return lhs.dependency == rhs.dependency && lhs.versionSpecifier == rhs.versionSpecifier
		}
	}

	private func findAllVersionsUncached(for dependency: Dependency, compatibleWith versionSpecifier: VersionSpecifier, isUpdatable: Bool) throws -> ConcreteVersionSet {
		let versionSet = ConcreteVersionSet()

		if !isUpdatable, let pinnedVersion = pinnedVersions[dependency] {
			versionSet.insert(ConcreteVersion(pinnedVersion: pinnedVersion))
			versionSet.pinnedVersionSpecifier = versionSpecifier
		} else if isUpdatable {
			let pinnedVersionsProducer: SignalProducer<PinnedVersion, CarthageError>

			switch versionSpecifier {
			case .gitReference(let hash):
				pinnedVersionsProducer = resolvedGitReference(dependency, hash)
			default:
				pinnedVersionsProducer = versionsForDependency(dependency)
			}

			let concreteVersionsProducer = pinnedVersionsProducer.filterMap { pinnedVersion -> ConcreteVersion? in
				let concreteVersion = ConcreteVersion(pinnedVersion: pinnedVersion)
				versionSet.insert(concreteVersion)
				return nil
			}

			_ = try concreteVersionsProducer.collect().first()!.dematerialize()
		}

		versionSet.retainVersions(compatibleWith: versionSpecifier)
		return versionSet
	}

	func findAllVersions(for dependency: Dependency, compatibleWith versionSpecifier: VersionSpecifier, isUpdatable: Bool) throws -> ConcreteVersionSet {
		let versionedDependency = VersionedDependency(dependency: dependency, versionSpecifier: versionSpecifier, isUpdatable: isUpdatable)

		let concreteVersionSet = try versionsCache.object(
			for: versionedDependency,
			byStoringDefault: try findAllVersionsUncached(for: dependency, compatibleWith: versionSpecifier, isUpdatable: isUpdatable)
		)

		guard !isUpdatable || !concreteVersionSet.isEmpty else {
			throw CarthageError.requiredVersionNotFound(dependency, versionSpecifier)
		}

		return concreteVersionSet
	}

	func findDependencies(for dependency: Dependency, version: ConcreteVersion) throws -> [DependencyEntry] {
		let pinnedDependency = PinnedDependency(dependency: dependency, pinnedVersion: version.pinnedVersion)
		let result: [DependencyEntry] = try dependencyCache.object(
			for: pinnedDependency,
			byStoringDefault: try dependenciesForDependency(dependency, version.pinnedVersion).collect().first()!.dematerialize()
		)
		return result
	}
}

final class DependencySet {
	private var contents: [Dependency: ConcreteVersionSet]

	private var updatableDependencyNames: Set<String>

	private let retriever: DependencyRetriever

	public private(set) var unresolvedDependencies: Set<Dependency>

	public private(set) var isRejected = false

	public var isComplete: Bool {
		// Dependency resolution is complete if there are no unresolved dependencies anymore
		return unresolvedDependencies.isEmpty
	}

	public var isAccepted: Bool {
		return !isRejected && isComplete
	}

	public var copy: DependencySet {
		return DependencySet(
			unresolvedDependencies: unresolvedDependencies,
			updatableDependencyNames: updatableDependencyNames,
			contents: contents.mapValues { $0.copy },
			retriever: retriever)
	}

	public var resolvedDependencies: [Dependency: PinnedVersion] {
		return contents.filterMapValues { $0.first?.pinnedVersion }
	}

	private init(unresolvedDependencies: Set<Dependency>,
				 updatableDependencyNames: Set<String>,
				 contents: [Dependency: ConcreteVersionSet],
				 retriever: DependencyRetriever) {
		self.unresolvedDependencies = unresolvedDependencies
		self.updatableDependencyNames = updatableDependencyNames
		self.contents = contents
		self.retriever = retriever
	}

	convenience init(requiredDependencies: AnySequence<DependencyEntry>,
							updatableDependencyNames: Set<String>,
							retriever: DependencyRetriever) throws {
		self.init(unresolvedDependencies: Set(requiredDependencies.map { $0.key }),
				  updatableDependencyNames: updatableDependencyNames,
				  contents: [Dependency: ConcreteVersionSet](),
				  retriever: retriever)
		try self.update(with: requiredDependencies)
	}

	public func removeVersion(_ version: ConcreteVersion, for dependency: Dependency) -> Bool {
		if let versionSet = contents[dependency] {
			versionSet.remove(version)
			if versionSet.isEmpty {
				isRejected = true
			}

			return true
		}

		return false
	}

	public func setVersions(_ versions: ConcreteVersionSet, for dependency: Dependency) {
		contents[dependency] = versions
		unresolvedDependencies.insert(dependency)
		if versions.isEmpty {
			isRejected = true
		}
	}

	public func removeAllVersionsExcept(_ version: ConcreteVersion, for dependency: Dependency) {
		if let versionSet = versions(for: dependency) {
			versionSet.removeAll(except: version)
		}
	}

	public func constrainVersions(for dependency: Dependency, with versionSpecifier: VersionSpecifier) {
		if let versionSet = versions(for: dependency) {
			versionSet.retainVersions(compatibleWith: versionSpecifier)
			if versionSet.isEmpty {
				self.isRejected = true
			}
		}
	}

	public func versions(for dependency: Dependency) -> ConcreteVersionSet? {
		return contents[dependency]
	}

	public func containsDependency(_ dependency: Dependency) -> Bool {
		return contents[dependency] != nil
	}

	public func isUpdatableDependency(_ dependency: Dependency) -> Bool {
		return updatableDependencyNames.isEmpty || updatableDependencyNames.contains(dependency.name)
	}

	public func addUpdatableDependency(_ dependency: Dependency) {
		if !updatableDependencyNames.isEmpty {
			updatableDependencyNames.insert(dependency.name)
		}
	}

	public func popSubSet() throws -> DependencySet? {
		while !unresolvedDependencies.isEmpty {
			if let dependency = unresolvedDependencies.first, let versionSet = contents[dependency], let version = versionSet.first {
				let count = versionSet.count
				let newSet: DependencySet
				if count > 1 {
					let copy = self.copy
					copy.removeAllVersionsExcept(version, for: dependency)
					_ = removeVersion(version, for: dependency)
					newSet = copy
				} else {
					newSet = self
				}

				let transitiveDependencies = try retriever.findDependencies(for: dependency, version: version)

				newSet.unresolvedDependencies.remove(dependency)

				try newSet.update(with: AnySequence(transitiveDependencies), forceUpdatable: isUpdatableDependency(dependency))

				return newSet
			}
		}

		return nil
	}

	public func update(with dependencyEntries: AnySequence<DependencyEntry>, forceUpdatable: Bool = false) throws {
		// Find all versions for current dependencies

		for (dependency, versionSpecifier) in dependencyEntries {
			let isUpdatable = forceUpdatable || isUpdatableDependency(dependency)
			if forceUpdatable {
				addUpdatableDependency(dependency)
			}

			let existingVersionSet = versions(for: dependency)

			if existingVersionSet == nil || (existingVersionSet!.isPinned && isUpdatable) {
				let validVersions = try retriever.findAllVersions(for: dependency, compatibleWith: versionSpecifier, isUpdatable: isUpdatable)
				setVersions(validVersions, for: dependency)

				if let pinnedVersionSpecifier = existingVersionSet?.pinnedVersionSpecifier {
					constrainVersions(for: dependency, with: pinnedVersionSpecifier)
				}
			} else {
				// Remove the versions from the set that are not valid according to the versionSpecifier
				constrainVersions(for: dependency, with: versionSpecifier)
			}

			if isRejected {
				// No need to proceed, set is rejected already
				break
			}
		}
	}
}

/**
Version that can be ordered on relevance.

Semantic versions are first, ordered descending, then versions that do not comply with the semantic structure (*.*.*).
*/
struct ConcreteVersion: Comparable, CustomStringConvertible {
	public static let firstPossibleNonSemanticVersion = ConcreteVersion(pinnedVersion: PinnedVersion(""))

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

final class ConcreteVersionSet: Sequence {
	public typealias Element = ConcreteVersion
	public typealias Iterator = ConcreteVersionSetIterator

	private var semanticVersions: SortedSet<ConcreteVersion>
	private var nonSemanticVersions: SortedSet<ConcreteVersion>

	public var pinnedVersionSpecifier: VersionSpecifier?

	public var isPinned: Bool {
		return pinnedVersionSpecifier != nil
	}

	private init(semanticVersions: SortedSet<ConcreteVersion>, nonSemanticVersions: SortedSet<ConcreteVersion>, pinnedVersionSpecifier: VersionSpecifier? = nil) {
		self.semanticVersions = semanticVersions
		self.nonSemanticVersions = nonSemanticVersions
        self.pinnedVersionSpecifier = pinnedVersionSpecifier
	}

	public convenience init() {
		self.init(semanticVersions: SortedSet<ConcreteVersion>(), nonSemanticVersions: SortedSet<ConcreteVersion>())
	}

	public var copy: ConcreteVersionSet {
		return ConcreteVersionSet(semanticVersions: semanticVersions, nonSemanticVersions: nonSemanticVersions, pinnedVersionSpecifier: pinnedVersionSpecifier)
	}

	public var count: Int {
		return semanticVersions.count + nonSemanticVersions.count
	}

	public var isEmpty: Bool {
		return semanticVersions.isEmpty && nonSemanticVersions.isEmpty
	}

	public var first: ConcreteVersion? {
		return self.semanticVersions.first ?? self.nonSemanticVersions.first
	}

	@discardableResult
	public func insert(_ version: ConcreteVersion) -> Bool {
		if version.semanticVersion != nil {
			return semanticVersions.insert(version)
		} else {
			return nonSemanticVersions.insert(version)
		}
	}

	@discardableResult
	public func remove(_ version: ConcreteVersion) -> Bool {
		if version.semanticVersion != nil {
			return semanticVersions.remove(version)
		} else {
			return nonSemanticVersions.remove(version)
		}
	}

	public func removeAll(except version: ConcreteVersion) {
		if version.semanticVersion != nil {
			semanticVersions.removeAll(except: version)
			nonSemanticVersions.removeAll()
		} else {
			semanticVersions.removeAll()
			nonSemanticVersions.removeAll(except: version)
		}
	}

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
}

extension Dictionary {
	/**
	Returns the value for the specified key if it exists, else it will store the default value as created by the closure and will return that value instead.
	
	This method is useful for caches where the first time a value is instantiated it should be stored in the cache for subsequent use.
	
	Compare this to the method [_ key, default: ] which does return a default but doesn't store it in the dictionary.
	*/
	fileprivate mutating func object(for key: Dictionary.Key, byStoringDefault defaultValue: @autoclosure () throws -> Dictionary.Value) rethrows -> Dictionary.Value {
		if let v = self[key] {
			return v
		} else {
			let dv = try defaultValue()
			self[key] = dv
			return dv
		}
	}

	fileprivate func filterMapValues<T>(_ transform: (Dictionary.Value) throws -> T?) rethrows -> [Dictionary.Key: T] {
		var result = [Dictionary.Key: T]()
		for (key, value) in self {
			if let transformedValue = try transform(value) {
				result[key] = transformedValue
			}
		}

		return result
	}
}
