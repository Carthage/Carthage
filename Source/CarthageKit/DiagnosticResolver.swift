import Foundation
import Result
import ReactiveSwift

/**
Resolver which logs all dependencies it encounters, and optionally stores them in the specified local repository.
*/
final class DiagnosticResolver: ResolverProtocol {
	public var localRepository: LocalRepository?
	public var ignoreErrors: Bool = false
	private let versionsForDependency: (Dependency) -> SignalProducer<PinnedVersion, CarthageError>
	private let resolvedGitReference: (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
	private let dependenciesForDependency: (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>

	private var versionSets = [Dependency: [PinnedVersion]]()
	private var handledDependencies = Set<PinnedDependency>()

	public init(
		versionsForDependency: @escaping (Dependency) -> SignalProducer<PinnedVersion, CarthageError>,
		dependenciesForDependency: @escaping (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>,
		resolvedGitReference: @escaping (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
		) {
		self.versionsForDependency = versionsForDependency
		self.dependenciesForDependency = dependenciesForDependency
		self.resolvedGitReference = resolvedGitReference
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
		} catch let error {
			let carthageError: CarthageError = (error as? CarthageError) ?? CarthageError.internalError(description: error.localizedDescription)
			result = .failure(carthageError)
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
				var pinnedVersions = [PinnedVersion]()
				let pinnedVersionsProducer: SignalProducer<PinnedVersion, CarthageError>
				var gitReference: String?

				switch versionSpecifier {
				case .gitReference(let hash):
					pinnedVersionsProducer = resolvedGitReference(dependency, hash)
					gitReference = hash
				default:
					pinnedVersionsProducer = versionsForDependency(dependency)
				}

				let concreteVersionsProducer = pinnedVersionsProducer.filterMap { pinnedVersion -> PinnedVersion? in
					pinnedVersions.append(pinnedVersion)
					return nil
				}

				_ = try concreteVersionsProducer.collect().first()!.dematerialize()

				versionSets[dependency] = pinnedVersions

				try localRepository?.storePinnedVersions(pinnedVersions, for: dependency, gitReference: gitReference)

				versionSet = pinnedVersions
			}

			print("Versions for dependency '\(dependency)': \(versionSet)")

			return versionSet
		} catch let error {
			print("Caught error while retrieving versions for \(dependency): \(error)")
			if ignoreErrors {
				return [PinnedVersion]()
			} else {
				throw error
			}
		}
	}

	private func findDependencies(for dependency: Dependency, version: PinnedVersion) throws -> [(Dependency, VersionSpecifier)] {
		do {
			let transitiveDependencies: [(Dependency, VersionSpecifier)] = try dependenciesForDependency(dependency, version).collect().first()!.dematerialize()

			try localRepository?.storeTransitiveDependencies(transitiveDependencies, for: dependency, version: version)

			print("Dependencies for dependency '\(dependency)' with version \(version): \(transitiveDependencies)")
			return transitiveDependencies
		} catch let error {
			print("Caught error while retrieving dependencies for \(dependency) at version \(version): \(error)")
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
