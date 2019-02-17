import Foundation
import Result
import ReactiveSwift

/**
Signals for diagnostic resolver events
*/
public enum DependencyCrawlerEvent {
	case foundVersions(versions: [PinnedVersion], dependency: Dependency, versionSpecifier: VersionSpecifier)
	case foundTransitiveDependencies(transitiveDependencies: [(Dependency, VersionSpecifier)], dependency: Dependency, version: PinnedVersion)
	case failedRetrievingTransitiveDependencies(error: Error, dependency: Dependency, version: PinnedVersion)
	case failedRetrievingVersions(error: Error, dependency: Dependency, versionSpeficier: VersionSpecifier)
}

/**
Class which logs all dependencies it encounters and stores them in the specified local store to be able to support subsequent offline test cases.
*/
public final class DependencyCrawler {
	private let store: LocalDependencyStore
	private let versionsForDependency: (Dependency) -> SignalProducer<PinnedVersion, CarthageError>
	private let resolvedGitReference: (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
	private let dependenciesForDependency: (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>

	public let ignoreErrors: Bool

	// Specify mappings to anonymize private dependencies (which may not be disclosed as part of the diagnostics)
	private var dependencyMappings: [Dependency: Dependency]?

	public let events: Signal<DependencyCrawlerEvent, NoError>
	private let eventPublisher: Signal<DependencyCrawlerEvent, NoError>.Observer

	private enum DependencyCrawlerError: Error {
		case versionRetrievalFailure(message: String)
		case dependencyRetrievalFailure(message: String)
	}

	public init(
			versionsForDependency: @escaping (Dependency) -> SignalProducer<PinnedVersion, CarthageError>,
			dependenciesForDependency: @escaping (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>,
			resolvedGitReference: @escaping (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>,
			store: LocalDependencyStore,
			mappings: [Dependency: Dependency]? = nil,
			ignoreErrors: Bool = false) {
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

	public func traverse(dependencies: [Dependency: VersionSpecifier]) -> Result<(), CarthageError> {
		let result: Result<(), CarthageError>
		do {
			var handledDependencies = Set<PinnedDependency>()
			var cachedVersionSets = [Dependency: [PinnedVersion]]()
			try traverse(dependencies: Array(dependencies),
						 handledDependencies: &handledDependencies,
						 cachedVersionSets: &cachedVersionSets)
			result = .success(())
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
					throw DependencyCrawlerError.versionRetrievalFailure(message: "Could not collect versions for dependency: \(dependency) and versionSpeficier: \(versionSpecifier)")
				}
				cachedVersionSets[dependency] = pinnedVersions

				let storedDependency = self.dependencyMappings?[dependency] ?? dependency
				try store.storePinnedVersions(pinnedVersions, for: storedDependency, gitReference: gitReference)

				versionSet = pinnedVersions
			}

			let filteredVersionSet = versionSet.filter { pinnedVersion -> Bool in
				versionSpecifier.isSatisfied(by: pinnedVersion)
			}

			eventPublisher.send(value:
				.foundVersions(versions: filteredVersionSet, dependency: dependency, versionSpecifier: versionSpecifier)
			)

			return filteredVersionSet
		} catch let error {

			eventPublisher.send(value:
				.failedRetrievingVersions(error: error, dependency: dependency, versionSpeficier: versionSpecifier)
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
			try store.storeTransitiveDependencies(storedTransitiveDependencies, for: storedDependency, version: version)

			eventPublisher.send(value:
				.foundTransitiveDependencies(transitiveDependencies: transitiveDependencies, dependency: dependency, version: version)
			)

			return transitiveDependencies
		} catch let error {

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

	private struct PinnedDependency: Hashable {
		public let dependency: Dependency
		public let pinnedVersion: PinnedVersion
		private let hash: Int

		init(dependency: Dependency, pinnedVersion: PinnedVersion) {
			self.dependency = dependency
			self.pinnedVersion = pinnedVersion
			self.hash = 37 &* dependency.hashValue &+ pinnedVersion.hashValue
		}

		public var hashValue: Int {
			return hash
		}

		public static func == (lhs: PinnedDependency, rhs: PinnedDependency) -> Bool {
			return lhs.pinnedVersion == rhs.pinnedVersion && lhs.dependency == rhs.dependency
		}
	}
}
