//
// Created by Werner Altewischer on 24/01/2018.
// Copyright (c) 2018 Carthage. All rights reserved.
//

import Foundation
import Result
import ReactiveSwift

/// Responsible for resolving acyclic dependency graphs.
public final class FastResolver: ResolverProtocol {

    private typealias DependencyEntry = (key: Dependency, value: VersionSpecifier)

    private let versionsForDependency: (Dependency) -> SignalProducer<PinnedVersion, CarthageError>
    private let resolvedGitReference: (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
    private let dependenciesForDependency: (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>

    private var dependencyCache = [PinnedDependency: [DependencyEntry]]()
    private var versionsCache = [Dependency: SortedSet<ConcreteVersion>]()

    private enum ResolverState {
        case rejected, accepted, incomplete
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
        let result = Result<[Dependency: PinnedVersion], CarthageError>.success([Dependency: PinnedVersion]())

        let dependencySet = DependencySet(requiredDependencies: Set(dependencies.keys))

        do {
            try backtrack(dependencies: AnySequence(dependencies), dependencySet: dependencySet)
        } catch let error {
            print("Caught error: \(error)")
        }

        return SignalProducer(result: result)
    }

    private func backtrack(dependencies: AnySequence<DependencyEntry>, dependencySet: DependencySet) throws -> (ResolverState, DependencySet) {

        //Find all versions for current dependencies
        for (dependency, versionSpecifier) in dependencies {
            if !dependencySet.containsDependency(dependency) {
                let validVersions = try findAllVersions(for: dependency, compatibleWith: versionSpecifier)
                dependencySet.setVersions(validVersions, for: dependency)
            } else {
                //Remove the versions from the set that are not valid according to the versionSpecifier
                dependencySet.constrainVersions(for: dependency, with: versionSpecifier)
            }
        }

        if dependencySet.isRejected {
            return (.rejected, dependencySet)
        } else if dependencySet.isComplete {
            return (.accepted, dependencySet)
        }

        outer:
        while true {
            if var (pinnedDependency, subSet) = dependencySet.popSubSet() {

                inner:
                while true {
                    let transitiveDependencies = try findDependencies(for: pinnedDependency.dependency, version: pinnedDependency.pinnedVersion)

                    let result = try backtrack(dependencies: AnySequence(transitiveDependencies), dependencySet: subSet)

                    switch result.0 {
                    case .rejected:
                        //Set is rejected, cannot narrow further, try next possibility
                        break inner
                    case .accepted:
                        //Set contains all dependencies, we've got a winner
                        return (.accepted, subSet)
                    case .incomplete:
                        //Set is still valid, but should be narrowed down further
                        if let (nextDependency, nextSubSet) = subSet.popSubSet() {
                            pinnedDependency = nextDependency
                            subSet = nextSubSet
                        } else {
                            break inner
                        }
                    }
                }

            } else {
                break outer
            }
        }

        return (.rejected, dependencySet)
    }

    private func findAllVersions(for dependency: Dependency, compatibleWith versionSpecifier: VersionSpecifier) throws -> SortedSet<ConcreteVersion> {
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
        ret.retainObjects(compatibleWith: versionSpecifier)
        return ret
    }

    private func findDependencies(for dependency: Dependency, version: PinnedVersion) throws -> [DependencyEntry] {
        let pinnedDependency = PinnedDependency(dependency: dependency, pinnedVersion: version)

        if let ret = dependencyCache[pinnedDependency] {
            return ret
        } else {
            let result = self.dependenciesForDependency(dependency, version).collect().first()!
            let ret = try result.dematerialize()
            dependencyCache[pinnedDependency] = ret
            return ret
        }
    }

}

private struct PinnedDependency: Hashable {
    let dependency: Dependency
    let pinnedVersion: PinnedVersion

    public var hashValue: Int {
        return pinnedVersion.hashValue &+ 17 * dependency.hashValue
    }

    public static func ==(lhs: PinnedDependency, rhs: PinnedDependency) -> Bool {
        return lhs.pinnedVersion == rhs.pinnedVersion && lhs.dependency == rhs.dependency
    }
}

final class DependencySet {

    private var contents: [Dependency: SortedSet<ConcreteVersion>]

    public var unresolvedDependencies: Set<Dependency>

    public private(set) var isRejected = false

    public var isComplete: Bool {
        //Dependency resolution is complete if there are no unresolved dependencies anymore
        return unresolvedDependencies.isEmpty
    }

    public var isAccepted: Bool {
        return self.isRejected && self.isComplete
    }

    public var copy: DependencySet {
        return DependencySet(unresolvedDependencies: self.unresolvedDependencies, contents: contents.mapValues { set -> SortedSet<ConcreteVersion> in return set.copy })
    }

    public var resolvedDependencies: [(Dependency, ConcreteVersion)] {
        return contents.filterMap { dependency, versionSet -> (Dependency, ConcreteVersion)? in
            if versionSet.isEmpty {
                return nil
            } else {
                return (dependency, versionSet[0])
            }
        }
    }

    private init(unresolvedDependencies: Set<Dependency>, contents: [Dependency: SortedSet<ConcreteVersion>]) {
        self.unresolvedDependencies = unresolvedDependencies
        self.contents = contents
    }

    public convenience init(requiredDependencies: Set<Dependency>) {
        self.init(unresolvedDependencies: requiredDependencies, contents: [Dependency: SortedSet<ConcreteVersion>]())
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
        if versions.isEmpty {
            isRejected = true
        } else {
            unresolvedDependencies.remove(dependency)
        }
    }

    public func removeAllVersionsExcept(_ version: ConcreteVersion, for dependency: Dependency) {
        if let versionSet = versions(for: dependency) {
            versionSet.removeAllExcept(version)
        }
    }

    public func constrainVersions(for dependency: Dependency, with versionSpecifier: VersionSpecifier) {
        if let versionSet = versions(for: dependency) {
            versionSet.retainObjects(compatibleWith: versionSpecifier)
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

    public func popSubSet() -> (PinnedDependency, DependencySet)? {
        //Find first dependency which contains more than 1 version
        for (dependency, set) in contents {
            let count = set.count
            if count > 1 {
                let copy = self.copy
                let version = set[0]
                copy.removeAllVersionsExcept(version, for: dependency)
                removeVersion(version, for: dependency)
                return (PinnedDependency(dependency: dependency, pinnedVersion: version.pinnedVersion), copy)
            } else if count == 0 {
                //Set is depleted for one of the dependencies, cannot pop
                return nil
            }
        }
        return nil
    }
}

/**
Version that can be ordered on relevance.

Semantic versions are first, ordered descending, then versions that do not comply with the semantic structure (*.*.*).
*/
struct ConcreteVersion: Comparable, CustomStringConvertible {

    public let pinnedVersion: PinnedVersion
    public let semanticVersion: SemanticVersion?

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
        return lhs.pinnedVersion.commitish > rhs.pinnedVersion.commitish
    }

    public var description: String {
        return pinnedVersion.description
    }
}

extension SortedSet where T == ConcreteVersion {

    func retainObjects(compatibleWith versionSpecifier: VersionSpecifier) {

        switch versionSpecifier {
        case .any, .gitReference:
            //Do nothing, always satisfied
            return
        default:
            break
        }

        //TODO: can be optimized: O(N) -> O(logN)
        self.retainObjects { concreteVersion in
            return versionSpecifier.isSatisfied(by: concreteVersion.pinnedVersion)
        }
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