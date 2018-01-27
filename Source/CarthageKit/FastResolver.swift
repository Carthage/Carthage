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
    private var versionsCache = [Dependency: ConcreteVersionSet]()

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

    func findAllVersions(for dependency: Dependency, compatibleWith versionSpecifier: VersionSpecifier) throws -> ConcreteVersionSet {
        let concreteVersions: ConcreteVersionSet
        if let versions = versionsCache[dependency] {
            concreteVersions = versions
        } else {
            let versionSet = ConcreteVersionSet()
            let pinnedVersionsProducer = self.versionsForDependency(dependency)
            let concreteVersionsProducer = pinnedVersionsProducer.filterMap { (pinnedVersion) -> ConcreteVersion? in
                let concreteVersion = ConcreteVersion(pinnedVersion: pinnedVersion)
                versionSet.insert(concreteVersion)
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
    func findAllVersions(for dependency: Dependency, compatibleWith versionSpecifier: VersionSpecifier) throws -> ConcreteVersionSet
    func findDependencies(for dependency: Dependency, version: ConcreteVersion) throws -> [DependencyEntry]
}

final class DependencySet {

    private var contents: [Dependency: ConcreteVersionSet]

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
        return DependencySet(unresolvedDependencies: self.unresolvedDependencies, contents: contents.mapValues { set -> ConcreteVersionSet in return set.copy }, retriever: self.retriever)
    }

    public var resolvedDependencies: [Dependency: PinnedVersion] {
        var ret = [Dependency: PinnedVersion]()
        for (dependency, versionSet) in contents {
            if let firstVersion = versionSet.first {
                ret[dependency] = firstVersion.pinnedVersion
            }
        }
        return ret
    }

    private init(unresolvedDependencies: Set<Dependency>, contents: [Dependency: ConcreteVersionSet], retriever: DependencyRetriever) {
        self.unresolvedDependencies = unresolvedDependencies
        self.contents = contents
        self.retriever = retriever
    }

    public convenience init(requiredDependencies: Set<Dependency>, retriever: DependencyRetriever) {
        self.init(unresolvedDependencies: requiredDependencies, contents: [Dependency: ConcreteVersionSet](), retriever: retriever)
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

    public func popSubSet() throws -> DependencySet? {
        while !unresolvedDependencies.isEmpty {
            if let dependency = unresolvedDependencies.first, let set = contents[dependency], let version = set.first {
                let count = set.count
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

    public static func ==(lhs: ConcreteVersion, rhs: ConcreteVersion) -> Bool {
        return compare(lhs: lhs, rhs: rhs) == .orderedSame
    }

    public static func <(lhs: ConcreteVersion, rhs: ConcreteVersion) -> Bool {
        return compare(lhs: lhs, rhs: rhs) == .orderedAscending
    }

    public static func >(lhs: ConcreteVersion, rhs: ConcreteVersion) -> Bool {
        return compare(lhs: lhs, rhs: rhs) == .orderedDescending
    }

    public static func >=(lhs: ConcreteVersion, rhs: ConcreteVersion) -> Bool {
        let comparisonResult = compare(lhs: lhs, rhs: rhs)
        return comparisonResult == .orderedSame || comparisonResult == .orderedDescending
    }

    public static func <=(lhs: ConcreteVersion, rhs: ConcreteVersion) -> Bool {
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

    private let semanticVersions: SortedSet<ConcreteVersion>
    private let nonSemanticVersions: SortedSet<ConcreteVersion>

    private init(semanticVersions: SortedSet<ConcreteVersion>, nonSemanticVersions: SortedSet<ConcreteVersion>) {
        self.semanticVersions = semanticVersions
        self.nonSemanticVersions = nonSemanticVersions
    }

    public convenience init() {
        self.init(semanticVersions: SortedSet<ConcreteVersion>(), nonSemanticVersions: SortedSet<ConcreteVersion>())
    }

    public var copy: ConcreteVersionSet {
        return ConcreteVersionSet(semanticVersions: semanticVersions.copy, nonSemanticVersions: nonSemanticVersions.copy)
    }

    public var count: Int {
        return semanticVersions.count + nonSemanticVersions.count
    }

    public var isEmpty: Bool {
        return count == 0
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

    public func retainVersions(compatibleWith versionSpecifier: VersionSpecifier) {

        //This is an optimization to achieve O(log(N)) time complexity for this method instead of O(N)
        var range: Range<Int>? = nil
        let versions = semanticVersions

        switch versionSpecifier {
        case .any, .gitReference:
            //Do nothing, always satisfied
            return
        case .exactly(let requirement):
            switch versions.search(ConcreteVersion(semanticVersion: requirement)) {
            case .notFound:
                break
            case .found(let i):
                range = (i..<i+1).relative(to: versions)
            }
        case .atLeast(let requirement):
            let splitIndex: Int
            switch versions.search(ConcreteVersion(semanticVersion: requirement)) {
            case .notFound(let i):
                splitIndex = i
            case .found(let i):
                splitIndex = i + 1
            }
            range = (..<splitIndex).relative(to: versions)
        case .compatibleWith(let requirement):

            let lowerBound = ConcreteVersion(semanticVersion: requirement)
            let upperBound = requirement.major > 0 ?
                    ConcreteVersion(semanticVersion: SemanticVersion(major: requirement.major + 1, minor: 0, patch: 0)) :
                    ConcreteVersion(semanticVersion: SemanticVersion(major: 0, minor: requirement.minor + 1, patch: 0))

            let lowerIndex: Int
            let upperIndex: Int

            switch versions.search(upperBound) {
            case .notFound(let i):
                lowerIndex = i
            case .found(let i):
                lowerIndex = i + 1
            }

            switch versions.search(lowerBound) {
            case .notFound(let i):
                upperIndex = i
            case .found(let i):
                upperIndex = i + 1
            }

            if upperIndex > lowerIndex {
                range = (lowerIndex..<upperIndex).relative(to: versions)
            }
        }
        versions.retain(range: range ?? 0..<0)
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

