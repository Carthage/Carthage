import Foundation
import Result
import ReactiveSwift

/**
Resolver which logs all dependencies it encounters, and optionally stores them in the specified local repository.
*/
final class DiagnosticResolver: ResolverProtocol {
	public var localRepository: LocalRepository?
	private let versionsForDependency: (Dependency) -> SignalProducer<PinnedVersion, CarthageError>
	private let resolvedGitReference: (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
	private let dependenciesForDependency: (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>
	
	private var versionSets = [Dependency: ConcreteVersionSet]()
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
		} catch (let error) {
			let carthageError: CarthageError = (error as? CarthageError) ?? CarthageError.internalError(description: error.localizedDescription)
			result = .failure(carthageError)
		}
		return SignalProducer(result: result)
	}
	
	private func traverse(dependencies: [(Dependency, VersionSpecifier)]) throws {
		for (dependency, versionSpecifier) in dependencies {
			let versionSet = try findAllVersions(for: dependency, compatibleWith: versionSpecifier)
			for version in versionSet {
				let pinnedDependency = PinnedDependency(dependency: dependency, pinnedVersion: version.pinnedVersion)
				
				if !handledDependencies.contains(pinnedDependency) {
					handledDependencies.insert(pinnedDependency)
					
					let transitiveDependencies = try findDependencies(for: dependency, version: version)
					try traverse(dependencies: transitiveDependencies)
				}
			}
		}
	}
	
	private func findAllVersions(for dependency: Dependency, compatibleWith versionSpecifier: VersionSpecifier) throws -> ConcreteVersionSet {
		
		let versionSet: ConcreteVersionSet
		if let cachedVersionSet = versionSets[dependency] {
			versionSet = cachedVersionSet.copy
		} else {
			let cachedVersionSet = ConcreteVersionSet()
			
			let pinnedVersionsProducer: SignalProducer<PinnedVersion, CarthageError>
			var gitReference: String? = nil
			
			switch versionSpecifier {
			case .gitReference(let hash):
				pinnedVersionsProducer = resolvedGitReference(dependency, hash)
				gitReference = hash
			default:
				pinnedVersionsProducer = versionsForDependency(dependency)
			}
			
			let concreteVersionsProducer = pinnedVersionsProducer.filterMap { pinnedVersion -> PinnedVersion? in
				let concreteVersion = ConcreteVersion(pinnedVersion: pinnedVersion)
				cachedVersionSet.insert(concreteVersion)
				return nil
			}
			
			_ = try concreteVersionsProducer.collect().first()!.dematerialize()
			
			versionSets[dependency] = cachedVersionSet
			versionSet = cachedVersionSet.copy
			
			let pinnedVersions: [PinnedVersion] = versionSet.map{ $0.pinnedVersion }
			
			try localRepository?.storePinnedVersions(pinnedVersions, for: dependency, gitReference: gitReference)
		}
		
		versionSet.retainVersions(compatibleWith: versionSpecifier)
		
		print("Versions for dependency '\(dependency.name)' with versionSpecifier \(versionSpecifier): \(versionSet)")
		
		return versionSet
	}
	
	private func findDependencies(for dependency: Dependency, version: ConcreteVersion) throws -> [(Dependency, VersionSpecifier)] {
		let transitiveDependencies:  [(Dependency, VersionSpecifier)] = try dependenciesForDependency(dependency, version.pinnedVersion).collect().first()!.dematerialize()
		
		try localRepository?.storeTransitiveDependencies(transitiveDependencies, for: dependency, version: version.pinnedVersion)
		
		print("Dependencies for dependency '\(dependency.name)' with version \(version): \(transitiveDependencies)")
		return transitiveDependencies
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
