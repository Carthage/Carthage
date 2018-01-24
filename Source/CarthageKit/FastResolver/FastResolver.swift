//
// Created by Werner Altewischer on 24/01/2018.
// Copyright (c) 2018 Carthage. All rights reserved.
//

import Foundation
import Result
import ReactiveSwift

/// Responsible for resolving acyclic dependency graphs.
public struct FastResolver: ResolverProtocol {
    private let versionsForDependency: (Dependency) -> SignalProducer<PinnedVersion, CarthageError>
    private let resolvedGitReference: (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
    private let dependenciesForDependency: (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>

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

        let dependencySet = DependencySet()

        backtrack(dependencies: dependencies, dependencySet: dependencySet)

        return SignalProducer(result: result)
    }

    private func backtrack(dependencies: [Dependency: VersionSpecifier], dependencySet: DependencySet) throws -> Bool {

        for (dependency, versionSpecifier) in dependencies {
            let validVersions = try findAllVersions(for: dependency, compatibleWith: versionSpecifier)
            dependencySet.addVersions(validVersions, for: dependency)
        }



        //Find all versions for current dependencies

        let dependencies: [Dependency]


        if !dependencySet.isValid {
            return false
        }




        if reject(P,c) then return
        if accept(P,c) then output(P,c)
        s ← first(P,c)
        while s ≠ Λ do
        bt(s)
        s ← next(P,s)
    }

    private func findAllVersions(for dependency: Dependency, compatibleWith versionSpecifier: VersionSpecifier? = nil) throws -> [PinnedVersion] {
        var versions = self.versionsForDependency(dependency)

        if let nonNilVersionSpecifier = versionSpecifier {
            versions = versions.filter { nonNilVersionSpecifier.isSatisfied(by: $0) }
        }

        let result = versions.collect().first()!
        return try result.dematerialize()
    }

    private func findDependencies(for dependency: Dependency, version: PinnedVersion) throws -> [(Dependency, VersionSpecifier)] {
        let result = self.dependenciesForDependency(dependency, version).collect().first()!
        return try result.dematerialize()
    }

}

final class DependencySet {

    private var contents = [Dependency: SortedSet<ConcreteVersion>]()
    public private(set) var isValid = true

    public init() {

    }

    public func removeVersion(_ version: PinnedVersion, for dependency: Dependency) {

    }

    public func addVersions(_ versions: [PinnedVersion], for dependency: Dependency) {

    }
}

/**
Version that can be ordered on relevance.

Semantic versions are first, ordered descending, then versions that do not comply with the semantic structure (*.*.*).
*/
final class ConcreteVersion: Comparable, CustomStringConvertible {

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

final class SortedSet<T: Comparable>: Sequence {

    typealias Element = T
    typealias Iterator = Array<Element>.Iterator

    private var storage = [T]()

    public var count: Int {
        return storage.count
    }

    /**
    Inserts an object at the correct insertion point to keep the set sorted,
    returns true if successful (i.e. the object did not yet exist), false otherwise.
    */
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