import Foundation
import ReactiveSwift
import ReactiveTask
import Result
import XCDBLD

struct CachedFramework: Codable {
	enum CodingKeys: String, CodingKey {
		case name = "name"
		case hash = "hash"
	}

	let name: String
	let hash: String
}

struct VersionFile: Codable {
	enum CodingKeys: String, CodingKey {
		case commitish = "commitish"
		case macOS = "Mac"
		case iOS = "iOS"
		case watchOS = "watchOS"
		case tvOS = "tvOS"
	}

	let commitish: String

	let macOS: [CachedFramework]?
	let iOS: [CachedFramework]?
	let watchOS: [CachedFramework]?
	let tvOS: [CachedFramework]?

	/// The extension representing a serialized VersionFile.
	static let pathExtension = "version"

	subscript(_ platform: Platform) -> [CachedFramework]? {
		switch platform {
		case .macOS:
			return macOS

		case .iOS:
			return iOS

		case .watchOS:
			return watchOS

		case .tvOS:
			return tvOS
		}
	}

	init(
		commitish: String,
		macOS: [CachedFramework]?,
		iOS: [CachedFramework]?,
		watchOS: [CachedFramework]?,
		tvOS: [CachedFramework]?
	) {
		self.commitish = commitish

		self.macOS = macOS
		self.iOS = iOS
		self.watchOS = watchOS
		self.tvOS = tvOS
	}

	init?(url: URL) {
		guard
			FileManager.default.fileExists(atPath: url.path),
			let jsonData = try? Data(contentsOf: url),
			let versionFile = try? JSONDecoder().decode(VersionFile.self, from: jsonData) else
		{
			return nil
		}
		self = versionFile
	}

	func frameworkURL(
		for cachedFramework: CachedFramework,
		platform: Platform,
		binariesDirectoryURL: URL
	) -> URL {
		return binariesDirectoryURL
			.appendingPathComponent(platform.rawValue, isDirectory: true)
			.resolvingSymlinksInPath()
			.appendingPathComponent("\(cachedFramework.name).framework", isDirectory: true)
	}

	func frameworkBinaryURL(
		for cachedFramework: CachedFramework,
		platform: Platform,
		binariesDirectoryURL: URL
	) -> URL {
		return frameworkURL(
			for: cachedFramework,
			platform: platform,
			binariesDirectoryURL: binariesDirectoryURL
		)
			.appendingPathComponent("\(cachedFramework.name)", isDirectory: false)
	}

	/// Sends the hashes of the provided cached framework's binaries in the
	/// order that they were provided in.
	func hashes(
		for cachedFrameworks: [CachedFramework],
		platform: Platform,
		binariesDirectoryURL: URL
	) -> SignalProducer<String?, CarthageError> {
		return SignalProducer<CachedFramework, CarthageError>(cachedFrameworks)
			.flatMap(.concat) { cachedFramework -> SignalProducer<String?, CarthageError> in
				let frameworkBinaryURL = self.frameworkBinaryURL(
					for: cachedFramework,
					platform: platform,
					binariesDirectoryURL: binariesDirectoryURL
				)

				return hashForFileAtURL(frameworkBinaryURL)
					.map { hash -> String? in
						return hash
					}
					.flatMapError { _ in
						return SignalProducer(value: nil)
					}
			}
	}

	/// Sends values indicating whether the provided cached frameworks match the
	/// given local Swift version, in the order of the provided cached
	/// frameworks.
	///
	/// Non-Swift frameworks are considered as matching the local Swift version,
	/// as they will be compatible with it by definition.
	func swiftVersionMatches(
		for cachedFrameworks: [CachedFramework],
		platform: Platform,
		binariesDirectoryURL: URL,
		localSwiftVersion: String
	) -> SignalProducer<Bool, CarthageError> {
		return SignalProducer<CachedFramework, CarthageError>(cachedFrameworks)
			.flatMap(.concat) { cachedFramework -> SignalProducer<Bool, CarthageError> in
				let frameworkURL = self.frameworkURL(
					for: cachedFramework,
					platform: platform,
					binariesDirectoryURL: binariesDirectoryURL
				)

				if !isSwiftFramework(frameworkURL) {
					return SignalProducer(value: true)
				} else {
					return frameworkSwiftVersion(frameworkURL)
						.map { swiftVersion -> Bool in
							return swiftVersion == localSwiftVersion
						}
						.flatMapError { _ in SignalProducer<Bool, CarthageError>(value: false) }
				}
			}
	}

	func satisfies(
		platform: Platform,
		commitish: String,
		binariesDirectoryURL: URL,
		localSwiftVersion: String
	) -> SignalProducer<Bool, CarthageError> {
		guard let cachedFrameworks = self[platform] else {
			return SignalProducer(value: false)
		}

		let hashes = self.hashes(
			for: cachedFrameworks,
			platform: platform,
			binariesDirectoryURL: binariesDirectoryURL
		)
			.collect()

		let swiftVersionMatches = self
			.swiftVersionMatches(
				for: cachedFrameworks, platform: platform,
				binariesDirectoryURL: binariesDirectoryURL, localSwiftVersion: localSwiftVersion
			)
			.collect()

		return SignalProducer.zip(hashes, swiftVersionMatches)
			.flatMap(.concat) { hashes, swiftVersionMatches -> SignalProducer<Bool, CarthageError> in
				return self.satisfies(
					platform: platform,
					commitish: commitish,
					hashes: hashes,
					swiftVersionMatches: swiftVersionMatches
				)
			}
	}

	func satisfies(
		platform: Platform,
		commitish: String,
		hashes: [String?],
		swiftVersionMatches: [Bool]
	) -> SignalProducer<Bool, CarthageError> {
		guard let cachedFrameworks = self[platform], commitish == self.commitish else {
			return SignalProducer(value: false)
		}

		return SignalProducer
			.zip(
				SignalProducer(hashes),
				SignalProducer(cachedFrameworks),
				SignalProducer(swiftVersionMatches)
			)
			.map { hash, cachedFramework, swiftVersionMatches -> Bool in
				if let hash = hash {
					return hash == cachedFramework.hash && swiftVersionMatches
				} else {
					return false
				}
			}
			.reduce(true) { result, current -> Bool in
				return result && current
			}
	}

	func write(to url: URL) -> Result<(), CarthageError> {
		return Result(at: url, attempt: {
			let encoder = JSONEncoder()
			encoder.outputFormatting = .prettyPrinted

			let jsonData = try encoder.encode(self)
			try FileManager
				.default
				.createDirectory(
					at: $0.deletingLastPathComponent(),
					withIntermediateDirectories: true,
					attributes: nil
			)
			try jsonData.write(to: $0, options: .atomic)
		})
	}
}

/// Creates a version file for the current dependency in the
/// Carthage/Build directory which associates its commitish with
/// the hashes (e.g. SHA256) of the built frameworks for each platform
/// in order to allow those frameworks to be skipped in future builds.
///
/// Returns a signal that succeeds once the file has been created.
public func createVersionFile(
	for dependency: Dependency,
	version: PinnedVersion,
	platforms: Set<Platform>,
	buildProducts: [URL],
	rootDirectoryURL: URL
) -> SignalProducer<(), CarthageError> {
	return createVersionFileForCommitish(
		version.commitish,
		dependencyName: dependency.name,
		platforms: platforms,
		buildProducts: buildProducts,
		rootDirectoryURL: rootDirectoryURL
	)
}

private func createVersionFile(
	_ commitish: String,
	dependencyName: String,
	rootDirectoryURL: URL,
	platformCaches: [String: [CachedFramework]]
) -> SignalProducer<(), CarthageError> {
	return SignalProducer<(), CarthageError> { () -> Result<(), CarthageError> in
		let rootBinariesURL = rootDirectoryURL
			.appendingPathComponent(Constants.binariesFolderPath, isDirectory: true)
			.resolvingSymlinksInPath()
		let versionFileURL = rootBinariesURL
			.appendingPathComponent(".\(dependencyName).\(VersionFile.pathExtension)")

		let versionFile = VersionFile(
			commitish: commitish,
			macOS: platformCaches[Platform.macOS.rawValue],
			iOS: platformCaches[Platform.iOS.rawValue],
			watchOS: platformCaches[Platform.watchOS.rawValue],
			tvOS: platformCaches[Platform.tvOS.rawValue])

		return versionFile.write(to: versionFileURL)
	}
}

/// Creates a version file for the dependency in the given root directory with:
/// - The given commitish
/// - The provided project name
/// - The location of the built frameworks products for all platforms
///
/// Returns a signal that succeeds once the file has been created.
public func createVersionFileForCommitish(
	_ commitish: String,
	dependencyName: String,
	platforms: Set<Platform> = Set(Platform.supportedPlatforms),
	buildProducts: [URL],
	rootDirectoryURL: URL
) -> SignalProducer<(), CarthageError> {
	var platformCaches: [String: [CachedFramework]] = [:]
	
	let platformsToCache = platforms.isEmpty ? Set(Platform.supportedPlatforms) : platforms
	for platform in platformsToCache {
		platformCaches[platform.rawValue] = []
	}
	
	if !buildProducts.isEmpty {
		return SignalProducer<URL, CarthageError>(buildProducts)
			.flatMap(.merge) { url -> SignalProducer<(String, (String, String)), CarthageError> in
				let frameworkName = url.deletingPathExtension().lastPathComponent
				let platformName = url.deletingLastPathComponent().lastPathComponent
				let frameworkURL = url.appendingPathComponent(frameworkName, isDirectory: false)
				let details = SignalProducer<(String, String), CarthageError>(value: (platformName, frameworkName))
				return SignalProducer.zip(hashForFileAtURL(frameworkURL), details)
			}
			.reduce(into: platformCaches) { (platformCaches: inout [String: [CachedFramework]], values: (String, (String, String))) in
				let hash = values.0
				let platformName = values.1.0
				let frameworkName = values.1.1

				let cachedFramework = CachedFramework(name: frameworkName, hash: hash)
				if var frameworks = platformCaches[platformName] {
					frameworks.append(cachedFramework)
					platformCaches[platformName] = frameworks
				}
			}
			.flatMap(.merge) { platformCaches -> SignalProducer<(), CarthageError> in
				createVersionFile(
					commitish,
					dependencyName: dependencyName,
					rootDirectoryURL: rootDirectoryURL,
					platformCaches: platformCaches
				)
			}
	} else {
		// Write out an empty version file for dependencies with no built frameworks, so cache builds can differentiate between
		// no cache and a dependency that has no frameworks
		return createVersionFile(
			commitish,
			dependencyName: dependencyName,
			rootDirectoryURL: rootDirectoryURL,
			platformCaches: platformCaches
		)
	}
}

/// Determines whether a dependency can be skipped because it is
/// already cached.
///
/// If a set of platforms is not provided, all platforms are checked.
///
/// Returns an optional bool which is nil if no version file exists,
/// otherwise true if the version file matches and the build can be
/// skipped or false if there is a mismatch of some kind.
public func versionFileMatches(
	_ dependency: Dependency,
	version: PinnedVersion,
	platforms: Set<Platform>,
	rootDirectoryURL: URL,
	toolchain: String?
) -> SignalProducer<Bool?, CarthageError> {
	let rootBinariesURL = rootDirectoryURL
		.appendingPathComponent(Constants.binariesFolderPath, isDirectory: true)
		.resolvingSymlinksInPath()
	let versionFileURL = rootBinariesURL
		.appendingPathComponent(".\(dependency.name).\(VersionFile.pathExtension)")
	guard let versionFile = VersionFile(url: versionFileURL) else {
		return SignalProducer(value: nil)
	}

	let commitish = version.commitish

	let platformsToCheck = platforms.isEmpty ? Set<Platform>(Platform.supportedPlatforms) : platforms

	return swiftVersion(usingToolchain: toolchain)
		.mapError { error in CarthageError.internalError(description: error.description) }
		.flatMap(.concat) { localSwiftVersion in
			return SignalProducer<Platform, CarthageError>(platformsToCheck)
				.flatMap(.merge) { platform in
					return versionFile.satisfies(
						platform: platform,
						commitish: commitish,
						binariesDirectoryURL: rootBinariesURL,
						localSwiftVersion: localSwiftVersion
					)
				}
				.reduce(true) { $0 && $1 }
				.map { .some($0) }
		}
}

private func hashForFileAtURL(_ frameworkFileURL: URL) -> SignalProducer<String, CarthageError> {
	guard FileManager.default.fileExists(atPath: frameworkFileURL.path) else {
		return SignalProducer(error: .readFailed(frameworkFileURL, nil))
	}

	let task = Task("/usr/bin/shasum", arguments: ["-a", "256", frameworkFileURL.path])

	return task.launch()
		.mapError(CarthageError.taskError)
		.ignoreTaskData()
		.attemptMap { data in
			guard let taskOutput = String(data: data, encoding: .utf8) else {
				return .failure(.readFailed(frameworkFileURL, nil))
			}

			let hashStr = taskOutput.components(separatedBy: CharacterSet.whitespaces)[0]
			return .success(hashStr.trimmingCharacters(in: .whitespacesAndNewlines))
		}
}
