import Foundation
import Result
import ReactiveSwift

/// Responsible for resolving acyclic dependency graphs.
public final class SwiftResolver: ResolverProtocol, PackageContainerProvider, DependencyResolverDelegate {
	
	public typealias Identifier = CarthagePackageIdentifier
	public typealias Container = CarthagePackageContainer
	
	private typealias SwiftDependencyResolver = DependencyResolver<SwiftResolver, SwiftResolver>
	private typealias Constraint = SwiftDependencyResolver.Constraint
	
	private let dependencyFinder: DependencyFinder
	
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
		self.dependencyFinder = DependencyFinder(versionsForDependency: versionsForDependency, dependenciesForDependency: dependenciesForDependency, resolvedGitReference: resolvedGitReference)
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
		
		let swiftDependencyResolver = SwiftDependencyResolver(self, self)
		
		let dependencyConstraints = dependencies.flatMap { (entry) -> Constraint? in
			return Constraint(container: CarthagePackageIdentifier(entry.key), versionRequirement: entry.value.versionSetSpecifier)
		}
		
		let pins = [Constraint]()
		
		let resolverResult: DependencyResolver.ResolverResult = swiftDependencyResolver.resolve(dependencies: dependencyConstraints, pins: pins)
		
		let result: Result<[Dependency: PinnedVersion], CarthageError>
		
		switch resolverResult {
		case .success(let bindings):
			
			var resolvedDict = [Dependency: PinnedVersion]()
			
			for binding in bindings {
				let identifier = binding.container
				let boundVersion = binding.binding
				
				if let pinnedVersion = boundVersion.pinnedVersion {
					resolvedDict[identifier.dependency] = pinnedVersion
				}
			}
			
			result = Result<[Dependency: PinnedVersion], CarthageError>.success(resolvedDict)
			
		case .unsatisfiable(dependencies: let failedDependencies, pins: _):
			
			let carthageError = CarthageError.unsatisfiableDependencyList(failedDependencies.map({ $0.description }))
			result = Result<[Dependency: PinnedVersion], CarthageError>.failure(carthageError)
			
		case .error(let error):
			
			let carthageError = CarthageError.internalError(description: error.localizedDescription)
			
			result = Result<[Dependency: PinnedVersion], CarthageError>.failure(carthageError)
		}
		
		return SignalProducer(result: result)
	}
	
	/// Get the container for a particular identifier asynchronously.
	public func getContainer(
		for identifier: Identifier,
		skipUpdate: Bool,
		completion: @escaping (Result<Container, AnyError>) -> Void
		) {
		
		do {
			let container = try CarthagePackageContainer(identifier: identifier, dependencyFinder: dependencyFinder)
			
			completion(Result<Container, AnyError>.success(container))
			
		} catch let error {
			completion(Result<Container, AnyError>.failure(AnyError(error)))
		}
	}
}

private final class DependencyFinder {
	private let versionsForDependency: (Dependency) -> SignalProducer<PinnedVersion, CarthageError>
	private let resolvedGitReference: (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
	private let dependenciesForDependency: (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>
	
	public init(
		versionsForDependency: @escaping (Dependency) -> SignalProducer<PinnedVersion, CarthageError>,
		dependenciesForDependency: @escaping (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>,
		resolvedGitReference: @escaping (Dependency, String) -> SignalProducer<PinnedVersion, CarthageError>
		) {
		self.versionsForDependency = versionsForDependency
		self.dependenciesForDependency = dependenciesForDependency
		self.resolvedGitReference = resolvedGitReference
	}
	
	public func findAllVersions(for dependency: Dependency, compatibleWith versionSpecifier: VersionSpecifier? = nil) throws -> [PinnedVersion] {
		var versions = self.versionsForDependency(dependency)
		
		if let nonNilVersionSpecifier = versionSpecifier {
			versions = versions.filter { nonNilVersionSpecifier.isSatisfied(by: $0) }
		}
		
		let result = versions.collect().first()!
		return try result.dematerialize()
	}
	
	public func findDependencies(for dependency: Dependency, version: PinnedVersion) throws -> [(Dependency, VersionSpecifier)] {
		let result = self.dependenciesForDependency(dependency, version).collect().first()!
		return try result.dematerialize()
	}
	
}

private extension PackageVersion {
	init(_ semanticVersion: SemanticVersion) {
		self.init(semanticVersion.major, semanticVersion.minor, semanticVersion.patch)
	}
}

private extension VersionSpecifier {
	
	var versionSetSpecifier: VersionSetSpecifier {
		
		switch self {
		case .any:
			return VersionSetSpecifier.any
		case .atLeast(let semanticVersion):
			let minVersion = PackageVersion(semanticVersion)
			let maxVersion = PackageVersion(Int.max, 0, 0)
			return VersionSetSpecifier.range(minVersion ..< maxVersion)
		case .compatibleWith(let semanticVersion):
			let minVersion = PackageVersion(semanticVersion)
			let maxVersion = PackageVersion(semanticVersion.major + 1, 0, 0)
			return VersionSetSpecifier.range(minVersion ..< maxVersion)
		case .exactly(let semanticVersion):
			return VersionSetSpecifier.exact(PackageVersion(semanticVersion.major, semanticVersion.minor, semanticVersion.patch))
		case .gitReference:
			return VersionSetSpecifier.empty
		}
	}
	
}

private extension BoundVersion {
	var pinnedVersion: PinnedVersion? {
		switch self {
		case .excluded:
			return nil
		case .version(let version):
			return PinnedVersion(version.description)
		case .unversioned:
			return nil
		case .revision(let identifier):
			return PinnedVersion(identifier)
		}
	}
}

private extension PinnedVersion {
	var packageVersion: PackageVersion? {
		
		let firstNumberIndex = self.commitish.index(where: {
			switch $0 {
			case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
				return true
			default:
				return false
			}
		})
		
		if let index = firstNumberIndex {
			let stripped = commitish.substring(from: index)
			return PackageVersion(string: stripped)
		}
		return nil
	}
}

private extension PackageVersion {
	var pinnedVersion: PinnedVersion {
		return PinnedVersion(self.description)
	}
}

public struct CarthagePackageIdentifier: PackageContainerIdentifier {
	public let dependency: Dependency
	
	init(_ dependency: Dependency) {
		self.dependency = dependency
	}
	
	public var hashValue: Int {
		return dependency.hashValue
	}
	
	public static func ==(lhs: CarthagePackageIdentifier, rhs: CarthagePackageIdentifier) -> Bool {
		return lhs.dependency == rhs.dependency
	}
}

public final class CarthagePackageContainer: PackageContainer {
	public typealias Identifier = CarthagePackageIdentifier
	
	public let identifier: Identifier
	
	private let dependencyFinder: DependencyFinder
	
	private let versions: [PackageVersion]
	
	fileprivate init(identifier: Identifier, dependencyFinder: DependencyFinder) throws {
		self.identifier = identifier
		self.dependencyFinder = dependencyFinder
		
		let pinnedVersions = try dependencyFinder.findAllVersions(for: identifier.dependency)
		let packageVersions = pinnedVersions.map({ $0.packageVersion! })
		
		self.versions = packageVersions.sorted(by: { (lhs, rhs) -> Bool in
			lhs > rhs
		})
	}
	
	public func versions(filter isIncluded: (PackageVersion) -> Bool) -> AnySequence<PackageVersion> {
		return AnySequence(versions.filter { isIncluded($0) })
	}
	
	public func getDependencies(at version: PackageVersion) throws -> [PackageContainerConstraint<Identifier>] {
		let dependencies = try dependencyFinder.findDependencies(for: identifier.dependency, version: version.pinnedVersion)
		
		return dependencies.map { (pinnedDependency) -> PackageContainerConstraint<Identifier> in
			return PackageContainerConstraint(container: CarthagePackageIdentifier(pinnedDependency.0), versionRequirement: pinnedDependency.1.versionSetSpecifier)
		}
	}
	
	public func getDependencies(at revision: String) throws -> [PackageContainerConstraint<Identifier>] {
		return [PackageContainerConstraint<Identifier>]()
	}
	
	public func getUnversionedDependencies() throws -> [PackageContainerConstraint<Identifier>] {
		return [PackageContainerConstraint<Identifier>]()
	}
	
	public func getUpdatedIdentifier(at boundVersion: BoundVersion) throws -> Identifier {
		return identifier
	}
}
