import Foundation
import Result
import ReactiveSwift

/// DependencyCrawler events
public enum DependencyCrawlerEvent {
	case foundVersions(versions: [PinnedVersion], dependency: Dependency, versionSpecifier: VersionSpecifier)
	case foundTransitiveDependencies(transitiveDependencies: [(Dependency, VersionSpecifier)], dependency: Dependency, version: PinnedVersion)
	case failedRetrievingTransitiveDependencies(error: CarthageError, dependency: Dependency, version: PinnedVersion)
	case failedRetrievingVersions(error: CarthageError, dependency: Dependency, versionSpecifier: VersionSpecifier)
}

/// Class which logs all dependencies it encounters and stores them in the specified local store to be able to support subsequent offline test cases.
public final class DependencyCrawler {
	private let store: LocalDependencyStore
	private let versionsForDependency: (Dependency) -> SignalProducer<PinnedVersion, CarthageError>
	private let resolvedGitReference: (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
	private let dependenciesForDependency: (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>
	private let ignoreErrors: Bool

	/// Specify mappings to anonymize private dependencies (which may not be disclosed as part of the diagnostics)
	private var dependencyMappings: [Dependency: Dependency]?
	private let eventPublisher: Signal<DependencyCrawlerEvent, NoError>.Observer

	/// DependencyCrawler events signal
	public let events: Signal<DependencyCrawlerEvent, NoError>

	private enum DependencyCrawlerError: Error {
		case versionRetrievalFailure(message: String)
		case dependencyRetrievalFailure(message: String)
	}

	/// Initializes with implementations for retrieving the versions, transitive dependencies and git references.
	///
	/// Uses the supplied local dependency store to store the encountered dependencies.
	///
	/// Optional mappings may be specified to anonymize the encountered dependencies (thereby removing sensitive information).
	///
	/// If ignoreErrors is true, any error during retrieval of the dependencies will not be fatal but will result in an empty array instead.
	public init(
		versionsForDependency: @escaping (Dependency) -> SignalProducer<PinnedVersion, CarthageError>,
		dependenciesForDependency: @escaping (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>,
		resolvedGitReference: @escaping (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>,
		store: LocalDependencyStore,
		mappings: [Dependency: Dependency]? = nil,
		ignoreErrors: Bool = false
		) {
		self.versionsForDependency = versionsForDependency
		self.dependenciesForDependency = dependenciesForDependency
		self.resolvedGitReference = resolvedGitReference
		self.store = store
		self.dependencyMappings = mappings
		self.ignoreErrors = ignoreErrors

		let (signal, observer) = Signal<DependencyCrawlerEvent, NoError>.pipe()
		events = signal
		eventPublisher = observer
	}

	/// Recursively traverses the supplied dependencies taking into account their compatibleWith version specifiers.
	///
	/// Stores all dependencies in the LocalDependencyStore.
	///
	/// Returns a dictionary of all encountered dependencies with as value a set of all their encountered versions.
	public func traverse(dependencies: [Dependency: VersionSpecifier]) -> Result<[Dependency: Set<PinnedVersion>], CarthageError> {
		let result: Result<[Dependency: Set<PinnedVersion>], CarthageError>
		do {
			var handledDependencies = Set<PinnedDependency>()
			var cachedVersionSets = [Dependency: [PinnedVersion]]()
			try traverse(dependencies: Array(dependencies),
						 handledDependencies: &handledDependencies,
						 cachedVersionSets: &cachedVersionSets)
			result = .success(handledDependencies.dictionaryRepresentation)
		} catch let error as CarthageError {
			result = .failure(error)
		} catch {
			result = .failure(CarthageError.internalError(description: error.localizedDescription))
		}
		return result
	}

	private func traverse(dependencies: [(Dependency, VersionSpecifier)],
						  handledDependencies: inout Set<PinnedDependency>,
						  cachedVersionSets: inout [Dependency: [PinnedVersion]]) throws {
		for (dependency, versionSpecifier) in dependencies {
			let versionSet = try findAllVersions(for: dependency,
												 compatibleWith: versionSpecifier,
												 cachedVersionSets: &cachedVersionSets)
			for version in versionSet {
				let pinnedDependency = PinnedDependency(dependency: dependency, pinnedVersion: version)

				if !handledDependencies.contains(pinnedDependency) {
					handledDependencies.insert(pinnedDependency)

					let transitiveDependencies = try findDependencies(for: dependency, version: version)
					try traverse(dependencies: transitiveDependencies,
								 handledDependencies: &handledDependencies,
								 cachedVersionSets: &cachedVersionSets)
				}
			}
		}
	}

	private func findAllVersions(for dependency: Dependency,
								 compatibleWith versionSpecifier: VersionSpecifier,
								 cachedVersionSets: inout [Dependency: [PinnedVersion]]) throws -> [PinnedVersion] {
		do {
			let versionSet: [PinnedVersion]
			if let cachedVersionSet = cachedVersionSets[dependency] {
				versionSet = cachedVersionSet
			} else {
				let pinnedVersionsProducer: SignalProducer<PinnedVersion, CarthageError>
				var gitReference: String?

				switch versionSpecifier {
				case .gitReference(let hash):
					pinnedVersionsProducer = resolvedGitReference(dependency, hash)
					gitReference = hash
				default:
					pinnedVersionsProducer = versionsForDependency(dependency)
				}

				guard let pinnedVersions: [PinnedVersion] = try pinnedVersionsProducer.collect().first()?.dematerialize() else {
					throw DependencyCrawlerError.versionRetrievalFailure(message: "Could not collect versions for dependency: \(dependency) and versionSpecifier: \(versionSpecifier)")
				}
				cachedVersionSets[dependency] = pinnedVersions

				let storedDependency = self.dependencyMappings?[dependency] ?? dependency
				try store.storePinnedVersions(pinnedVersions, for: storedDependency, gitReference: gitReference).dematerialize()

				versionSet = pinnedVersions
			}

			let filteredVersionSet = versionSet.filter { pinnedVersion -> Bool in
				versionSpecifier.isSatisfied(by: pinnedVersion)
			}

			eventPublisher.send(value:
				.foundVersions(versions: filteredVersionSet, dependency: dependency, versionSpecifier: versionSpecifier)
			)

			return filteredVersionSet
		} catch let error as CarthageError {

			eventPublisher.send(value:
				.failedRetrievingVersions(error: error, dependency: dependency, versionSpecifier: versionSpecifier)
			)

			if ignoreErrors {
				return [PinnedVersion]()
			} else {
				throw error
			}
		}
	}

	private func findDependencies(for dependency: Dependency, version: PinnedVersion) throws -> [(Dependency, VersionSpecifier)] {
		do {
			guard let transitiveDependencies: [(Dependency, VersionSpecifier)] = try dependenciesForDependency(dependency, version).collect().first()?.dematerialize() else {
				throw DependencyCrawlerError.dependencyRetrievalFailure(message: "Could not find transitive dependencies for dependency: \(dependency), version: \(version)")
			}

			let storedDependency = self.dependencyMappings?[dependency] ?? dependency
			let storedTransitiveDependencies = transitiveDependencies.map { transitiveDependency, versionSpecifier -> (Dependency, VersionSpecifier) in
				let storedTransitiveDependency = self.dependencyMappings?[transitiveDependency] ?? transitiveDependency
				return (storedTransitiveDependency, versionSpecifier)
			}
			try store.storeTransitiveDependencies(storedTransitiveDependencies, for: storedDependency, version: version).dematerialize()

			eventPublisher.send(value:
				.foundTransitiveDependencies(transitiveDependencies: transitiveDependencies, dependency: dependency, version: version)
			)

			return transitiveDependencies
		} catch let error as CarthageError {

			eventPublisher.send(value:
				.failedRetrievingTransitiveDependencies(error: error, dependency: dependency, version: version)
			)

			if ignoreErrors {
				return [(Dependency, VersionSpecifier)]()
			} else {
				throw error
			}
		}
	}
}

private struct PinnedDependency: Hashable {
	public let dependency: Dependency
	public let pinnedVersion: PinnedVersion
	
	init(dependency: Dependency, pinnedVersion: PinnedVersion) {
		self.dependency = dependency
		self.pinnedVersion = pinnedVersion
	}
}

extension Sequence where Element == PinnedDependency {
	fileprivate var dictionaryRepresentation: [Dependency: Set<PinnedVersion>] {
		return self.reduce(into: [Dependency: Set<PinnedVersion>]()) { dict, pinnedDependency in
			var set = dict[pinnedDependency.dependency, default: Set<PinnedVersion>()]
			set.insert(pinnedDependency.pinnedVersion)
			dict[pinnedDependency.dependency] = set
		}
	}
}
