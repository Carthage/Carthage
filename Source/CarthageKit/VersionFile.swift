import Foundation
import ReactiveSwift
import ReactiveTask
import Result
import XCDBLD

/// A representation of the cached frameworks
public struct CachedFramework: Codable {
	enum CodingKeys: String, CodingKey {
		case name = "name"
		case container = "container"
		case libraryIdentifier = "identifier"
		case hash = "hash"
		case linking = "linking"
		case swiftToolchainVersion = "swiftToolchainVersion"
	}

	/// Name of the framework
	public let name: String
	public let container: String?
	public let libraryIdentifier: String?
	/// Hash of the framework
	public let hash: String
    /// The linking type of the framework. One of `dynamic` or `static`. Defaults to `dynamic`
    public let linking: FrameworkType?
	/// The Swift toolchain version used to build the framework
	public let swiftToolchainVersion: String?
	/// Indicates if the framework is built from swift code
	public var isSwiftFramework: Bool {
		return swiftToolchainVersion != nil
	}

	/// The framework's expected location within a platform directory.
	func location(in buildDirectory: URL, sdk: SDK) -> URL {
		if let container = container, let libraryIdentifier = libraryIdentifier {
			return buildDirectory
				.appendingPathComponent(container)
				.appendingPathComponent(libraryIdentifier)
				.appendingPathComponent("\(name).framework")
		}
		let platformDirectory = buildDirectory.appendingPathComponent(sdk.platformSimulatorlessFromHeuristic)
		switch linking {
		case .some(.static):
			return platformDirectory
				.appendingPathComponent(FrameworkType.staticFolderName)
				.appendingPathComponent("\(name).framework")
		default:
			return platformDirectory.appendingPathComponent("\(name).framework")
		}
	}
}

/// The representation for a version file
public struct VersionFile: Codable {
	enum CodingKeys: String, CodingKey {
		case commitish = "commitish"
		case macOS = "Mac"
		case iOS = "iOS"
		case watchOS = "watchOS"
		case tvOS = "tvOS"
	}

	/// The revision of the dependency (usually a version number)
	public let commitish: String
	/// The macOS cached frameworks
	public let macOS: [CachedFramework]?
	/// The iOS cached frameworks
	public let iOS: [CachedFramework]?
	/// The watchOS cached frameworks
	public let watchOS: [CachedFramework]?
	/// The tvOS cached frameworks
	public let tvOS: [CachedFramework]?

	/// The extension representing a serialized VersionFile.
	static let pathExtension = "version"

	subscript(_ platform: SDK) -> [CachedFramework]? {
		switch platform.platformSimulatorlessFromHeuristic {
		case "Mac":
			return macOS

		case "iOS":
			return iOS

		case "watchOS":
			return watchOS

		case "tvOS":
			return tvOS
			
		default:
			return nil
		}
	}

	/// Initializes a version file from some values
	public init(
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

	/// Initializes a version file from the content of a file
	/// - Parameter url: the path to the file
	public init?(url: URL) {
		guard
			FileManager.default.fileExists(atPath: url.path),
			let jsonData = try? Data(contentsOf: url),
			let versionFile = try? JSONDecoder().decode(VersionFile.self, from: jsonData) else
		{
			return nil
		}
		self = versionFile
	}

	/// Calculates the path of the version file corresponding with a dependency
	/// - Parameters:
	///   - dependency: the dependency
	///   - rootDirectoryURL: the path to the root directory
	public static func url(for dependency: Dependency, rootDirectoryURL: URL) -> URL {
		let rootBinariesURL = rootDirectoryURL
			.appendingPathComponent(Constants.binariesFolderPath, isDirectory: true)
			.resolvingSymlinksInPath()
		return rootBinariesURL
			.appendingPathComponent(".\(dependency.name).\(VersionFile.pathExtension)")
	}

	/// Calculates the path of the framework corresponding with a version file
	/// - Parameters:
	///   - cachedFramework: the cached framework used to calculate the path
	///   - platform: the platform to use
	///   - binariesDirectoryURL: the binaries directory
	public func frameworkURL(
		for cachedFramework: CachedFramework,
		platform: SDK,
		binariesDirectoryURL: URL
	) -> URL {
		return cachedFramework.location(in: binariesDirectoryURL, sdk: platform)
	}

	/// Calculates the path of the binary inside the framework corresponding with a version file
	/// - Parameters:
	///   - cachedFramework: the cached framework used to calculate the path
	///   - platform: the platform to use
	///   - binariesDirectoryURL: the binaries directory
	public func frameworkBinaryURL(
		for cachedFramework: CachedFramework,
		platform: SDK,
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
	public func hashes(
		for cachedFrameworks: [CachedFramework],
		platform: SDK,
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
	public func swiftVersionMatches(
		for cachedFrameworks: [CachedFramework],
		platform: SDK,
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
							return swiftVersion == localSwiftVersion || isModuleStableAPI(localSwiftVersion, swiftVersion, frameworkURL)
						}
						.flatMapError { _ in SignalProducer<Bool, CarthageError>(value: false) }
				}
			}
	}

	/// Check if the version file matches its values with the ones provided
	public func satisfies(
		platform: SDK,
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

	/// Check if the version file matches its values with the ones provided
	public func satisfies(
		platform: SDK,
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

	/// Writes the version file to the provided path
	public func write(to url: URL) -> Result<(), CarthageError> {
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

/// Creates a version file for the current project in the
/// Carthage/Build directory which associates its commitish with
/// the hashes (e.g. SHA256) of the built frameworks for each platform
/// in order to allow those frameworks to be skipped in future builds.
///
/// Derives the current project name from `git remote get-url origin`
///
/// Returns a signal that succeeds once the file has been created.
public func createVersionFileForCurrentProject(
	platforms: Set<SDK>?,
	buildProducts: [URL],
	rootDirectoryURL: URL
) -> SignalProducer<(), CarthageError> {

	/*
	List all remotes known for this repository
	and keep only the "fetch" urls by which the current repository
	would be known for the purpose of fetching anyways.

	Example of well-formed output:

		$ git remote -v
		origin   https://github.com/blender/Carthage.git (fetch)
		origin   https://github.com/blender/Carthage.git (push)
		upstream https://github.com/Carthage/Carthage.git (fetch)
		upstream https://github.com/Carthage/Carthage.git (push)

	Example of ill-formed output where upstream does not have a url:

		$ git remote -v
		origin   https://github.com/blender/Carthage.git (fetch)
		origin   https://github.com/blender/Carthage.git (push)
		upstream
	*/
	let allRemoteURLs = launchGitTask(["remote", "-v"])
		.flatMap(.concat) { $0.linesProducer }
		.map { $0.components(separatedBy: .whitespacesAndNewlines) }
		.filter { $0.count >= 3 && $0.last == "(fetch)" } // Discard ill-formed output as of example
		.map { ($0[0], $0[1]) }
		.collect()

	let currentProjectName = allRemoteURLs
		// Assess the popularity of each remote url
		.map { $0.reduce([String: (popularity: Int, remoteNameAndURL: (name: String, url: String))]()) { remoteURLPopularityMap, remoteNameAndURL in
			let (remoteName, remoteUrl) = remoteNameAndURL
			var remoteURLPopularityMap = remoteURLPopularityMap
			if let existingEntry = remoteURLPopularityMap[remoteName] {
				remoteURLPopularityMap[remoteName] = (existingEntry.popularity + 1, existingEntry.remoteNameAndURL)
			} else {
				remoteURLPopularityMap[remoteName] = (0, (remoteName, remoteUrl))
			}
			return remoteURLPopularityMap
			}
		}
		// Pick "origin" if it exists,
		// otherwise sort remotes by popularity
		// or alphabetically in case of a draw
		.map { (remotePopularityMap: [String: (popularity: Int, remoteNameAndURL: (name: String, url: String))]) -> String in
			guard let origin = remotePopularityMap["origin"] else {
				let urlOfMostPopularRemote = remotePopularityMap.sorted { lhs, rhs in
					if lhs.value.popularity == rhs.value.popularity {
						return lhs.key < rhs.key
					}
					return lhs.value.popularity > rhs.value.popularity
				}
				.first?.value.remoteNameAndURL.url

				// If the reposiroty is not pushed to any remote
				// the list of remotes is empty, so call the current project... "_Current"
				return urlOfMostPopularRemote.flatMap { Dependency.git(GitURL($0)).name } ?? "_Current"
			}

			return Dependency.git(GitURL(origin.remoteNameAndURL.url)).name
		}

	let currentGitTagOrCommitish = launchGitTask(["rev-parse", "HEAD"])
		.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
		.flatMap(.merge) { headCommitish in
			launchGitTask(["describe", "--tags", "--exact-match", headCommitish])
				.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
				.flatMapError { _  in SignalProducer(value: headCommitish) }
		}

	 return SignalProducer.zip(currentProjectName, currentGitTagOrCommitish)
		.flatMap(.merge) { currentProjectNameString, version in
			createVersionFileForCommitish(
				version,
				dependencyName: currentProjectNameString,
				platforms: platforms,
				buildProducts: buildProducts,
				rootDirectoryURL: rootDirectoryURL
		)
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
	platforms: Set<SDK>?,
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

		let knownIn2019YearSDK: (String) -> String = { prefix in
			SDK.knownIn2019YearSDKs
				.first(where: { sdk in sdk.rawValue.hasPrefix(prefix) } )!
				.platformSimulatorlessFromHeuristic
		}

		let sortedFrameworks: ([CachedFramework]?) -> [CachedFramework]? = {
			$0?.sorted { $0.name < $1.name }
		}

		let versionFile = VersionFile(
			commitish: commitish,
			macOS: sortedFrameworks(platformCaches[knownIn2019YearSDK("mac")]),
			iOS: sortedFrameworks(platformCaches[knownIn2019YearSDK("iphoneos")]),
			watchOS: sortedFrameworks(platformCaches[knownIn2019YearSDK("watchos")]),
			tvOS: sortedFrameworks(platformCaches[knownIn2019YearSDK("appletvos")]))

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
	platforms: Set<SDK>? = nil,
	buildProducts: [URL],
	rootDirectoryURL: URL
) -> SignalProducer<(), CarthageError> {
	var platformCaches: [String: [CachedFramework]] = [:]

	let platformsToCache = (platforms ?? SDK.knownIn2019YearSDKs).intersection(SDK.knownIn2019YearSDKs)

	for platform in platformsToCache {
		platformCaches[platform.platformSimulatorlessFromHeuristic] = []
	}

	struct FrameworkDetail {
		let frameworkName: String
		let frameworkLocator: FrameworkLocator
		let frameworkSwiftVersion: String?
	}
	enum FrameworkLocator {
		case xcframework(name: String, libraryIdentifier: String)
		case platformDirectory(name: String, linking: FrameworkType)
	}

	if !buildProducts.isEmpty {
		return SignalProducer<URL, CarthageError>(buildProducts)
			.skipRepeats()
			.flatMap(.merge, { url -> SignalProducer<(URL, URL), CarthageError> in
				return frameworkBundlesInURL(url)
					.map { ($0.bundleURL, url) }
					.flatMapError { _ in .empty }
			})
			.flatMap(.merge) { url, containerURL -> SignalProducer<(String, FrameworkDetail), CarthageError> in
				let frameworkName: String
				let frameworkLocator: FrameworkLocator
				switch (
					url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent,
					url.deletingLastPathComponent().lastPathComponent,
					url.deletingPathExtension().lastPathComponent
				) {
				case (containerURL.lastPathComponent, let libraryIdentifier, let name):
					frameworkName = name
					frameworkLocator = .xcframework(name: containerURL.lastPathComponent, libraryIdentifier: libraryIdentifier)
				case (let platform, FrameworkType.staticFolderName, let name):
					frameworkName = name
					frameworkLocator = .platformDirectory(name: platform, linking: .static)
				case (_, let platform, let name):
					frameworkName = name
					frameworkLocator = .platformDirectory(name: platform, linking: .dynamic)
				}

				return frameworkSwiftVersionIfIsSwiftFramework(url)
					.mapError { swiftVersionError -> CarthageError in .unknownFrameworkSwiftVersion(swiftVersionError.description) }
					.flatMap(.merge) { frameworkSwiftVersion -> SignalProducer<(String, FrameworkDetail), CarthageError> in
						let frameworkDetail = FrameworkDetail(
							frameworkName: frameworkName,
							frameworkLocator: frameworkLocator,
							frameworkSwiftVersion: frameworkSwiftVersion
						)
						let details = SignalProducer<FrameworkDetail, CarthageError>(value: frameworkDetail)
						let binaryURL = url.appendingPathComponent(frameworkName, isDirectory: false)
						return SignalProducer.zip(hashForFileAtURL(binaryURL), details)
				}
			}
			.reduce(into: platformCaches) { (platformCaches: inout [String: [CachedFramework]], values: (String, FrameworkDetail)) in
				let hash = values.0
				let frameworkName = values.1.frameworkName
				let frameworkSwiftVersion = values.1.frameworkSwiftVersion

				let cachedFramework: CachedFramework
				let platformName: String?

				switch values.1.frameworkLocator {
				case .platformDirectory(name: let name, linking: let linking):
					platformName = name
					cachedFramework = CachedFramework(name: frameworkName, container: nil, libraryIdentifier: nil, hash: hash, linking: linking, swiftToolchainVersion: frameworkSwiftVersion)
				case .xcframework(name: let container, libraryIdentifier: let identifier):
					let targetOS = identifier.components(separatedBy: "-")[0]
					platformName = SDK.associatedSetOfKnownIn2023YearSDKs(targetOS).first?.platformSimulatorlessFromHeuristic
					cachedFramework = CachedFramework(name: frameworkName, container: container, libraryIdentifier: identifier, hash: hash, linking: nil, swiftToolchainVersion: frameworkSwiftVersion)
				}
				if let platformName = platformName, var frameworks = platformCaches[platformName] {
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
	platforms: Set<SDK>?,
	rootDirectoryURL: URL,
	toolchain: String?
) -> SignalProducer<Bool?, CarthageError> {
	let versionFileURL = VersionFile.url(for: dependency, rootDirectoryURL: rootDirectoryURL)
	guard let versionFile = VersionFile(url: versionFileURL) else {
		return SignalProducer(value: nil)
	}

	let commitish = version.commitish

	let platformsToCheck = (platforms ?? SDK.knownIn2019YearSDKs).intersection(SDK.knownIn2019YearSDKs)

	let rootBinariesURL = rootDirectoryURL
		.appendingPathComponent(Constants.binariesFolderPath, isDirectory: true)
		.resolvingSymlinksInPath()

	return swiftVersion(usingToolchain: toolchain)
		.mapError { error in CarthageError.internalError(description: error.description) }
		.flatMap(.concat) { localSwiftVersion in
			return SignalProducer<SDK, CarthageError>(platformsToCheck)
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
