import Foundation
import Result
import ReactiveSwift

/**
 Signals for diagnostic resolver events
 */
public enum DiagnosticResolverEvent {
    case foundVersions(versions: [PinnedVersion], dependency: Dependency, versionSpecifier: VersionSpecifier)
    case foundTransitiveDependencies(transitiveDependencies: [(Dependency, VersionSpecifier)], dependency: Dependency, version: PinnedVersion)
    case failedRetrievingTransitiveDependencies(error: Error, dependency: Dependency, version: PinnedVersion)
    case failedRetrievingVersions(error: Error, dependency: Dependency, versionSpeficier: VersionSpecifier)
}

/**
 Resolver which logs all dependencies it encounters, and optionally stores them in the specified local repository.
 */
public final class DiagnosticResolver: ResolverProtocol {
    private let localRepository: LocalRepository
    private let versionsForDependency: (Dependency) -> SignalProducer<PinnedVersion, CarthageError>
    private let resolvedGitReference: (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
    private let dependenciesForDependency: (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>

    private var versionSets = [Dependency: [PinnedVersion]]()
    private var handledDependencies = Set<PinnedDependency>()

    public var ignoreErrors: Bool = false

    // Specify mappings to anonimize private dependencies (which may not be disclosed as part of the diagnostics)
    public var dependencyMappings: [Dependency: Dependency]?

    public let diagnosticResolverEvents: Signal<DiagnosticResolverEvent, NoError>
    private let diagnosticResolverEventPublisher: Signal<DiagnosticResolverEvent, NoError>.Observer

    private enum DiagnosticResolverError: Error {
        case versionRetrievalFailure(message: String)
        case dependencyRetrievalFailure(message: String)
    }

    public convenience init(versionsForDependency: @escaping (Dependency) -> SignalProducer<PinnedVersion, CarthageError>, dependenciesForDependency: @escaping (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>, resolvedGitReference: @escaping (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>) {
        self.init(versionsForDependency: versionsForDependency,
                  dependenciesForDependency: dependenciesForDependency,
                  resolvedGitReference: resolvedGitReference,
                  localRepository: LocalRepository(directoryURL: URL(fileURLWithPath: "/tmp")))
    }

    public init(
        versionsForDependency: @escaping (Dependency) -> SignalProducer<PinnedVersion, CarthageError>,
        dependenciesForDependency: @escaping (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>,
        resolvedGitReference: @escaping (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>,
        localRepository: LocalRepository) {
        self.versionsForDependency = versionsForDependency
        self.dependenciesForDependency = dependenciesForDependency
        self.resolvedGitReference = resolvedGitReference
        self.localRepository = localRepository

        let (signal, observer) = Signal<DiagnosticResolverEvent, NoError>.pipe()
        diagnosticResolverEvents = signal
        diagnosticResolverEventPublisher = observer
    }

    public func resolve(
        dependencies: [Dependency: VersionSpecifier],
        lastResolved: [Dependency: PinnedVersion]? = nil,
        dependenciesToUpdate: [String]? = nil
        ) -> SignalProducer<[Dependency: PinnedVersion], CarthageError> {
        let result: Result<[Dependency: PinnedVersion], CarthageError>
        do {
            try traverse(dependencies: Array(dependencies))
            result = .success([Dependency: PinnedVersion]())
        } catch let error as CarthageError {
            result = .failure(error)
        } catch {
            result = .failure(CarthageError.internalError(description: error.localizedDescription))
        }
        return SignalProducer(result: result)
    }

    private func traverse(dependencies: [(Dependency, VersionSpecifier)]) throws {
        for (dependency, versionSpecifier) in dependencies {
            let versionSet = try findAllVersions(for: dependency, compatibleWith: versionSpecifier)
            for version in versionSet {
                let pinnedDependency = PinnedDependency(dependency: dependency, pinnedVersion: version)

                if !handledDependencies.contains(pinnedDependency) {
                    handledDependencies.insert(pinnedDependency)

                    let transitiveDependencies = try findDependencies(for: dependency, version: version)
                    try traverse(dependencies: transitiveDependencies)
                }
            }
        }
    }

    private func findAllVersions(for dependency: Dependency, compatibleWith versionSpecifier: VersionSpecifier) throws -> [PinnedVersion] {
        do {
            let versionSet: [PinnedVersion]
            if let cachedVersionSet = versionSets[dependency] {
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
                    throw DiagnosticResolverError.versionRetrievalFailure(message: "Could not collect versions for dependency: \(dependency) and versionSpeficier: \(versionSpecifier)")
                }
                versionSets[dependency] = pinnedVersions

                let storedDependency = self.dependencyMappings?[dependency] ?? dependency
                try localRepository.storePinnedVersions(pinnedVersions, for: storedDependency, gitReference: gitReference)

                versionSet = pinnedVersions
            }

            let filteredVersionSet = versionSet.filter { pinnedVersion -> Bool in
                versionSpecifier.isSatisfied(by: pinnedVersion)
            }

            diagnosticResolverEventPublisher.send(value:
                .foundVersions(versions: filteredVersionSet, dependency: dependency, versionSpecifier: versionSpecifier)
            )

            return filteredVersionSet
        } catch let error {

            diagnosticResolverEventPublisher.send(value:
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
                throw DiagnosticResolverError.dependencyRetrievalFailure(message: "Could not find transitive dependencies for dependency: \(dependency), version: \(version)")
            }

            let storedDependency = self.dependencyMappings?[dependency] ?? dependency
            let storedTransitiveDependencies = transitiveDependencies.map { transitiveDependency, versionSpecifier -> (Dependency, VersionSpecifier) in
                let storedTransitiveDependency = self.dependencyMappings?[transitiveDependency] ?? transitiveDependency
                return (storedTransitiveDependency, versionSpecifier)
            }
            try localRepository.storeTransitiveDependencies(storedTransitiveDependencies, for: storedDependency, version: version)

            diagnosticResolverEventPublisher.send(value:
                .foundTransitiveDependencies(transitiveDependencies: transitiveDependencies, dependency: dependency, version: version)
            )

            return transitiveDependencies
        } catch let error {

            diagnosticResolverEventPublisher.send(value:
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
