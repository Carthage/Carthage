// swiftlint:disable file_length

import Foundation
import Result
import ReactiveSwift
import Tentacle
import XCDBLD
import ReactiveTask

/// Describes an event occurring to or with a project.
public enum ProjectEvent {
	/// The project is beginning to clone.
	case cloning(Dependency)

	/// The project is beginning a fetch.
	case fetching(Dependency)

	/// The project is being checked out to the specified revision.
	case checkingOut(Dependency, String)

	/// The project is downloading a binary-only framework definition.
	case downloadingBinaryFrameworkDefinition(Dependency, URL)

	/// Any available binaries for the specified release of the project are
	/// being downloaded. This may still be followed by `CheckingOut` event if
	/// there weren't any viable binaries after all.
	case downloadingBinaries(Dependency, String)

	/// Downloading any available binaries of the project is being skipped,
	/// because of a GitHub API request failure which is due to authentication
	/// or rate-limiting.
	case skippedDownloadingBinaries(Dependency, String)

	/// Installing of a binary framework is being skipped because of an inability
	/// to verify that it was built with a compatible Swift version.
	case skippedInstallingBinaries(dependency: Dependency, error: Error)

	/// Building the project is being skipped, since the project is not sharing
	/// any framework schemes.
	case skippedBuilding(Dependency, String)

	/// Building the project is being skipped because it is cached.
	case skippedBuildingCached(Dependency)

	/// Rebuilding a cached project because of a version file/framework mismatch.
	case rebuildingCached(Dependency)

	/// Building an uncached project.
	case buildingUncached(Dependency)
}

extension ProjectEvent: Equatable {
	public static func == (lhs: ProjectEvent, rhs: ProjectEvent) -> Bool {
		switch (lhs, rhs) {
		case let (.cloning(left), .cloning(right)):
			return left == right

		case let (.fetching(left), .fetching(right)):
			return left == right

		case let (.checkingOut(leftIdentifier, leftRevision), .checkingOut(rightIdentifier, rightRevision)):
			return leftIdentifier == rightIdentifier && leftRevision == rightRevision

		case let (.downloadingBinaryFrameworkDefinition(leftIdentifier, leftURL), .downloadingBinaryFrameworkDefinition(rightIdentifier, rightURL)):
			return leftIdentifier == rightIdentifier && leftURL == rightURL

		case let (.downloadingBinaries(leftIdentifier, leftRevision), .downloadingBinaries(rightIdentifier, rightRevision)):
			return leftIdentifier == rightIdentifier && leftRevision == rightRevision

		case let (.skippedDownloadingBinaries(leftIdentifier, leftRevision), .skippedDownloadingBinaries(rightIdentifier, rightRevision)):
			return leftIdentifier == rightIdentifier && leftRevision == rightRevision

		case let (.skippedBuilding(leftIdentifier, leftRevision), .skippedBuilding(rightIdentifier, rightRevision)):
			return leftIdentifier == rightIdentifier && leftRevision == rightRevision

		default:
			return false
		}
	}
}

/// Represents a project that is using Carthage.
public final class Project { // swiftlint:disable:this type_body_length
	/// File URL to the root directory of the project.
	public let directoryURL: URL

	/// The file URL to the project's Cartfile.
	public var cartfileURL: URL {
		return directoryURL.appendingPathComponent(Constants.Project.cartfilePath, isDirectory: false)
	}

	/// The file URL to the project's Cartfile.resolved.
	public var resolvedCartfileURL: URL {
		return directoryURL.appendingPathComponent(Constants.Project.resolvedCartfilePath, isDirectory: false)
	}

	/// Whether to prefer HTTPS for cloning (vs. SSH).
	public var preferHTTPS = true

	/// Whether to use submodules for dependencies, or just check out their
	/// working directories.
	public var useSubmodules = false

	/// Whether to download binaries for dependencies, or just check out their
	/// repositories.
	public var useBinaries = false

	/// Sends each event that occurs to a project underneath the receiver (or
	/// the receiver itself).
	public let projectEvents: Signal<ProjectEvent, NoError>
	private let _projectEventsObserver: Signal<ProjectEvent, NoError>.Observer

	public init(directoryURL: URL) {
		precondition(directoryURL.isFileURL)

		let (signal, observer) = Signal<ProjectEvent, NoError>.pipe()
		projectEvents = signal
		_projectEventsObserver = observer

		self.directoryURL = directoryURL
	}

	private typealias CachedVersions = [Dependency: [PinnedVersion]]
	private typealias CachedBinaryProjects = [URL: BinaryProject]

	/// Caches versions to avoid expensive lookups, and unnecessary
	/// fetching/cloning.
	private var cachedVersions: CachedVersions = [:]
	private let cachedVersionsQueue = SerialProducerQueue(name: "org.carthage.Constants.Project.cachedVersionsQueue")

	// Cache the binary project definitions in memory to avoid redownloading during carthage operation
	private var cachedBinaryProjects: CachedBinaryProjects = [:]
	private let cachedBinaryProjectsQueue = SerialProducerQueue(name: "org.carthage.Constants.Project.cachedBinaryProjectsQueue")

	private lazy var xcodeVersionDirectory: String = XcodeVersion.make()
		.map { "\($0.version)_\($0.buildVersion)" } ?? "Unknown"

	/// Attempts to load Cartfile or Cartfile.private from the given directory,
	/// merging their dependencies.
	public func loadCombinedCartfile() -> SignalProducer<Cartfile, CarthageError> {
		let cartfileURL = directoryURL.appendingPathComponent(Constants.Project.cartfilePath, isDirectory: false)
		let privateCartfileURL = directoryURL.appendingPathComponent(Constants.Project.privateCartfilePath, isDirectory: false)

		func isNoSuchFileError(_ error: CarthageError) -> Bool {
			switch error {
			case let .readFailed(_, underlyingError):
				if let underlyingError = underlyingError {
					return underlyingError.domain == NSCocoaErrorDomain && underlyingError.code == NSFileReadNoSuchFileError
				} else {
					return false
				}

			default:
				return false
			}
		}

		let cartfile = SignalProducer { Cartfile.from(file: cartfileURL) }
			.flatMapError { error -> SignalProducer<Cartfile, CarthageError> in
				if isNoSuchFileError(error) && FileManager.default.fileExists(atPath: privateCartfileURL.path) {
					return SignalProducer(value: Cartfile())
				}

				return SignalProducer(error: error)
			}

		let privateCartfile = SignalProducer { Cartfile.from(file: privateCartfileURL) }
			.flatMapError { error -> SignalProducer<Cartfile, CarthageError> in
				if isNoSuchFileError(error) {
					return SignalProducer(value: Cartfile())
				}

				return SignalProducer(error: error)
			}

		return SignalProducer.zip(cartfile, privateCartfile)
			.attemptMap { cartfile, privateCartfile -> Result<Cartfile, CarthageError> in
				var cartfile = cartfile

				let duplicateDeps = duplicateDependenciesIn(cartfile, privateCartfile).map { dependency in
					return DuplicateDependency(
						dependency: dependency,
						locations: ["\(Constants.Project.cartfilePath)", "\(Constants.Project.privateCartfilePath)"]
					)
				}

				if duplicateDeps.isEmpty {
					cartfile.append(privateCartfile)
					return .success(cartfile)
				}

				return .failure(.duplicateDependencies(duplicateDeps))
			}
	}

	/// Reads the project's Cartfile.resolved.
	public func loadResolvedCartfile() -> SignalProducer<ResolvedCartfile, CarthageError> {
		return SignalProducer {
			Result(attempt: { try String(contentsOf: self.resolvedCartfileURL, encoding: .utf8) })
				.mapError { .readFailed(self.resolvedCartfileURL, $0) }
				.flatMap(ResolvedCartfile.from)
		}
	}

	/// Writes the given Cartfile.resolved out to the project's directory.
	public func writeResolvedCartfile(_ resolvedCartfile: ResolvedCartfile) -> Result<(), CarthageError> {
		return Result(at: resolvedCartfileURL, attempt: {
			try resolvedCartfile.description.write(to: $0, atomically: true, encoding: .utf8)
		})
	}

	/// Limits the number of concurrent clones/fetches to the number of active
	/// processors.
	private let cloneOrFetchQueue = ConcurrentProducerQueue(name: "org.carthage.CarthageKit", limit: ProcessInfo.processInfo.activeProcessorCount)

	/// Clones the given dependency to the global repositories folder, or fetches
	/// inside it if it has already been cloned.
	///
	/// Returns a signal which will send the URL to the repository's folder on
	/// disk once cloning or fetching has completed.
	private func cloneOrFetchDependency(_ dependency: Dependency, commitish: String? = nil) -> SignalProducer<URL, CarthageError> {
		return cloneOrFetch(dependency: dependency, preferHTTPS: self.preferHTTPS, commitish: commitish)
			.on(value: { event, _ in
				if let event = event {
					self._projectEventsObserver.send(value: event)
				}
			})
			.map { _, url in url }
			.take(last: 1)
			.startOnQueue(cloneOrFetchQueue)
	}

	func downloadBinaryFrameworkDefinition(url: URL) -> SignalProducer<BinaryProject, CarthageError> {
		return SignalProducer<Project.CachedBinaryProjects, CarthageError>(value: self.cachedBinaryProjects)
			.flatMap(.merge) { binaryProjectsByURL -> SignalProducer<BinaryProject, CarthageError> in
				if let binaryProject = binaryProjectsByURL[url] {
					return SignalProducer(value: binaryProject)
				} else {
					self._projectEventsObserver.send(value: .downloadingBinaryFrameworkDefinition(.binary(url), url))

					return URLSession.shared.reactive.data(with: URLRequest(url: url))
						.mapError { CarthageError.readFailed(url, $0 as NSError) }
						.attemptMap { data, _ in
							return BinaryProject.from(jsonData: data).mapError { error in
								return CarthageError.invalidBinaryJSON(url, error)
							}
						}
						.on(value: { binaryProject in
							self.cachedBinaryProjects[url] = binaryProject
						})
				}
			}
			.startOnQueue(self.cachedBinaryProjectsQueue)
	}

	/// Sends all versions available for the given project.
	///
	/// This will automatically clone or fetch the project's repository as
	/// necessary.
	private func versions(for dependency: Dependency) -> SignalProducer<PinnedVersion, CarthageError> {
		let fetchVersions: SignalProducer<PinnedVersion, CarthageError>

		switch dependency {
		case .git, .gitHub:
			fetchVersions = cloneOrFetchDependency(dependency)
				.flatMap(.merge) { repositoryURL in listTags(repositoryURL) }
				.map { PinnedVersion($0) }

		case let .binary(url):
			fetchVersions = downloadBinaryFrameworkDefinition(url: url)
				.flatMap(.concat) { binaryProject -> SignalProducer<PinnedVersion, CarthageError> in
					return SignalProducer(binaryProject.versions.keys)
				}
		}

		return SignalProducer<Project.CachedVersions, CarthageError>(value: self.cachedVersions)
			.flatMap(.merge) { versionsByDependency -> SignalProducer<PinnedVersion, CarthageError> in
				if let versions = versionsByDependency[dependency] {
					return SignalProducer(versions)
				} else {
					return fetchVersions
						.collect()
						.on(value: { newVersions in
							self.cachedVersions[dependency] = newVersions
						})
						.flatMap(.concat) { versions in SignalProducer<PinnedVersion, CarthageError>(versions) }
				}
			}
			.startOnQueue(cachedVersionsQueue)
			.collect()
			.flatMap(.concat) { versions -> SignalProducer<PinnedVersion, CarthageError> in
				if versions.isEmpty {
					return SignalProducer(error: .taggedVersionNotFound(dependency))
				}

				return SignalProducer(versions)
			}
	}

	/// Produces the sub dependencies of the given dependency. Uses the checked out directory if able
	private func dependencySet(for dependency: Dependency, version: PinnedVersion) -> SignalProducer<Set<Dependency>, CarthageError> {
		return self.dependencies(for: dependency, version: version, tryCheckoutDirectory: true)
			.map { $0.0 }
			.collect()
			.map { Set($0) }
			.concat(value: Set())
			.take(first: 1)
	}

	/// Loads the dependencies for the given dependency, at the given version.
	private func dependencies(for dependency: Dependency, version: PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError> {
		return self.dependencies(for: dependency, version: version, tryCheckoutDirectory: false)
	}

	/// Loads the dependencies for the given dependency, at the given version. Optionally can attempt to read from the Checkout directory
	private func dependencies(
		for dependency: Dependency,
		version: PinnedVersion,
		tryCheckoutDirectory: Bool
	) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError> {
		switch dependency {
		case .git, .gitHub:
			let revision = version.commitish
			let cartfileFetch: SignalProducer<Cartfile, CarthageError> = self.cloneOrFetchDependency(dependency, commitish: revision)
				.flatMap(.concat) { repositoryURL in
					return contentsOfFileInRepository(repositoryURL, Constants.Project.cartfilePath, revision: revision)
				}
				.flatMapError { _ in .empty }
				.attemptMap(Cartfile.from(string:))

			let cartfileSource: SignalProducer<Cartfile, CarthageError>
			if tryCheckoutDirectory {
				let dependencyURL = self.directoryURL.appendingPathComponent(dependency.relativePath)
				cartfileSource = SignalProducer<Bool, NoError> { () -> Bool in
					var isDirectory: ObjCBool = false
					return FileManager.default.fileExists(atPath: dependencyURL.path, isDirectory: &isDirectory) && isDirectory.boolValue
				}
				.flatMap(.concat) { directoryExists -> SignalProducer<Cartfile, CarthageError> in
					if directoryExists {
						return SignalProducer(result: Cartfile.from(file: dependencyURL.appendingPathComponent(Constants.Project.cartfilePath)))
							.flatMapError { _ in .empty }
					} else {
						return cartfileFetch
					}
				}
				.flatMapError { _ in .empty }
			} else {
				cartfileSource = cartfileFetch
			}
			return cartfileSource
				.flatMap(.concat) { cartfile -> SignalProducer<(Dependency, VersionSpecifier), CarthageError> in
					return SignalProducer(cartfile.dependencies.map { ($0.0, $0.1) })
				}

		case .binary:
			// Binary-only frameworks do not support dependencies
			return .empty
		}
	}

	/// Attempts to resolve a Git reference to a version.
	private func resolvedGitReference(_ dependency: Dependency, reference: String) -> SignalProducer<PinnedVersion, CarthageError> {
		let repositoryURL = repositoryFileURL(for: dependency)
		return cloneOrFetchDependency(dependency, commitish: reference)
			.flatMap(.concat) { _ in
				return resolveTagInRepository(repositoryURL, reference)
					.map { _ in
						// If the reference is an exact tag, resolves it to the tag.
						return PinnedVersion(reference)
					}
					.flatMapError { _ in
						return resolveReferenceInRepository(repositoryURL, reference)
							.map(PinnedVersion.init)
					}
			}
	}

	/// Attempts to determine the latest satisfiable version of the project's
	/// Carthage dependencies.
	///
	/// This will fetch dependency repositories as necessary, but will not check
	/// them out into the project's working directory.
	public func updatedResolvedCartfile(_ dependenciesToUpdate: [String]? = nil, resolver: ResolverProtocol) -> SignalProducer<ResolvedCartfile, CarthageError> {
		let resolvedCartfile: SignalProducer<ResolvedCartfile?, CarthageError> = loadResolvedCartfile()
			.map(Optional.init)
			.flatMapError { _ in .init(value: nil) }

		return SignalProducer
			.zip(loadCombinedCartfile(), resolvedCartfile)
			.flatMap(.merge) { cartfile, resolvedCartfile in
				return resolver.resolve(
					dependencies: cartfile.dependencies,
					lastResolved: resolvedCartfile?.dependencies,
					dependenciesToUpdate: dependenciesToUpdate
				)
			}
			.map(ResolvedCartfile.init)
	}

	/// Attempts to determine the latest version (whether satisfiable or not)
	/// of the project's Carthage dependencies.
	///
	/// This will fetch dependency repositories as necessary, but will not check
	/// them out into the project's working directory.
	private func latestDependencies(resolver: ResolverProtocol) -> SignalProducer<[Dependency: PinnedVersion], CarthageError> {
		return loadResolvedCartfile()
			.map { $0.dependencies.mapValues { _ in VersionSpecifier.any } }
			.flatMap(.merge) { resolver.resolve(dependencies: $0, lastResolved: nil, dependenciesToUpdate: nil) }
	}

	public typealias OutdatedDependency = (Dependency, PinnedVersion, PinnedVersion, PinnedVersion)
	/// Attempts to determine which of the project's Carthage
	/// dependencies are out of date.
	///
	/// This will fetch dependency repositories as necessary, but will not check
	/// them out into the project's working directory.
	public func outdatedDependencies(_ includeNestedDependencies: Bool, useNewResolver: Bool = true, resolver: ResolverProtocol? = nil) -> SignalProducer<[OutdatedDependency], CarthageError> {
		let resolverType: ResolverProtocol.Type
		if useNewResolver {
			resolverType = NewResolver.self
		} else {
			resolverType = Resolver.self
		}

		let dependencies: (Dependency, PinnedVersion) -> SignalProducer<(Dependency, VersionSpecifier), CarthageError>
		if includeNestedDependencies {
			dependencies = self.dependencies(for:version:)
		} else {
			dependencies = { _, _ in .empty }
		}

		let resolver = resolver ?? resolverType.init(
			versionsForDependency: versions(for:),
			dependenciesForDependency: dependencies,
			resolvedGitReference: resolvedGitReference
		)

		let outdatedDependencies = SignalProducer
			.combineLatest(
				loadResolvedCartfile(),
				updatedResolvedCartfile(resolver: resolver),
				latestDependencies(resolver: resolver)
			)
			.map { ($0.dependencies, $1.dependencies, $2) }
			.map { (currentDependencies, updatedDependencies, latestDependencies) -> [OutdatedDependency] in
				return updatedDependencies.flatMap { (project, version) -> OutdatedDependency? in
					if let resolved = currentDependencies[project], let latest = latestDependencies[project], resolved != version || resolved != latest {
						if SemanticVersion.from(resolved).value == nil, version == resolved {
							// If resolved version is not a semantic version but a commit
							// it is a false-positive if `version` and `resolved` are the same
							return nil
						}

						return (project, resolved, version, latest)
					} else {
						return nil
					}
				}
			}

		if includeNestedDependencies {
			return outdatedDependencies
		}

		return SignalProducer
			.combineLatest(
				outdatedDependencies,
				loadCombinedCartfile()
			)
			.map { oudatedDependencies, combinedCartfile -> [OutdatedDependency] in
				return oudatedDependencies.filter { project, _, _, _ in
					return combinedCartfile.dependencies[project] != nil
				}
			}
	}

	/// Updates the dependencies of the project to the latest version. The
	/// changes will be reflected in Cartfile.resolved, and also in the working
	/// directory checkouts if the given parameter is true.
	public func updateDependencies(
		shouldCheckout: Bool = true,
		useNewResolver: Bool = false,
		buildOptions: BuildOptions,
		dependenciesToUpdate: [String]? = nil
	) -> SignalProducer<(), CarthageError> {
		let resolverType: ResolverProtocol.Type
		if useNewResolver {
			resolverType = NewResolver.self
		} else {
			resolverType = Resolver.self
		}
		let resolver = resolverType.init(
			versionsForDependency: versions(for:),
			dependenciesForDependency: dependencies(for:version:),
			resolvedGitReference: resolvedGitReference
		)

		return updatedResolvedCartfile(dependenciesToUpdate, resolver: resolver)
			.attemptMap { resolvedCartfile -> Result<(), CarthageError> in
				return self.writeResolvedCartfile(resolvedCartfile)
			}
			.then(shouldCheckout ? checkoutResolvedDependencies(dependenciesToUpdate, buildOptions: buildOptions) : .empty)
	}

	/// Unzips the file at the given URL and copies the frameworks, DSYM and
	/// bcsymbolmap files into the corresponding folders for the project. This
	/// step will also check framework compatibility and create a version file
	/// for the given frameworks.
	///
	/// Sends the temporary URL of the unzipped directory
	private func unarchiveAndCopyBinaryFrameworks(
		zipFile: URL,
		projectName: String,
		pinnedVersion: PinnedVersion,
		toolchain: String?
	) -> SignalProducer<URL, CarthageError> {
		return SignalProducer<URL, CarthageError>(value: zipFile)
			.flatMap(.concat, unarchive(archive:))
			.flatMap(.concat) { directoryURL -> SignalProducer<URL, CarthageError> in
				return frameworksInDirectory(directoryURL)
					.flatMap(.merge) { url -> SignalProducer<URL, CarthageError> in
						return checkFrameworkCompatibility(url, usingToolchain: toolchain)
							.mapError { error in CarthageError.internalError(description: error.description) }
					}
					.flatMap(.merge, self.copyFrameworkToBuildFolder)
					.flatMap(.merge) { frameworkURL -> SignalProducer<URL, CarthageError> in
						return self.copyDSYMToBuildFolderForFramework(frameworkURL, fromDirectoryURL: directoryURL)
							.then(self.copyBCSymbolMapsToBuildFolderForFramework(frameworkURL, fromDirectoryURL: directoryURL))
							.then(SignalProducer(value: frameworkURL))
					}
					.collect()
					.flatMap(.concat) { frameworkURLs -> SignalProducer<(), CarthageError> in
						return self.createVersionFilesForFrameworks(
							frameworkURLs,
							fromDirectoryURL: directoryURL,
							projectName: projectName,
							commitish: pinnedVersion.commitish
						)
					}
					.then(SignalProducer<URL, CarthageError>(value: directoryURL))
			}
	}

	/// Removes the file located at the given URL
	///
	/// Sends empty value on successful removal
	private func removeItem(at url: URL) -> SignalProducer<(), CarthageError> {
		return SignalProducer {
			Result(at: url, attempt: FileManager.default.removeItem(at:))
		}
	}

	/// Installs binaries and debug symbols for the given project, if available.
	///
	/// Sends a boolean indicating whether binaries were installed.
	private func installBinaries(for dependency: Dependency, pinnedVersion: PinnedVersion, toolchain: String?) -> SignalProducer<Bool, CarthageError> {
		return SignalProducer<Bool, CarthageError>(value: self.useBinaries)
			.flatMap(.merge) { useBinaries -> SignalProducer<Bool, CarthageError> in
				if !useBinaries {
					return SignalProducer(value: false)
				}

				let checkoutDirectoryURL = self.directoryURL.appendingPathComponent(dependency.relativePath, isDirectory: true)

				switch dependency {
				case let .gitHub(server, repository):
					let client = Client(server: server)
					return self.downloadMatchingBinaries(for: dependency, pinnedVersion: pinnedVersion, fromRepository: repository, client: client)
						.flatMapError { error -> SignalProducer<URL, CarthageError> in
							if !client.isAuthenticated {
								return SignalProducer(error: error)
							}
							return self.downloadMatchingBinaries(
								for: dependency,
								pinnedVersion: pinnedVersion,
								fromRepository: repository,
								client: Client(server: server, isAuthenticated: false)
							)
						}
						.flatMap(.concat) {
							return self.unarchiveAndCopyBinaryFrameworks(zipFile: $0, projectName: dependency.name, pinnedVersion: pinnedVersion, toolchain: toolchain)
								.on(value: { _ in
									// Trash the checkouts folder when we've successfully copied binaries, to avoid building unnecessarily
									_ = try? FileManager.default.trashItem(at: checkoutDirectoryURL, resultingItemURL: nil)
								})
						}
						.flatMap(.concat) { self.removeItem(at: $0) }
						.map { true }
						.flatMapError { error in
							self._projectEventsObserver.send(value: .skippedInstallingBinaries(dependency: dependency, error: error))
							return SignalProducer(value: false)
						}
						.concat(value: false)
						.take(first: 1)

				case .git, .binary:
					return SignalProducer(value: false)
				}
			}
	}

	/// Downloads any binaries and debug symbols that may be able to be used
	/// instead of a repository checkout.
	///
	/// Sends the URL to each downloaded zip, after it has been moved to a
	/// less temporary location.
	private func downloadMatchingBinaries(
		for dependency: Dependency,
		pinnedVersion: PinnedVersion,
		fromRepository repository: Repository,
		client: Client
	) -> SignalProducer<URL, CarthageError> {
		return client.execute(repository.release(forTag: pinnedVersion.commitish))
			.map { _, release in release }
			.filter { release in
				return !release.isDraft && !release.assets.isEmpty
			}
			.flatMapError { error -> SignalProducer<Release, CarthageError> in
				switch error {
				case .doesNotExist:
					return .empty

				case let .apiError(_, _, error):
					// Log the GitHub API request failure, not to error out,
					// because that should not be fatal error.
					self._projectEventsObserver.send(value: .skippedDownloadingBinaries(dependency, error.message))
					return .empty

				default:
					return SignalProducer(error: .gitHubAPIRequestFailed(error))
				}
			}
			.on(value: { release in
				self._projectEventsObserver.send(value: .downloadingBinaries(dependency, release.nameWithFallback))
			})
			.flatMap(.concat) { release -> SignalProducer<URL, CarthageError> in
				return SignalProducer<Release.Asset, CarthageError>(release.assets)
					.filter { asset in
						if asset.name.range(of: Constants.Project.binaryAssetPattern) == nil {
							return false
						}
						return Constants.Project.binaryAssetContentTypes.contains(asset.contentType)
					}
					.flatMap(.concat) { asset -> SignalProducer<URL, CarthageError> in
						let fileURL = fileURLToCachedBinary(dependency, release, asset)

						if FileManager.default.fileExists(atPath: fileURL.path) {
							return SignalProducer(value: fileURL)
						} else {
							return client.download(asset: asset)
								.mapError(CarthageError.gitHubAPIRequestFailed)
								.flatMap(.concat) { downloadURL in cacheDownloadedBinary(downloadURL, toURL: fileURL) }
						}
					}
			}
	}

	/// Copies the framework at the given URL into the current project's build
	/// folder.
	///
	/// Sends the URL to the framework after copying.
	private func copyFrameworkToBuildFolder(_ frameworkURL: URL) -> SignalProducer<URL, CarthageError> {
		return platformForFramework(frameworkURL)
			.flatMap(.merge) { platform -> SignalProducer<URL, CarthageError> in
				let platformFolderURL = self.directoryURL.appendingPathComponent(platform.relativePath, isDirectory: true)
				return SignalProducer(value: frameworkURL)
					.copyFileURLsIntoDirectory(platformFolderURL)
			}
	}

	/// Copies the DSYM matching the given framework and contained within the
	/// given directory URL to the directory that the framework resides within.
	///
	/// If no dSYM is found for the given framework, completes with no values.
	///
	/// Sends the URL of the dSYM after copying.
	public func copyDSYMToBuildFolderForFramework(_ frameworkURL: URL, fromDirectoryURL directoryURL: URL) -> SignalProducer<URL, CarthageError> {
		let destinationDirectoryURL = frameworkURL.deletingLastPathComponent()
		return dSYMForFramework(frameworkURL, inDirectoryURL: directoryURL)
			.copyFileURLsIntoDirectory(destinationDirectoryURL)
	}

	/// Copies any *.bcsymbolmap files matching the given framework and contained
	/// within the given directory URL to the directory that the framework
	/// resides within.
	///
	/// If no bcsymbolmap files are found for the given framework, completes with
	/// no values.
	///
	/// Sends the URLs of the bcsymbolmap files after copying.
	public func copyBCSymbolMapsToBuildFolderForFramework(_ frameworkURL: URL, fromDirectoryURL directoryURL: URL) -> SignalProducer<URL, CarthageError> {
		let destinationDirectoryURL = frameworkURL.deletingLastPathComponent()
		return BCSymbolMapsForFramework(frameworkURL, inDirectoryURL: directoryURL)
			.copyFileURLsIntoDirectory(destinationDirectoryURL)
	}

	/// Creates a .version file for all of the provided frameworks.
	public func createVersionFilesForFrameworks(
		_ frameworkURLs: [URL],
		fromDirectoryURL directoryURL: URL,
		projectName: String,
		commitish: String
	) -> SignalProducer<(), CarthageError> {
		return createVersionFileForCommitish(commitish, dependencyName: projectName, buildProducts: frameworkURLs, rootDirectoryURL: self.directoryURL)
	}

	private let gitOperationQueue = SerialProducerQueue(name: "org.carthage.Constants.Project.gitOperationQueue")

	/// Checks out the given dependency into its intended working directory,
	/// cloning it first if need be.
	private func checkoutOrCloneDependency(
		_ dependency: Dependency,
		version: PinnedVersion,
		submodulesByPath: [String: Submodule]
	) -> SignalProducer<(), CarthageError> {
		let revision = version.commitish
		return cloneOrFetchDependency(dependency, commitish: revision)
			.flatMap(.merge) { repositoryURL -> SignalProducer<(), CarthageError> in
				let workingDirectoryURL = self.directoryURL.appendingPathComponent(dependency.relativePath, isDirectory: true)

				/// The submodule for an already existing submodule at dependency project’s path
				/// or the submodule to be added at this path given the `--use-submodules` flag.
				let submodule: Submodule?

				if var foundSubmodule = submodulesByPath[dependency.relativePath] {
					foundSubmodule.url = dependency.gitURL(preferHTTPS: self.preferHTTPS)!
					foundSubmodule.sha = revision
					submodule = foundSubmodule
				} else if self.useSubmodules {
					submodule = Submodule(name: dependency.relativePath, path: dependency.relativePath, url: dependency.gitURL(preferHTTPS: self.preferHTTPS)!, sha: revision)
				} else {
					submodule = nil
				}

				let symlinkCheckoutPaths = self.symlinkCheckoutPaths(for: dependency, version: version, withRepository: repositoryURL, atRootDirectory: self.directoryURL)

				if let submodule = submodule {
					// In the presence of `submodule` for `dependency` — before symlinking, (not after) — add submodule and its submodules:
					// `dependency`, subdependencies that are submodules, and non-Carthage-housed submodules.
					return addSubmoduleToRepository(self.directoryURL, submodule, GitURL(repositoryURL.path))
						.startOnQueue(self.gitOperationQueue)
						.then(symlinkCheckoutPaths)
				} else {
					return checkoutRepositoryToDirectory(repositoryURL, workingDirectoryURL, revision: revision)
						// For checkouts of “ideally bare” repositories of `dependency`, we add its submodules by cloning ourselves, after symlinking.
						.then(symlinkCheckoutPaths)
						.then(
							submodulesInRepository(repositoryURL, revision: revision)
								.flatMap(.merge) {
									cloneSubmoduleInWorkingDirectory($0, workingDirectoryURL)
								}
						)
				}
			}
			.on(started: {
				self._projectEventsObserver.send(value: .checkingOut(dependency, revision))
			})
	}

	public func buildOrderForResolvedCartfile(
		_ cartfile: ResolvedCartfile,
		dependenciesToInclude: [String]? = nil
	) -> SignalProducer<(Dependency, PinnedVersion), CarthageError> {
		typealias DependencyGraph = [Dependency: Set<Dependency>]
		// A resolved cartfile already has all the recursive dependencies. All we need to do is sort
		// out the relationships between them. Loading the cartfile will each will give us its
		// dependencies. Building a recursive lookup table with this information will let us sort
		// dependencies before the projects that depend on them.
		return SignalProducer<(Dependency, PinnedVersion), CarthageError>(cartfile.dependencies.map { ($0, $1) })
			.flatMap(.merge) { (dependency: Dependency, version: PinnedVersion) -> SignalProducer<DependencyGraph, CarthageError> in
				return self.dependencySet(for: dependency, version: version)
					.map { dependencies in
						[dependency: dependencies]
					}
			}
			.reduce(into: [:]) { (working: inout DependencyGraph, next: DependencyGraph) in
				for (key, value) in next {
					working.updateValue(value, forKey: key)
				}
			}
			.flatMap(.latest) { (graph: DependencyGraph) -> SignalProducer<(Dependency, PinnedVersion), CarthageError> in
				let dependenciesToInclude = Set(graph
					.map { dependency, _ in dependency }
					.filter { dependency in dependenciesToInclude?.contains(dependency.name) ?? false })

				guard let sortedDependencies = topologicalSort(graph, nodes: dependenciesToInclude) else { // swiftlint:disable:this single_line_guard
					return SignalProducer(error: .dependencyCycle(graph))
				}

				let sortedPinnedDependencies = cartfile.dependencies.keys
					.filter { dependency in sortedDependencies.contains(dependency) }
					.sorted { left, right in sortedDependencies.index(of: left)! < sortedDependencies.index(of: right)! }
					.map { ($0, cartfile.dependencies[$0]!) }

				return SignalProducer(sortedPinnedDependencies)
			}
	}

	/// Checks out the dependencies listed in the project's Cartfile.resolved,
	/// optionally they are limited by the given list of dependency names.
	public func checkoutResolvedDependencies(_ dependenciesToCheckout: [String]? = nil, buildOptions: BuildOptions?) -> SignalProducer<(), CarthageError> {
		/// Determine whether the repository currently holds any submodules (if
		/// it even is a repository).
		let submodulesSignal = submodulesInRepository(self.directoryURL)
			.reduce(into: [:]) { (submodulesByPath: inout [String: Submodule], submodule) in
				submodulesByPath[submodule.path] = submodule
			}

		return loadResolvedCartfile()
			.map { resolvedCartfile -> [(Dependency, PinnedVersion)] in
				return resolvedCartfile.dependencies
					.filter { dep, _ in dependenciesToCheckout?.contains(dep.name) ?? true }
			}
			.zip(with: submodulesSignal)
			.flatMap(.merge) { dependencies, submodulesByPath -> SignalProducer<(), CarthageError> in
				return SignalProducer<(Dependency, PinnedVersion), CarthageError>(dependencies)
					.flatMap(.concurrent(limit: 4)) { dependency, version -> SignalProducer<(), CarthageError> in
						switch dependency {
						case .git, .gitHub:

							let submoduleFound = submodulesByPath[dependency.relativePath] != nil
							let checkoutOrCloneDependency = self.checkoutOrCloneDependency(dependency, version: version, submodulesByPath: submodulesByPath)

							// Disable binary downloads for the dependency if that
							// is already checked out as a submodule.
							if submoduleFound {
								return checkoutOrCloneDependency
							}

							return self.installBinaries(for: dependency, pinnedVersion: version, toolchain: buildOptions?.toolchain)
								.flatMap(.merge) { installed -> SignalProducer<(), CarthageError> in
									if installed {
										return .empty
									} else {
										return checkoutOrCloneDependency
									}
								}

						case let .binary(url):
							return self.installBinariesForBinaryProject(url: url, pinnedVersion: version, projectName: dependency.name, toolchain: buildOptions?.toolchain)
						}
					}
			}
			.then(SignalProducer<(), CarthageError>.empty)
	}

	private func installBinariesForBinaryProject(
		url: URL,
		pinnedVersion: PinnedVersion,
		projectName: String,
		toolchain: String?
	) -> SignalProducer<(), CarthageError> {
		return SignalProducer<SemanticVersion, ScannableError>(result: SemanticVersion.from(pinnedVersion))
			.mapError { CarthageError(scannableError: $0) }
			.combineLatest(with: self.downloadBinaryFrameworkDefinition(url: url))
			.attemptMap { semanticVersion, binaryProject -> Result<(SemanticVersion, URL), CarthageError> in
				guard let frameworkURL = binaryProject.versions[pinnedVersion] else {
					return .failure(CarthageError.requiredVersionNotFound(Dependency.binary(url), VersionSpecifier.exactly(semanticVersion)))
				}

				return .success((semanticVersion, frameworkURL))
			}
			.flatMap(.concat) { semanticVersion, frameworkURL in
				return self.downloadBinary(dependency: Dependency.binary(url), version: semanticVersion, url: frameworkURL)
			}
			.flatMap(.concat) { self.unarchiveAndCopyBinaryFrameworks(zipFile: $0, projectName: projectName, pinnedVersion: pinnedVersion, toolchain: toolchain) }
			.flatMap(.concat) { self.removeItem(at: $0) }
	}

	/// Downloads the binary only framework file. Sends the URL to each downloaded zip, after it has been moved to a
	/// less temporary location.
	private func downloadBinary(dependency: Dependency, version: SemanticVersion, url: URL) -> SignalProducer<URL, CarthageError> {
		let fileName = url.lastPathComponent
		let fileURL = fileURLToCachedBinaryDependency(dependency, version, fileName)

		if FileManager.default.fileExists(atPath: fileURL.path) {
			return SignalProducer(value: fileURL)
		} else {
			return URLSession.shared.reactive.download(with: URLRequest(url: url))
				.on(started: {
					self._projectEventsObserver.send(value: .downloadingBinaries(dependency, version.description))
				})
				.mapError { CarthageError.readFailed(url, $0 as NSError) }
				.flatMap(.concat) { downloadURL, _ in cacheDownloadedBinary(downloadURL, toURL: fileURL) }
		}
	}

	/// Creates symlink between the dependency checkouts and the root checkouts
	private func symlinkCheckoutPaths(
		for dependency: Dependency,
		version: PinnedVersion,
		withRepository repositoryURL: URL,
		atRootDirectory rootDirectoryURL: URL
	) -> SignalProducer<(), CarthageError> {
		let rawDependencyURL = rootDirectoryURL.appendingPathComponent(dependency.relativePath, isDirectory: true)
		let dependencyURL = rawDependencyURL.resolvingSymlinksInPath()
		let dependencyCheckoutsURL = dependencyURL.appendingPathComponent(carthageProjectCheckoutsPath, isDirectory: true).resolvingSymlinksInPath()
		let fileManager = FileManager.default

		return self.dependencySet(for: dependency, version: version)
			.zip(with: // file system objects which might conflict with symlinks
				list(treeish: version.commitish, atPath: carthageProjectCheckoutsPath, inRepository: repositoryURL)
					.map { (path: String) in (path as NSString).lastPathComponent }
					.collect()
			)
			.attemptMap { (dependencies: Set<Dependency>, components: [String]) -> Result<(), CarthageError> in
				let names = dependencies
					.filter { dependency in
						// Filter out dependencies with names matching (case-insensitively) file system objects from git in `CarthageProjectCheckoutsPath`.
						// Edge case warning on file system case-sensitivity. If a differently-cased file system object exists in git
						// and is stored on a case-sensitive file system (like the Sierra preview of APFS), we currently preempt
						// the non-conflicting symlink. Probably, nobody actually desires or needs the opposite behavior.
						!components.contains {
							dependency.name.caseInsensitiveCompare($0) == .orderedSame
						}
					}
					.map { $0.name }

				// If no `CarthageProjectCheckoutsPath`-housed symlinks are needed,
				// return early after potentially adding submodules
				// (which could be outside `CarthageProjectCheckoutsPath`).
				if names.isEmpty { return .success(()) } // swiftlint:disable:this single_line_return

				do {
					try fileManager.createDirectory(at: dependencyCheckoutsURL, withIntermediateDirectories: true)
				} catch let error as NSError {
					if !(error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError) {
						return .failure(.writeFailed(dependencyCheckoutsURL, error))
					}
				}

				for name in names {
					let dependencyCheckoutURL = dependencyCheckoutsURL.appendingPathComponent(name)
					let subdirectoryPath = (carthageProjectCheckoutsPath as NSString).appendingPathComponent(name)
					let linkDestinationPath = relativeLinkDestination(for: dependency, subdirectory: subdirectoryPath)

					let dependencyCheckoutURLResource = try? dependencyCheckoutURL.resourceValues(forKeys: [
						.isSymbolicLinkKey,
						.isDirectoryKey,
					])

					if dependencyCheckoutURLResource?.isSymbolicLink == true {
						_ = dependencyCheckoutURL.path.withCString(Darwin.unlink)
					} else if dependencyCheckoutURLResource?.isDirectory == true {
						// older version of carthage wrote this directory?
						// user wrote this directory, unaware of the precedent not to circumvent carthage’s management?
						// directory exists as the result of rogue process or gamma ray?

						// TODO: explore possibility of messaging user, informing that deleting said directory will result
						// in symlink creation with carthage versions greater than 0.20.0, maybe with more broad advice on
						// “from scratch” reproducability.
						continue
					}

					if let error = Result(at: dependencyCheckoutURL, attempt: {
						try fileManager.createSymbolicLink(atPath: $0.path, withDestinationPath: linkDestinationPath)
					}).error {
						return .failure(error)
					}
				}

				return .success(())
			}
	}

	/// Attempts to build each Carthage dependency that has been checked out,
	/// optionally they are limited by the given list of dependency names.
	/// Cached dependencies whose dependency trees are also cached will not
	/// be rebuilt unless otherwise specified via build options.
	///
	/// Returns a producer-of-producers representing each scheme being built.
	public func buildCheckedOutDependenciesWithOptions(
		_ options: BuildOptions,
		dependenciesToBuild: [String]? = nil,
		sdkFilter: @escaping SDKFilterCallback = { sdks, _, _, _ in .success(sdks) }
	) -> SignalProducer<BuildSchemeProducer, CarthageError> {
		return loadResolvedCartfile()
			.flatMap(.concat) { resolvedCartfile -> SignalProducer<(Dependency, PinnedVersion), CarthageError> in
				return self.buildOrderForResolvedCartfile(resolvedCartfile, dependenciesToInclude: dependenciesToBuild)
			}
			.flatMap(.concat) { dependency, version -> SignalProducer<((Dependency, PinnedVersion), Set<Dependency>, Bool?), CarthageError> in
				return SignalProducer.combineLatest(
					SignalProducer(value: (dependency, version)),
					self.dependencySet(for: dependency, version: version),
					versionFileMatches(dependency, version: version, platforms: options.platforms, rootDirectoryURL: self.directoryURL, toolchain: options.toolchain)
				)
			}
			.reduce([]) { includedDependencies, nextGroup -> [(Dependency, PinnedVersion)] in
				let (nextDependency, projects, matches) = nextGroup

				var dependenciesIncludingNext = includedDependencies
				dependenciesIncludingNext.append(nextDependency)

				let projectsToBeBuilt = Set(includedDependencies.map { $0.0 })

				guard options.cacheBuilds && projects.isDisjoint(with: projectsToBeBuilt) else {
					return dependenciesIncludingNext
				}

				guard let versionFileMatches = matches else {
					self._projectEventsObserver.send(value: .buildingUncached(nextDependency.0))
					return dependenciesIncludingNext
				}

				if versionFileMatches {
					self._projectEventsObserver.send(value: .skippedBuildingCached(nextDependency.0))
					return includedDependencies
				} else {
					self._projectEventsObserver.send(value: .rebuildingCached(nextDependency.0))
					return dependenciesIncludingNext
				}
			}
			.flatMap(.concat) { dependencies -> SignalProducer<(Dependency, PinnedVersion), CarthageError> in
				return .init(dependencies)
			}
			.flatMap(.concat) { dependency, version -> SignalProducer<BuildSchemeProducer, CarthageError> in
				let dependencyPath = self.directoryURL.appendingPathComponent(dependency.relativePath, isDirectory: true).path
				if !FileManager.default.fileExists(atPath: dependencyPath) {
					return .empty
				}

				var options = options
				let baseURL = options.derivedDataPath.flatMap(URL.init(string:)) ?? Constants.Dependency.derivedDataURL
				let derivedDataPerXcode = baseURL.appendingPathComponent(self.xcodeVersionDirectory, isDirectory: true)
				let derivedDataPerDependency = derivedDataPerXcode.appendingPathComponent(dependency.name, isDirectory: true)
				let derivedDataVersioned = derivedDataPerDependency.appendingPathComponent(version.commitish, isDirectory: true)
				options.derivedDataPath = derivedDataVersioned.resolvingSymlinksInPath().path

				return build(dependency: dependency, version: version, self.directoryURL, withOptions: options, sdkFilter: sdkFilter)
					.map { producer -> BuildSchemeProducer in
						return producer.flatMapError { error in
							switch error {
							case .noSharedFrameworkSchemes, .skip:
								// Log that building the dependency is being skipped,
								// not to error out with `.noSharedFrameworkSchemes`
								// to continue building other dependencies.
								self._projectEventsObserver.send(value: .skippedBuilding(dependency, error.description))
								return .empty

							default:
								return SignalProducer(error: error)
							}
						}
					}
			}
	}
}

/// Constructs a file URL to where the binary corresponding to the given
/// arguments should live.
private func fileURLToCachedBinary(_ dependency: Dependency, _ release: Release, _ asset: Release.Asset) -> URL {
	// ~/Library/Caches/org.carthage.CarthageKit/binaries/ReactiveCocoa/v2.3.1/1234-ReactiveCocoa.framework.zip
	return Constants.Dependency.assetsURL.appendingPathComponent("\(dependency.name)/\(release.tag)/\(asset.id)-\(asset.name)", isDirectory: false)
}

/// Constructs a file URL to where the binary only framework download should be cached
private func fileURLToCachedBinaryDependency(_ dependency: Dependency, _ semanticVersion: SemanticVersion, _ fileName: String) -> URL {
	// ~/Library/Caches/org.carthage.CarthageKit/binaries/MyBinaryProjectFramework/2.3.1/MyBinaryProject.framework.zip
	return Constants.Dependency.assetsURL.appendingPathComponent("\(dependency.name)/\(semanticVersion)/\(fileName)")
}

/// Caches the downloaded binary at the given URL, moving it to the other URL
/// given.
///
/// Sends the final file URL upon .success.
private func cacheDownloadedBinary(_ downloadURL: URL, toURL cachedURL: URL) -> SignalProducer<URL, CarthageError> {
	return SignalProducer(value: cachedURL)
		.attempt { fileURL in
			Result(at: fileURL.deletingLastPathComponent(), attempt: {
				try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
			})
		}
		.attempt { newDownloadURL in
			// Tries `rename()` system call at first.
			let result = downloadURL.withUnsafeFileSystemRepresentation { old in
				newDownloadURL.withUnsafeFileSystemRepresentation { new in
					rename(old!, new!)
				}
			}
			if result == 0 {
				return .success(())
			}

			if errno != EXDEV {
				return .failure(.taskError(.posixError(errno)))
			}

			// If the “Cross-device link” error occurred, then falls back to
			// `FileManager.moveItem(at:to:)`.
			//
			// See https://github.com/Carthage/Carthage/issues/706 and
			// https://github.com/Carthage/Carthage/issues/711.
			return Result(at: newDownloadURL, attempt: {
				try FileManager.default.moveItem(at: downloadURL, to: $0)
			})
		}
}

/// Sends the URL to each file found in the given directory conforming to the
/// given type identifier. If no type identifier is provided, all files are sent.
private func filesInDirectory(_ directoryURL: URL, _ typeIdentifier: String? = nil) -> SignalProducer<URL, CarthageError> {
	let producer = FileManager.default.reactive
		.enumerator(at: directoryURL, includingPropertiesForKeys: [ .typeIdentifierKey ], options: [ .skipsHiddenFiles, .skipsPackageDescendants ], catchErrors: true)
		.map { _, url in url }
	if let typeIdentifier = typeIdentifier {
		return producer
			.filter { url in
				return url.typeIdentifier
					.analysis(ifSuccess: { identifier in
						return UTTypeConformsTo(identifier as CFString, typeIdentifier as CFString)
					}, ifFailure: { _ in false })
			}
	} else {
		return producer
	}
}

/// Sends the platform specified in the given Info.plist.
func platformForFramework(_ frameworkURL: URL) -> SignalProducer<Platform, CarthageError> {
	return SignalProducer(value: frameworkURL)
		// Neither DTPlatformName nor CFBundleSupportedPlatforms can not be used
		// because Xcode 6 and below do not include either in macOS frameworks.
		.attemptMap { url -> Result<String, CarthageError> in
			let bundle = Bundle(url: url)

			func readFailed(_ message: String) -> CarthageError {
				let error = Result<(), NSError>.error(message)
				return .readFailed(frameworkURL, error)
			}

			func sdkNameFromExecutable() -> String? {
				guard let executableURL = bundle?.executableURL else {
					return nil
				}

				let task = Task("/usr/bin/xcrun", arguments: ["otool", "-lv", executableURL.path])

				let sdkName: String? = task.launch(standardInput: nil)
					.ignoreTaskData()
					.map { String(data: $0, encoding: .utf8) ?? "" }
					.filter { !$0.isEmpty }
					.flatMap(.merge) { (output: String) -> SignalProducer<String, NoError> in
						output.linesProducer
					}
					.filter { $0.contains("LC_VERSION") }
					.take(last: 1)
					.map { lcVersionLine -> String? in
						let sdkString = lcVersionLine.split(separator: "_")
							.last
							.flatMap(String.init)
							.flatMap { $0.lowercased() }

						return sdkString
					}
					.skipNil()
					.single()?
					.value

				return sdkName
			}

			// Try to read what platfrom this binary is for. Attempt in order:
			// 1. Read `DTSDKName` from Info.plist.
			//    Some users are reporting that static frameworks don't have this key in the .plist,
			//    so we fall back and check the binary of the executable itself.
			// 2. Read the LC_VERSION_<PLATFORM> from the framework's binary executable file

			if let sdkNameFromBundle = bundle?.object(forInfoDictionaryKey: "DTSDKName") as? String {
				return .success(sdkNameFromBundle)
			} else if let sdkNameFromExecutable = sdkNameFromExecutable() {
				return .success(sdkNameFromExecutable)
			} else {
				return .failure(readFailed("could not determine platform neither from DTSDKName key in plist nor from the framework's executable"))
			}
		}
		// Thus, the SDK name must be trimmed to match the platform name, e.g.
		// macosx10.10 -> macosx
		.map { sdkName in sdkName.trimmingCharacters(in: CharacterSet.letters.inverted) }
		.attemptMap { platform in SDK.from(string: platform).map { $0.platform } }
}

/// Sends the URL to each framework bundle found in the given directory.
private func frameworksInDirectory(_ directoryURL: URL) -> SignalProducer<URL, CarthageError> {
	return filesInDirectory(directoryURL, kUTTypeFramework as String)
		.filter { !$0.pathComponents.contains("__MACOSX") }
		.filter { url in

			// Skip nested frameworks
			let frameworksInURL = url.pathComponents.filter { pathComponent in
				return (pathComponent as NSString).pathExtension == "framework"
			}
			return frameworksInURL.count == 1
		}
}

/// Sends the URL to each dSYM found in the given directory
private func dSYMsInDirectory(_ directoryURL: URL) -> SignalProducer<URL, CarthageError> {
	return filesInDirectory(directoryURL, "com.apple.xcode.dsym")
}

/// Sends the URL of the dSYM whose UUIDs match those of the given framework, or
/// errors if there was an error parsing a dSYM contained within the directory.
private func dSYMForFramework(_ frameworkURL: URL, inDirectoryURL directoryURL: URL) -> SignalProducer<URL, CarthageError> {
	return UUIDsForFramework(frameworkURL)
		.flatMap(.concat) { (frameworkUUIDs: Set<UUID>) in
			return dSYMsInDirectory(directoryURL)
				.flatMap(.merge) { dSYMURL in
					return UUIDsForDSYM(dSYMURL)
						.filter { (dSYMUUIDs: Set<UUID>) in
							return dSYMUUIDs == frameworkUUIDs
						}
						.map { _ in dSYMURL }
				}
		}
		.take(first: 1)
}

/// Sends the URL to each bcsymbolmap found in the given directory.
private func BCSymbolMapsInDirectory(_ directoryURL: URL) -> SignalProducer<URL, CarthageError> {
	return filesInDirectory(directoryURL)
		.filter { url in url.pathExtension == "bcsymbolmap" }
}

/// Sends the URLs of the bcsymbolmap files that match the given framework and are
/// located somewhere within the given directory.
private func BCSymbolMapsForFramework(_ frameworkURL: URL, inDirectoryURL directoryURL: URL) -> SignalProducer<URL, CarthageError> {
	return UUIDsForFramework(frameworkURL)
		.flatMap(.merge) { uuids -> SignalProducer<URL, CarthageError> in
			if uuids.isEmpty {
				return .empty
			}
			func filterUUIDs(_ signal: Signal<URL, CarthageError>) -> Signal<URL, CarthageError> {
				var remainingUUIDs = uuids
				let count = remainingUUIDs.count
				return signal
					.filter { fileURL in
						let basename = fileURL.deletingPathExtension().lastPathComponent
						if let fileUUID = UUID(uuidString: basename) {
							return remainingUUIDs.remove(fileUUID) != nil
						} else {
							return false
						}
					}
					.take(first: count)
			}
			return BCSymbolMapsInDirectory(directoryURL)
				.lift(filterUUIDs)
		}
}

/// Returns the file URL at which the given project's repository will be
/// located.
private func repositoryFileURL(for dependency: Dependency, baseURL: URL = Constants.Dependency.repositoriesURL) -> URL {
	return baseURL.appendingPathComponent(dependency.name, isDirectory: true)
}

/// Returns the string representing a relative path from a dependency back to the root
internal func relativeLinkDestination(for dependency: Dependency, subdirectory: String) -> String {
	let dependencySubdirectoryPath = (dependency.relativePath as NSString).appendingPathComponent(subdirectory)
	let componentsForGettingTheHellOutOfThisRelativePath = Array(repeating: "..", count: (dependencySubdirectoryPath as NSString).pathComponents.count - 1)

	// Directs a link from, e.g., /Carthage/Checkouts/ReactiveCocoa/Carthage/Build to /Carthage/Build
	let linkDestinationPath = componentsForGettingTheHellOutOfThisRelativePath.reduce(subdirectory) { trailingPath, pathComponent in
		return (pathComponent as NSString).appendingPathComponent(trailingPath)
	}

	return linkDestinationPath
}

/// Clones the given project to the given destination URL (defaults to the global
/// repositories folder), or fetches inside it if it has already been cloned.
/// Optionally takes a commitish to check for prior to fetching.
///
/// Returns a signal which will send the operation type once started, and
/// the URL to where the repository's folder will exist on disk, then complete
/// when the operation completes.
public func cloneOrFetch(
	dependency: Dependency,
	preferHTTPS: Bool,
	destinationURL: URL = Constants.Dependency.repositoriesURL,
	commitish: String? = nil
) -> SignalProducer<(ProjectEvent?, URL), CarthageError> {
	let fileManager = FileManager.default
	let repositoryURL = repositoryFileURL(for: dependency, baseURL: destinationURL)

	return SignalProducer {
			Result(at: destinationURL, attempt: {
				try fileManager.createDirectory(at: $0, withIntermediateDirectories: true)
				return dependency.gitURL(preferHTTPS: preferHTTPS)!
			})
		}
		.flatMap(.merge) { (remoteURL: GitURL) -> SignalProducer<(ProjectEvent?, URL), CarthageError> in
			return isGitRepository(repositoryURL)
				.flatMap(.merge) { isRepository -> SignalProducer<(ProjectEvent?, URL), CarthageError> in
					let isLocalProject = dependency.isLocalProject
					if isRepository, isLocalProject == false {
						let fetchProducer: () -> SignalProducer<(ProjectEvent?, URL), CarthageError> = {
							guard FetchCache.needsFetch(forURL: remoteURL) else {
								return SignalProducer(value: (nil, repositoryURL))
							}

							return SignalProducer(value: (.fetching(dependency), repositoryURL))
								.concat(
									fetchRepository(repositoryURL, remoteURL: remoteURL, refspec: "+refs/heads/*:refs/heads/*")
										.then(SignalProducer<(ProjectEvent?, URL), CarthageError>.empty)
								)
						}

						// If we've already cloned the repo, check for the revision, possibly skipping an unnecessary fetch
						if let commitish = commitish {
							return SignalProducer.zip(
									branchExistsInRepository(repositoryURL, pattern: commitish),
									commitExistsInRepository(repositoryURL, revision: commitish)
								)
								.flatMap(.concat) { branchExists, commitExists -> SignalProducer<(ProjectEvent?, URL), CarthageError> in
									// If the given commitish is a branch, we should fetch.
									if branchExists || !commitExists {
										return fetchProducer()
									} else {
										return SignalProducer(value: (nil, repositoryURL))
									}
								}
						} else {
							return fetchProducer()
						}
					} else {
						// Either the directory didn't exist or it did but wasn't a git repository
						// (Could happen if the process is killed during a previous directory creation)
						// So we remove it, then clone
						_ = try? fileManager.removeItem(at: repositoryURL)
						return SignalProducer(value: (.cloning(dependency), repositoryURL))
							.concat(
								cloneRepository(remoteURL, repositoryURL)
									.then(SignalProducer<(ProjectEvent?, URL), CarthageError>.empty)
							)
					}
				}
		}
}
