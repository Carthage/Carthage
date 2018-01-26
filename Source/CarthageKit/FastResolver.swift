//
// Created by Werner Altewischer on 24/01/2018.
// Copyright (c) 2018 Carthage. All rights reserved.
//

import Foundation
import Result
import ReactiveSwift

typealias DependencyEntry = (key: Dependency, value: VersionSpecifier)

/// Responsible for resolving acyclic dependency graphs.
public final class FastResolver: ResolverProtocol, DependencyRetriever {

    private let versionsForDependency: (Dependency) -> SignalProducer<PinnedVersion, CarthageError>
    private let resolvedGitReference: (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
    private let dependenciesForDependency: (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>

    private var dependencyCache = [PinnedDependency: [DependencyEntry]]()
    private var versionsCache = [Dependency: SortedSet<ConcreteVersion>]()

    private enum ResolverState {
        case rejected, accepted
    }

    private struct PinnedDependency: Hashable {
        let dependency: Dependency
        let pinnedVersion: PinnedVersion

        public var hashValue: Int {
            return pinnedVersion.hashValue &+ 17 &* dependency.hashValue
        }

        public static func ==(lhs: PinnedDependency, rhs: PinnedDependency) -> Bool {
            return lhs.pinnedVersion == rhs.pinnedVersion && lhs.dependency == rhs.dependency
        }
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
        let dependencySet = DependencySet(requiredDependencies: Set(dependencies.keys), retriever: self)

        do {
            try dependencySet.update(with: AnySequence(dependencies))
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

        return SignalProducer(result: result)
    }

    private func backtrack(dependencySet: DependencySet) throws -> (state: ResolverState, dependencySet: DependencySet) {

        if dependencySet.isRejected {
            return (.rejected, dependencySet)
        } else if dependencySet.isComplete {
            return (.accepted, dependencySet)
        }

        while !dependencySet.isRejected {

            if let subSet = try dependencySet.popSubSet() {

                //Backtrack again with this subset
                let result = try backtrack(dependencySet: subSet)

                switch result.state {
                case .rejected:
                    //Set is rejected, try next possibility
                    break
                case .accepted:
                    //Set contains all dependencies, we've got a winner
                    return (.accepted, result.dependencySet)
                }

            } else {
                //All done
                break
            }
        }

        //Defaults to rejected, no valid set was found
        return (.rejected, dependencySet)
    }

    func findAllVersions(for dependency: Dependency, compatibleWith versionSpecifier: VersionSpecifier) throws -> SortedSet<ConcreteVersion> {
        let concreteVersions: SortedSet<ConcreteVersion>
        if let versions = versionsCache[dependency] {
            concreteVersions = versions
        } else {
            let versionSet = SortedSet<ConcreteVersion>()
            let pinnedVersionsProducer = self.versionsForDependency(dependency)
            let concreteVersionsProducer = pinnedVersionsProducer.filterMap { (pinnedVersion) -> ConcreteVersion? in
                let concreteVersion = ConcreteVersion(pinnedVersion: pinnedVersion)
                versionSet.insertObject(concreteVersion)
                return nil
            }
            _ = concreteVersionsProducer.collect().first()
            versionsCache[dependency] = versionSet
            concreteVersions = versionSet
        }

        let ret = concreteVersions.copy
        ret.retainVersions(compatibleWith: versionSpecifier)
        return ret
    }

    func findDependencies(for dependency: Dependency, version: ConcreteVersion) throws -> [DependencyEntry] {
        let pinnedDependency = PinnedDependency(dependency: dependency, pinnedVersion: version.pinnedVersion)

        if let ret = dependencyCache[pinnedDependency] {
            return ret
        } else {
            let result = self.dependenciesForDependency(dependency, version.pinnedVersion).collect().first()!
            let ret = try result.dematerialize()
            dependencyCache[pinnedDependency] = ret
            return ret
        }
    }
}

protocol DependencyRetriever: class {
    func findAllVersions(for dependency: Dependency, compatibleWith versionSpecifier: VersionSpecifier) throws -> SortedSet<ConcreteVersion>
    func findDependencies(for dependency: Dependency, version: ConcreteVersion) throws -> [DependencyEntry]
}

final class DependencySet {

    private var contents: [Dependency: SortedSet<ConcreteVersion>]

    private weak var retriever: DependencyRetriever!

    public var unresolvedDependencies: Set<Dependency>

    public private(set) var isRejected = false

    public var isComplete: Bool {
        //Dependency resolution is complete if there are no unresolved dependencies anymore
        return unresolvedDependencies.isEmpty
    }

    public var isAccepted: Bool {
        return !self.isRejected && self.isComplete
    }

    public var copy: DependencySet {
        return DependencySet(unresolvedDependencies: self.unresolvedDependencies, contents: contents.mapValues { set -> SortedSet<ConcreteVersion> in return set.copy }, retriever: self.retriever)
    }

    public var resolvedDependencies: [Dependency: PinnedVersion] {
        var ret = [Dependency: PinnedVersion]()
        for (dependency, versionSet) in contents {
            if (versionSet.count > 0) {
                ret[dependency] = versionSet[0].pinnedVersion
            }
        }
        return ret
    }

    private init(unresolvedDependencies: Set<Dependency>, contents: [Dependency: SortedSet<ConcreteVersion>], retriever: DependencyRetriever) {
        self.unresolvedDependencies = unresolvedDependencies
        self.contents = contents
        self.retriever = retriever
    }

    public convenience init(requiredDependencies: Set<Dependency>, retriever: DependencyRetriever) {
        self.init(unresolvedDependencies: requiredDependencies, contents: [Dependency: SortedSet<ConcreteVersion>](), retriever: retriever)
    }

    public func removeVersion(_ version: ConcreteVersion, for dependency: Dependency) -> Bool {
        if let versionSet = contents[dependency] {
            versionSet.removeObject(version)
            if versionSet.isEmpty {
                isRejected = true
            }
            return true
        }
        return false
    }

    public func setVersions(_ versions: SortedSet<ConcreteVersion>, for dependency: Dependency) {
        contents[dependency] = versions
        unresolvedDependencies.insert(dependency)
        if versions.isEmpty {
            isRejected = true
        }
    }

    public func removeAllVersionsExcept(_ version: ConcreteVersion, for dependency: Dependency) {
        if let versionSet = versions(for: dependency) {
            versionSet.removeAllExcept(version)
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

    public func versions(for dependency: Dependency) -> SortedSet<ConcreteVersion>? {
        return contents[dependency]
    }

    public func containsDependency(_ dependency: Dependency) -> Bool {
        return contents[dependency] != nil
    }

    public func popSubSet() throws -> DependencySet? {
        while !unresolvedDependencies.isEmpty {
            if let dependency = unresolvedDependencies.first, let set = contents[dependency], !set.isEmpty {
                let count = set.count
                let version = set[0]
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

                try newSet.update(with: AnySequence(transitiveDependencies))

                return newSet
            }
        }
        return nil
    }

    public func update(with dependencyEntries: AnySequence<DependencyEntry>) throws {
        //Find all versions for current dependencies
        for (dependency, versionSpecifier) in dependencyEntries {
            if !self.containsDependency(dependency) {
                let validVersions = try retriever.findAllVersions(for: dependency, compatibleWith: versionSpecifier)
                self.setVersions(validVersions, for: dependency)
            } else {
                //Remove the versions from the set that are not valid according to the versionSpecifier
                self.constrainVersions(for: dependency, with: versionSpecifier)
            }
            if self.isRejected {
                //No need to proceed, set is rejected already
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

    public static func ==(lhs: ConcreteVersion, rhs: ConcreteVersion) -> Bool {
        if let leftSemanticVersion = lhs.semanticVersion, let rightSemanticVersion = rhs.semanticVersion {
            return leftSemanticVersion == rightSemanticVersion
        }
        return lhs.pinnedVersion == rhs.pinnedVersion
    }

    public static func <(lhs: ConcreteVersion, rhs: ConcreteVersion) -> Bool {
        let leftSemanticVersion = lhs.semanticVersion
        let rightSemanticVersion = rhs.semanticVersion

        if leftSemanticVersion != nil && rightSemanticVersion != nil {
            return leftSemanticVersion! > rightSemanticVersion!
        } else if leftSemanticVersion != nil {
            return true
        } else if rightSemanticVersion != nil {
            return false
        }
        return lhs.pinnedVersion.commitish < rhs.pinnedVersion.commitish
    }

    public var description: String {
        return pinnedVersion.description
    }
}

extension SortedSet where T == ConcreteVersion {

    var semanticVersions: ArraySlice<ConcreteVersion> {
        let index = storage.binarySearch(ConcreteVersion.firstPossibleNonSemanticVersion)
        return slice(at: index, first: true)
    }

    var nonSemanticVersions: ArraySlice<ConcreteVersion> {
        let index = storage.binarySearch(ConcreteVersion.firstPossibleNonSemanticVersion)
        return slice(at: index, first: false)
    }

    private func slice(at index: Int, first: Bool) -> ArraySlice<ConcreteVersion> {
        let insertionIndex: Int
        if (index >= 0) {
            insertionIndex = index
        } else {
            insertionIndex = -(index + 1)
        }

        if first {
            return storage[..<insertionIndex]
        } else {
            return storage[insertionIndex...]
        }
    }

    private func retainSlice(_ slice: ArraySlice<ConcreteVersion>?, includeNonSemantic: Bool = true) {
        var newStorage = [ConcreteVersion]()

        if let definedSlice = slice {
            newStorage.append(contentsOf: definedSlice)
        }

        if includeNonSemantic {
            newStorage.append(contentsOf: nonSemanticVersions)
        }

        storage = newStorage
    }

    func retainVersions(compatibleWith versionSpecifier: VersionSpecifier) {

        //This is an optimization to achieve O(log(N)) time complexity for this method instead of O(N)
        var slice: ArraySlice<ConcreteVersion> = storage[0..<0]

        switch versionSpecifier {
        case .any, .gitReference:
            //Do nothing, always satisfied
            return
        case .exactly(let requirement):
            let index = self.storage.binarySearch(ConcreteVersion(semanticVersion: requirement))
            if (index >= 0) {
                slice = storage[index..<index+1]
            }
        case .atLeast(let requirement):
            let index = self.storage.binarySearch(ConcreteVersion(semanticVersion: requirement))
            let splitIndex: Int

            if index >= 0 {
                splitIndex = index + 1
            } else {
                splitIndex = -(index + 1)
            }

            if splitIndex > 0 {
                slice = storage[..<splitIndex]
            }

        case .compatibleWith(let requirement):

            let lowerBound = ConcreteVersion(semanticVersion: requirement)
            let upperBound = requirement.major > 0 ?
                    ConcreteVersion(semanticVersion: SemanticVersion(major: requirement.major + 1, minor: 0, patch: 0)) :
                    ConcreteVersion(semanticVersion: SemanticVersion(major: 0, minor: requirement.minor + 1, patch: 0))

            var index1 = self.storage.binarySearch(upperBound)
            if index1 < 0 {
                index1 = -(index1 + 1)
            } else {
                index1 += 1
            }

            var index2 = self.storage.binarySearch(lowerBound)

            if index2 >= 0 {
                index2 += 1
            } else {
                index2 = -(index2 + 1)
            }

            if index2 > index1 {
                slice = storage[index1..<index2]
            }
        }

        retainSlice(slice)
    }
}

final class SortedSet<T: Comparable>: Sequence {

    typealias Element = T
    typealias Iterator = Array<Element>.Iterator

    private var storage: [T]

    public var count: Int {
        return storage.count
    }

    public var isEmpty: Bool {
        return storage.isEmpty
    }

    public var copy: SortedSet<T> {
        let ret = SortedSet<T>(storage: self.storage)
        return ret
    }

    private init(storage: [T]) {
        self.storage = storage
    }

    public convenience init() {
        self.init(storage: [T]())
    }

    /**
    Inserts an object at the correct insertion point to keep the set sorted,
    returns true if successful (i.e. the object did not yet exist), false otherwise.
    */
    @discardableResult
    public func insertObject(_ object: T) -> Bool {
        let index = storage.binarySearch(object)

        if (index >= 0) {
            //Element already exists
            return false
        } else {
            let insertionIndex = -(index + 1)
            storage.insert(object, at: insertionIndex)
            return true
        }
    }

    /**
    Removes an object from the set,
    returns true if succesfull (i.e. the set contained the object), false otherwise
    */
    @discardableResult
    public func removeObject(_ object: T) -> Bool {
        let index = storage.binarySearch(object)
        if (index >= 0) {
            storage.remove(at: index)
            return true
        } else {
            return false
        }
    }

    /**
    Checks whether the specified object is contained in this set, returns true if so, false otherwise.
    */
    public func containsObject(_ object: T) -> Bool {
        return storage.binarySearch(object) >= 0
    }

    public func retainObjects(satisfying predicate: (T) -> Bool) {
        var newStorage = [T]()
        for obj in storage {
            if predicate(obj) {
                newStorage.append(obj)
            }
        }
        storage = newStorage
    }

    public func removeAllExcept(_ object: T) {
        let index = storage.binarySearch(object)
        storage.removeAll()
        if index >= 0 {
            storage.append(object)
        }
    }

    /**
    Returns the object at the specified index.
    */
    public subscript(index: Int) -> Element {
        return storage[index]
    }

    public func makeIterator() -> Iterator {
        return storage.makeIterator()
    }
}

extension Array where Element: Comparable {

    func binarySearch(_ element: Element) -> Int {
        var low = 0;
        var high = self.count - 1;

        while (low <= high) {
            let mid = (low + high) >> 1;
            let midVal = self[mid];

            if (midVal < element) {
                low = mid + 1
            } else if (midVal > element) {
                high = mid - 1
            } else {
                return mid
            }
        }
        return -(low + 1);
    }
}

extension Collection {
    public func filterMap<T>(_ transform: (Self.Element) throws -> T?) rethrows -> [T] {
        var ret = [T]()
        for element in self {
            if let newElement = try transform(element) {
                ret.append(newElement)
            }
        }
        return ret
    }
}
