import Foundation
import Tentacle
import Result
import ReactiveSwift

/// Local store for storing/loading dependencies and their versions.
/// This is for testing without requiring live connection to real repositories.
public final class LocalDependencyStore {
	private let directoryURL: URL

	/// Initializes with the URL to the directory containing the JSON files with the dependency information
	public init(directoryURL: URL) {
		self.directoryURL = directoryURL
	}

	/// Loads the pinned version for the specified dependency and optional git reference
	public func loadPinnedVersions(for dependency: Dependency, gitReference: String? = nil) -> Result<[PinnedVersion], CarthageError> {
		let fileURL = canonicalPinnedVersionFileURL(for: dependency, gitReference: gitReference)
		do {
			let data = try Data(contentsOf: fileURL)
			let pinnedVersions = try JSONDecoder().decode([PinnedVersion].self, from: data)
			return Result.success(pinnedVersions)
		} catch let error as NSError {
			return Result.failure(CarthageError.readFailed(fileURL, error))
		} catch {
			return Result.failure(CarthageError.internalError(description: error.localizedDescription))
		}
	}

	/// Loads transitive dependencies for the specified dependency and version
	public func loadTransitiveDependencies(for dependency: Dependency, version: PinnedVersion) -> Result<[(Dependency, VersionSpecifier)], CarthageError> {
		let fileURL = transitiveDependenciesURL(for: dependency, version: version)
		do {
			let data = try Data(contentsOf: fileURL)
			let versionSpecs = try JSONDecoder().decode([DependencyVersionSpecification].self, from: data)
			let versionedDependencies = versionSpecs.map { ($0.dependency, $0.versionSpecifier) }
			return Result.success(versionedDependencies)
		} catch let error as NSError {
			return Result.failure(CarthageError.readFailed(fileURL, error))
		} catch {
			return Result.failure(CarthageError.internalError(description: error.localizedDescription))
		}
	}

	private func canonicalPinnedVersionFileURL(for dependency: Dependency, gitReference: String? = nil) -> URL {
		let fileName = (gitReference.map { "\($0).json" } ?? "default.json")
		let fileURL = directoryURL.appendingPathComponent("versions").appendingPathComponent(dependency.name).appendingPathComponent(fileName)
		return fileURL
	}

	private func transitiveDependenciesURL(for dependency: Dependency, version: PinnedVersion) -> URL {
		let fileName = "\(version.commitish).json"
		let fileURL = directoryURL.appendingPathComponent("dependencies").appendingPathComponent(dependency.name).appendingPathComponent(fileName)
		return fileURL
	}

	/// Stores the specified pinned versions for the specified dependency and optional git reference to disk.
	public func storePinnedVersions(_ pinnedVersions: [PinnedVersion], for dependency: Dependency, gitReference: String? = nil) -> Result<(), CarthageError> {
		let fileURL = canonicalPinnedVersionFileURL(for: dependency, gitReference: gitReference)

		do {
			//Ensure the directory exists:
			try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

			let encoder = JSONEncoder()
			encoder.outputFormatting = .prettyPrinted

			let jsonData = try encoder.encode(pinnedVersions)

			try jsonData.write(to: fileURL, options: [])

			return Result.success(())
		} catch let error as NSError {
			return Result.failure(CarthageError.writeFailed(fileURL, error))
		} catch {
			return Result.failure(CarthageError.internalError(description: error.localizedDescription))
		}
	}

	/// Stores the specified transitive dependencies for the specified dependency and version to disk.
	public func storeTransitiveDependencies(_ transitiveDependencies: [(Dependency, VersionSpecifier)], for dependency: Dependency, version: PinnedVersion) -> Result<(), CarthageError> {
		let fileURL = transitiveDependenciesURL(for: dependency, version: version)

		do {
			//Ensure the directory exits:
			try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

			let specs = transitiveDependencies.map { dependencyEntry -> DependencyVersionSpecification in
				DependencyVersionSpecification(dependency: dependencyEntry.0, versionSpecifier: dependencyEntry.1)
			}

			let encoder = JSONEncoder()
			encoder.outputFormatting = .prettyPrinted

			let jsonData = try encoder.encode(specs)

			try jsonData.write(to: fileURL)
			return Result.success(())
		} catch let error as NSError {
			return Result.failure(CarthageError.writeFailed(fileURL, error))
		} catch {
			return Result.failure(CarthageError.internalError(description: error.localizedDescription))
		}
	}

	/// Implementation of method needed by the Resolver protocol
	public func versions(for dependency: Dependency) -> SignalProducer<PinnedVersion, CarthageError> {
		return SignalProducer<[PinnedVersion], CarthageError> { () -> Result<[PinnedVersion], CarthageError> in
			return self.loadPinnedVersions(for: dependency)
			}.flatten()
	}

	/// Implementation of method needed by the Resolver protocol
	public func resolvedGitReference(_ dependency: Dependency, reference: String) -> SignalProducer<PinnedVersion, CarthageError> {
		return SignalProducer<[PinnedVersion], CarthageError> { () -> Result<[PinnedVersion], CarthageError> in
			return self.loadPinnedVersions(for: dependency, gitReference: reference)
			}.flatten()
	}

	/// Implementation of method needed by the Resolver protocol
	public func dependencies(for dependency: Dependency, version: PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError> {
		return SignalProducer<[(Dependency, VersionSpecifier)], CarthageError> { () -> Result<[(Dependency, VersionSpecifier)], CarthageError> in
			return self.loadTransitiveDependencies(for: dependency, version: version)
			}.flatten()
	}
}

struct DependencyVersionSpecification: Codable {
	let dependency: Dependency
	let versionSpecifier: VersionSpecifier
}

extension PinnedVersion: Codable {
	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(self.commitish)
	}

	public init(from decoder: Decoder) throws {
		let commitish = try decoder.singleValueContainer().decode(String.self)
		self = PinnedVersion(commitish)
	}
}

extension Server {
	static func fromURL(_ url: URL?) -> Server {
		if let definedUrl = url {
			return Server.enterprise(url: definedUrl)
		} else {
			return Server.dotCom
		}
	}
}

extension Dependency: Codable {
	private enum CodingKeys: String, CodingKey {
		case gitHub
		case git
		case binary
	}

	private struct GitHub: Codable {
		let serverUrl: URL?
		let repositoryOwner: String
		let repositoryName: String

		init(server: Server, repository: Repository) {
			self.serverUrl = (server == .dotCom ? nil : server.url)
			self.repositoryName = repository.name
			self.repositoryOwner = repository.owner
		}

		var dependency: Dependency {
			return Dependency.gitHub(Server.fromURL(serverUrl), Repository(owner: repositoryOwner, name: repositoryName))
		}
	}

	private struct Git: Codable {
		let urlString: String

		init(gitURL: GitURL) {
			self.urlString = gitURL.urlString
		}

		var dependency: Dependency {
			return Dependency.git(GitURL(urlString))
		}
	}

	private struct Binary: Codable {
		let url: URL
		let resolvedDescription: String

		init(binaryURL: BinaryURL) {
			self.url = binaryURL.url
			self.resolvedDescription = binaryURL.resolvedDescription
		}

		var dependency: Dependency {
			return Dependency.binary(BinaryURL(url: url, resolvedDescription: resolvedDescription))
		}
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		switch self {
		/// A repository hosted on GitHub.com or GitHub Enterprise.
		case .gitHub(let server, let repository):
			try container.encode(GitHub(server: server, repository: repository), forKey: .gitHub)
		/// An arbitrary Git repository.
		case .git(let gitURL):
			try container.encode(Git(gitURL: gitURL), forKey: .git)
		/// A binary-only framework
		case .binary(let binaryURL):
			try container.encode(Binary(binaryURL: binaryURL), forKey: .binary)
		}
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		if let gitHub = try? container.decode(GitHub.self, forKey: .gitHub) {
			self = gitHub.dependency
		} else if let git = try? container.decode(Git.self, forKey: .git) {
			self = git.dependency
		} else if let binary = try? container.decode(Binary.self, forKey: .binary) {
			self = binary.dependency
		} else {
			throw DecodingError.dataCorrupted(
				DecodingError.Context(codingPath: [CodingKeys.git, CodingKeys.gitHub, CodingKeys.binary],
									  debugDescription: "None of the keys .git, .gitHub or .binary found")
			)
		}
	}
}

extension VersionSpecifier: Codable {
	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(self.description)
	}

	public init(from decoder: Decoder) throws {
		let description = try decoder.singleValueContainer().decode(String.self)
		let result = VersionSpecifier.from(Scanner(string: description))
		switch result {
		case .success(let versionSpecifier):
			self = versionSpecifier
		case .failure(let error):
			throw error
		}
	}
}
