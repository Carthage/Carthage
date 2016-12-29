//
//  Project.swift
//  Carthage
//
//  Created by Alan Rogers on 12/10/2014.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import Result
import ReactiveCocoa
import Tentacle

/// Carthage's bundle identifier.
public let CarthageKitBundleIdentifier = Bundle(for: Project.self).bundleIdentifier!

/// The fallback dependencies URL to be used in case
/// the intended ~/Library/Caches/org.carthage.CarthageKit cannot
/// be found or created.
private let fallbackDependenciesURL: URL = {
	let homePath: String
	if let homeEnvValue = ProcessInfo.processInfo.environment["HOME"] {
		homePath = (homeEnvValue as NSString).appendingPathComponent(".carthage")
	} else {
		homePath = ("~/.carthage" as NSString).expandingTildeInPath
	}
	return URL(fileURLWithPath: homePath, isDirectory:true)
}()

/// ~/Library/Caches/org.carthage.CarthageKit/
private let CarthageUserCachesURL: URL = {
	let fileManager = FileManager.`default`
	
	let urlResult: Result<URL, NSError> = `try` { (error: NSErrorPointer) -> URL? in
		return try? fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
	}.flatMap { cachesURL in
		let dependenciesURL = cachesURL.appendingPathComponent(CarthageKitBundleIdentifier, isDirectory: true)
		let dependenciesPath = dependenciesURL.carthage_absoluteString
		
		if fileManager.fileExists(atPath: dependenciesPath, isDirectory:nil) {
			if fileManager.isWritableFile(atPath: dependenciesPath) {
				return Result(value: dependenciesURL)
			} else {
				let error = NSError(domain: CarthageKitBundleIdentifier, code: 0, userInfo: nil)
				return Result(error: error)
			}
		} else {
			return Result(attempt: {
				try fileManager.createDirectory(at: dependenciesURL, withIntermediateDirectories: true, attributes: [NSFilePosixPermissions : 0o755])
				return dependenciesURL
			})
		}
	}

	switch urlResult {
	case let .Success(url):
		_ = try? FileManager.`default`.removeItem(at: fallbackDependenciesURL)
		return url
	case let .Failure(error):
		NSLog("Warning: No Caches directory could be found or created: \(error.localizedDescription). (\(error))")
		return fallbackDependenciesURL
	}
}()

/// The file URL to the directory in which downloaded release binaries will be
/// stored.
///
/// ~/Library/Caches/org.carthage.CarthageKit/binaries/
public let CarthageDependencyAssetsURL: URL = CarthageUserCachesURL.appendingPathComponent("binaries", isDirectory: true)

/// The file URL to the directory in which cloned dependencies will be stored.
///
/// ~/Library/Caches/org.carthage.CarthageKit/dependencies/
public let CarthageDependencyRepositoriesURL: URL = CarthageUserCachesURL.appendingPathComponent("dependencies", isDirectory: true)

/// The relative path to a project's Cartfile.
public let CarthageProjectCartfilePath = "Cartfile"

/// The relative path to a project's Cartfile.private.
public let CarthageProjectPrivateCartfilePath = "Cartfile.private"

/// The relative path to a project's Cartfile.resolved.
public let CarthageProjectResolvedCartfilePath = "Cartfile.resolved"

/// The text that needs to exist in a GitHub Release asset's name, for it to be
/// tried as a binary framework.
public let CarthageProjectBinaryAssetPattern = ".framework"

/// MIME types allowed for GitHub Release assets, for them to be considered as
/// binary frameworks.
public let CarthageProjectBinaryAssetContentTypes = [
	"application/zip"
]

/// Describes an event occurring to or with a project.
public enum ProjectEvent {
	/// The project is beginning to clone.
	case cloning(ProjectIdentifier)

	/// The project is beginning a fetch.
	case fetching(ProjectIdentifier)
	
	/// The project is being checked out to the specified revision.
	case checkingOut(ProjectIdentifier, String)

	/// Any available binaries for the specified release of the project are
	/// being downloaded. This may still be followed by `CheckingOut` event if
	/// there weren't any viable binaries after all.
	case downloadingBinaries(ProjectIdentifier, String)

	/// Downloading any available binaries of the project is being skipped,
	/// because of a GitHub API request failure which is due to authentication
	/// or rate-limiting.
	case skippedDownloadingBinaries(ProjectIdentifier, String)

	/// Building the project is being skipped, since the project is not sharing
	/// any framework schemes.
	case skippedBuilding(ProjectIdentifier, String)
}

/// Represents a project that is using Carthage.
public final class Project {
	/// File URL to the root directory of the project.
	public let directoryURL: URL

	/// The file URL to the project's Cartfile.
	public var cartfileURL: URL {
		return directoryURL.appendingPathComponent(CarthageProjectCartfilePath, isDirectory: false)
	}

	/// The file URL to the project's Cartfile.resolved.
	public var resolvedCartfileURL: URL {
		return directoryURL.appendingPathComponent(CarthageProjectResolvedCartfilePath, isDirectory: false)
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

	deinit {
		_projectEventsObserver.sendCompleted()
	}

	private typealias CachedVersions = [ProjectIdentifier: [PinnedVersion]]

	/// Caches versions to avoid expensive lookups, and unnecessary
	/// fetching/cloning.
	private var cachedVersions: CachedVersions = [:]
	private let cachedVersionsQueue = ProducerQueue(name: "org.carthage.CarthageKit.Project.cachedVersionsQueue")

	/// Attempts to load Cartfile or Cartfile.private from the given directory,
	/// merging their dependencies.
	public func loadCombinedCartfile() -> SignalProducer<Cartfile, CarthageError> {
		let cartfileURL = directoryURL.appendingPathComponent(CarthageProjectCartfilePath, isDirectory: false)
		let privateCartfileURL = directoryURL.appendingPathComponent(CarthageProjectPrivateCartfilePath, isDirectory: false)

		func isNoSuchFileError(error: CarthageError) -> Bool {
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
		
		let cartfile = SignalProducer.attempt {
				return Cartfile.from(file: cartfileURL)
			}
			.flatMapError { error -> SignalProducer<Cartfile, CarthageError> in
				if isNoSuchFileError(error) && FileManager.`default`.fileExists(atPath: privateCartfileURL.carthage_path) {
					return SignalProducer(value: Cartfile())
				}

				return SignalProducer(error: error)
			}

		let privateCartfile = SignalProducer.attempt {
				return Cartfile.from(file: privateCartfileURL)
			}
			.flatMapError { error -> SignalProducer<Cartfile, CarthageError> in
				if isNoSuchFileError(error) {
					return SignalProducer(value: Cartfile())
				}

				return SignalProducer(error: error)
			}

		return SignalProducer.zip(cartfile, privateCartfile)
			.attemptMap { cartfile, privateCartfile -> Result<Cartfile, CarthageError> in
				var cartfile = cartfile

				let duplicateDeps = duplicateProjectsIn(cartfile, privateCartfile).map { DuplicateDependency(project: $0, locations: ["\(CarthageProjectCartfilePath)", "\(CarthageProjectPrivateCartfilePath)"]) }

				if duplicateDeps.isEmpty {
					cartfile.append(privateCartfile)
					return .success(cartfile)
				}

				return .failure(.duplicateDependencies(duplicateDeps))
			}
	}

	/// Reads the project's Cartfile.resolved.
	public func loadResolvedCartfile() -> SignalProducer<ResolvedCartfile, CarthageError> {
		return SignalProducer.attempt {
			do {
				let resolvedCartfileContents = try String(contentsOf: self.resolvedCartfileURL, encoding: .utf8)
				return ResolvedCartfile.from(string: resolvedCartfileContents)
			} catch let error as NSError {
				return .failure(.readFailed(self.resolvedCartfileURL, error))
			}
		}
	}

	/// Writes the given Cartfile.resolved out to the project's directory.
	public func writeResolvedCartfile(resolvedCartfile: ResolvedCartfile) -> Result<(), CarthageError> {
		do {
			try resolvedCartfile.description.write(to: resolvedCartfileURL, atomically: true, encoding: .utf8)
			return .success(())
		} catch let error as NSError {
			return .failure(.writeFailed(resolvedCartfileURL, error))
		}
	}

	/// Produces the sub dependencies of the given dependency
	func dependencyProjectsForDependency(dependency: Dependency<PinnedVersion>) -> SignalProducer<Set<ProjectIdentifier>, CarthageError> {
		return self.dependencies(for: dependency)
			.map { $0.project }
			.collect()
			.map { Set($0) }
			.concat(SignalProducer(value: Set()))
			.take(first: 1)
	}

	private let gitOperationQueue = ProducerQueue(name: "org.carthage.CarthageKit.Project.gitOperationQueue")

	/// Clones the given dependency to the global repositories folder, or fetches
	/// inside it if it has already been cloned.
	///
	/// Returns a signal which will send the URL to the repository's folder on
	/// disk once cloning or fetching has completed.
	private func cloneOrFetchDependency(project: ProjectIdentifier, commitish: String? = nil) -> SignalProducer<URL, CarthageError> {
		return cloneOrFetchProject(project, preferHTTPS: self.preferHTTPS, commitish: commitish)
			.on(next: { event, _ in
				if let event = event {
					self._projectEventsObserver.send(value: event)
				}
			})
			.map { _, url in url }
			.take(last: 1)
			.startOnQueue(gitOperationQueue)
	}

	/// Sends all versions available for the given project.
	///
	/// This will automatically clone or fetch the project's repository as
	/// necessary.
	private func versions(for project: ProjectIdentifier) -> SignalProducer<PinnedVersion, CarthageError> {
		let fetchVersions = cloneOrFetchDependency(project)
			.flatMap(.merge) { repositoryURL in listTags(repositoryURL) }
			.map { PinnedVersion($0) }
			.collect()
			.on(next: { newVersions in
				self.cachedVersions[project] = newVersions
			})
			.flatMap(.concat) { versions in SignalProducer<PinnedVersion, CarthageError>(versions) }

		return SignalProducer.attempt {
				return .success(self.cachedVersions)
			}
			.flatMap(.merge) { versionsByProject -> SignalProducer<PinnedVersion, CarthageError> in
				if let versions = versionsByProject[project] {
					return SignalProducer(versions)
				} else {
					return fetchVersions
				}
			}
			.startOnQueue(cachedVersionsQueue)
			.collect()
			.flatMap(.concat) { versions -> SignalProducer<PinnedVersion, CarthageError> in
				if versions.isEmpty {
					return SignalProducer(error: .taggedVersionNotFound(project))
				}
				
				return SignalProducer(versions)
			}
	}
	
	/// Loads the dependencies for the given dependency, at the given version.
	private func dependencies(for dependency: Dependency<PinnedVersion>) -> SignalProducer<Dependency<VersionSpecifier>, CarthageError> {
		let revision = dependency.version.commitish
		return self.cloneOrFetchDependency(dependency.project, commitish: revision)
			.flatMap(.concat) { repositoryURL in
				return contentsOfFileInRepository(repositoryURL, CarthageProjectCartfilePath, revision: revision)
			}
			.flatMapError { _ in .empty }
			.attemptMap(Cartfile.from(string:))
			.flatMap(.concat) { cartfile -> SignalProducer<Dependency<VersionSpecifier>, CarthageError> in
				return SignalProducer(Array(cartfile.dependencies))
			}
	}

	/// Attempts to resolve a Git reference to a version.
	private func resolvedGitReference(project: ProjectIdentifier, reference: String) -> SignalProducer<PinnedVersion, CarthageError> {
		let repositoryURL = repositoryFileURLForProject(project)
		return cloneOrFetchDependency(project, commitish: reference)
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
	public func updatedResolvedCartfile(dependenciesToUpdate: [String]? = nil) -> SignalProducer<ResolvedCartfile, CarthageError> {
		let resolver = Resolver(versionsForDependency: versions(for:), dependenciesForDependency: dependencies(for:), resolvedGitReference: resolvedGitReference)

		let resolvedCartfile: SignalProducer<ResolvedCartfile?, CarthageError> = loadResolvedCartfile()
			.map(Optional.init)
			.flatMapError { _ in .init(value: nil) }

		return SignalProducer
			.zip(loadCombinedCartfile(), resolvedCartfile)
			.flatMap(.merge) { cartfile, resolvedCartfile in
				return resolver.resolve(dependencies: cartfile.dependencies, lastResolved: resolvedCartfile, dependenciesToUpdate: dependenciesToUpdate)
			}
			.collect()
			.map(ResolvedCartfile.init)
	}
	
	/// Attempts to determine which of the project's Carthage
	/// dependencies are out of date.
	///
	/// This will fetch dependency repositories as necessary, but will not check
	/// them out into the project's working directory.
	public func outdatedDependencies(includeNestedDependencies: Bool) -> SignalProducer<[(Dependency<PinnedVersion>, Dependency<PinnedVersion>)], CarthageError> {
		typealias PinnedDependency = Dependency<PinnedVersion>
		typealias OutdatedDependency = (PinnedDependency, PinnedDependency)

		let currentDependencies = loadResolvedCartfile()
			.map { $0.dependencies }
		let updatedDependencies = updatedResolvedCartfile()
			.map { $0.dependencies }
		let outdatedDependencies = SignalProducer.combineLatest(currentDependencies, updatedDependencies)
			.map { (currentDependencies, updatedDependencies) -> [OutdatedDependency] in
				var currentDependenciesDictionary = [ProjectIdentifier: PinnedDependency]()
				for dependency in currentDependencies {
					currentDependenciesDictionary[dependency.project] = dependency
				}

				return updatedDependencies.flatMap { updated -> OutdatedDependency? in
					if let resolved = currentDependenciesDictionary[updated.project] where resolved.version != updated.version {
						return (resolved, updated)
					} else {
						return nil
					}
				}
			}

		if includeNestedDependencies {
			return outdatedDependencies
		}

		let explicitDependencyProjects = loadCombinedCartfile()
			.map { $0.dependencies.map { $0.project } }

		return SignalProducer.combineLatest(outdatedDependencies, explicitDependencyProjects)
			.map { (oudatedDependencies, explicitDependencyProjects) -> [OutdatedDependency] in
				return oudatedDependencies.filter { resolved, updated in
					return explicitDependencyProjects.contains(resolved.project)
				}
		}
	}

	/// Updates the dependencies of the project to the latest version. The
	/// changes will be reflected in Cartfile.resolved, and also in the working
	/// directory checkouts if the given parameter is true.
	public func updateDependencies(shouldCheckout shouldCheckout: Bool = true, dependenciesToUpdate: [String]? = nil) -> SignalProducer<(), CarthageError> {
		return updatedResolvedCartfile(dependenciesToUpdate)
			.attemptMap { resolvedCartfile -> Result<(), CarthageError> in
				return self.writeResolvedCartfile(resolvedCartfile)
			}
			.then(shouldCheckout ? checkoutResolvedDependencies(dependenciesToUpdate) : .empty)
	}

	/// Installs binaries and debug symbols for the given project, if available.
	///
	/// Sends a boolean indicating whether binaries were installed.
	private func installBinariesForProject(project: ProjectIdentifier, atRevision revision: String) -> SignalProducer<Bool, CarthageError> {
		return SignalProducer.attempt {
				return .success(self.useBinaries)
			}
			.flatMap(.merge) { useBinaries -> SignalProducer<Bool, CarthageError> in
				if !useBinaries {
					return SignalProducer(value: false)
				}

				let checkoutDirectoryURL = self.directoryURL.appendingPathComponent(project.relativePath, isDirectory: true)

				switch project {
				case let .gitHub(repository):
					let client = Client(repository: repository)
					return self.downloadMatchingBinariesForProject(project, atRevision: revision, fromRepository: repository, client: client)
						.flatMapError { error -> SignalProducer<URL, CarthageError> in
							if !client.isAuthenticated {
								return SignalProducer(error: error)
							}
							return self.downloadMatchingBinariesForProject(project, atRevision: revision, fromRepository: repository, client: Client(repository: repository, isAuthenticated: false))
						}
						.flatMap(.concat, transform: unzip(archive:))
						.flatMap(.concat) { directoryURL in
							return frameworksInDirectory(directoryURL)
								.flatMap(.merge, transform: self.copyFrameworkToBuildFolder)
								.flatMap(.merge) { frameworkURL in
									return self.copyDSYMToBuildFolderForFramework(frameworkURL, fromDirectoryURL: directoryURL)
										.then(self.copyBCSymbolMapsToBuildFolderForFramework(frameworkURL, fromDirectoryURL: directoryURL))
								}
								.on(completed: {
									_ = try? FileManager.`default`.trashItem(at: checkoutDirectoryURL, resultingItemURL: nil)
								})
								.then(SignalProducer(value: directoryURL))
						}
						.attemptMap { (temporaryDirectoryURL: URL) -> Result<Bool, CarthageError> in
							do {
								try FileManager.`default`.removeItem(at: temporaryDirectoryURL)
								return .success(true)
							} catch let error as NSError {
								return .failure(.writeFailed(temporaryDirectoryURL, error))
							}
						}
						.concat(SignalProducer(value: false))
						.take(first: 1)

				case .git:
					return SignalProducer(value: false)
				}
			}
	}

	/// Downloads any binaries and debug symbols that may be able to be used 
	/// instead of a repository checkout.
	///
	/// Sends the URL to each downloaded zip, after it has been moved to a
	/// less temporary location.
	private func downloadMatchingBinariesForProject(project: ProjectIdentifier, atRevision revision: String, fromRepository repository: Repository, client: Client) -> SignalProducer<URL, CarthageError> {
		return client.release(forTag: revision, in: repository)
			.map { _, release in release }
			.filter { release in
				return !release.isDraft && !release.assets.isEmpty
			}
			.flatMapError { error -> SignalProducer<Release, CarthageError> in
				switch error {
				case .DoesNotExist:
					return .empty
					
				case let .APIError(_, _, error):
					// Log the GitHub API request failure, not to error out,
					// because that should not be fatal error.
					self._projectEventsObserver.send(value: .skippedDownloadingBinaries(project, error.message))
					return .empty

				default:
					return SignalProducer(error: .gitHubAPIRequestFailed(error))
				}
			}
			.on(next: { release in
				self._projectEventsObserver.send(value: .downloadingBinaries(project, release.nameWithFallback))
			})
			.flatMap(.concat) { release -> SignalProducer<URL, CarthageError> in
				return SignalProducer<Release.Asset, CarthageError>(release.assets)
					.filter { asset in
						if asset.name.range(of: CarthageProjectBinaryAssetPattern) == nil {
							return false
						}
						return CarthageProjectBinaryAssetContentTypes.contains(asset.contentType)
					}
					.flatMap(.concat) { asset -> SignalProducer<URL, CarthageError> in
						let fileURL = fileURLToCachedBinary(project, release, asset)

						if FileManager.`default`.fileExists(atPath: fileURL.carthage_path) {
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
	private func copyFrameworkToBuildFolder(frameworkURL: URL) -> SignalProducer<URL, CarthageError> {
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
	public func copyDSYMToBuildFolderForFramework(frameworkURL: URL, fromDirectoryURL directoryURL: URL) -> SignalProducer<URL, CarthageError> {
		let destinationDirectoryURL = frameworkURL.deletingLastPathComponent()
		return dSYMForFramework(frameworkURL, inDirectoryURL:directoryURL)
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
	public func copyBCSymbolMapsToBuildFolderForFramework(frameworkURL: URL, fromDirectoryURL directoryURL: URL) -> SignalProducer<URL, CarthageError> {
		let destinationDirectoryURL = frameworkURL.deletingLastPathComponent()
		return BCSymbolMapsForFramework(frameworkURL, inDirectoryURL: directoryURL)
			.copyFileURLsIntoDirectory(destinationDirectoryURL)
	}

	/// Checks out the given dependency into its intended working directory,
	/// cloning it first if need be.
	private func checkoutOrCloneDependency(dependency: Dependency<PinnedVersion>, submodulesByPath: [String: Submodule]) -> SignalProducer<(), CarthageError> {
		let project = dependency.project
		let revision = dependency.version.commitish
		return cloneOrFetchDependency(project, commitish: revision)
			.flatMap(.merge) { repositoryURL -> SignalProducer<(), CarthageError> in
				let workingDirectoryURL = self.directoryURL.appendingPathComponent(project.relativePath, isDirectory: true)
				var submodule: Submodule?
				
				if var foundSubmodule = submodulesByPath[project.relativePath] {
					foundSubmodule.url = repositoryURLForProject(project, preferHTTPS: self.preferHTTPS)
					foundSubmodule.sha = revision
					submodule = foundSubmodule
				} else if self.useSubmodules {
					submodule = Submodule(name: project.relativePath, path: project.relativePath, url: repositoryURLForProject(project, preferHTTPS: self.preferHTTPS), sha: revision)
				}
				
				if let submodule = submodule {
					return addSubmoduleToRepository(self.directoryURL, submodule, GitURL(repositoryURL.carthage_path))
						.startOnQueue(self.gitOperationQueue)
				} else {
					return checkoutRepositoryToDirectory(repositoryURL, workingDirectoryURL, revision: revision)
						.then(self.dependencyProjectsForDependency(dependency))
						.flatMap(.merge) { dependencies in
							return self.symlinkCheckoutPathsForDependencyProject(dependency.project, subDependencies: dependencies, rootDirectoryURL: self.directoryURL)
						}
				}
			}
			.on(started: {
				self._projectEventsObserver.send(value: .checkingOut(project, revision))
			})
	}
	
	public func buildOrderForResolvedCartfile(cartfile: ResolvedCartfile, dependenciesToInclude: [String]? = nil) -> SignalProducer<Dependency<PinnedVersion>, CarthageError> {
		typealias DependencyGraph = [ProjectIdentifier: Set<ProjectIdentifier>]
		// A resolved cartfile already has all the recursive dependencies. All we need to do is sort
		// out the relationships between them. Loading the cartfile will each will give us its
		// dependencies. Building a recursive lookup table with this information will let us sort
		// dependencies before the projects that depend on them.
		return SignalProducer<Dependency<PinnedVersion>, CarthageError>(cartfile.dependencies)
			.flatMap(.merge) { (dependency: Dependency<PinnedVersion>) -> SignalProducer<DependencyGraph, CarthageError> in
				return self.dependencyProjectsForDependency(dependency)
					.map { dependencies in
						[dependency.project: dependencies]
					}
			}
			.reduce([:]) { (working: DependencyGraph, next: DependencyGraph) in
				var result = working
				next.forEach { result.updateValue($1, forKey: $0) }
				return result
			}
			.flatMap(.latest) { (graph: DependencyGraph) -> SignalProducer<Dependency<PinnedVersion>, CarthageError> in
				let projectsToInclude = Set(graph
					.map { project, _ in project }
					.filter { project in dependenciesToInclude?.contains(project.name) ?? false })

				guard let sortedProjects = topologicalSort(graph, nodes: projectsToInclude) else {
					return SignalProducer(error: .dependencyCycle(graph))
				}

				let sortedDependencies = cartfile.dependencies
					.filter { dependency in sortedProjects.contains(dependency.project) }
					.sort { left, right in sortedProjects.index(of: left.project) < sortedProjects.index(of: right.project) }

				return SignalProducer(sortedDependencies)
			}
	}

	/// Checks out the dependencies listed in the project's Cartfile.resolved,
	/// optionally they are limited by the given list of dependency names.
	public func checkoutResolvedDependencies(dependenciesToCheckout: [String]? = nil) -> SignalProducer<(), CarthageError> {
		/// Determine whether the repository currently holds any submodules (if
		/// it even is a repository).
		let submodulesSignal = submodulesInRepository(self.directoryURL)
			.reduce([:]) { (submodulesByPath: [String: Submodule], submodule) in
				var submodulesByPath = submodulesByPath
				submodulesByPath[submodule.path] = submodule
				return submodulesByPath
			}
		
		return loadResolvedCartfile()
			.flatMap(.merge) { resolvedCartfile in
				return self
					.buildOrderForResolvedCartfile(resolvedCartfile, dependenciesToInclude: dependenciesToCheckout)
					.collect()
			}
			.zip(with: submodulesSignal)
			.flatMap(.merge) { dependencies, submodulesByPath -> SignalProducer<(), CarthageError> in
				return SignalProducer<Dependency<PinnedVersion>, CarthageError>(dependencies)
					.flatMap(.concat) { dependency -> SignalProducer<(), CarthageError> in
						let project = dependency.project

						let submoduleFound = submodulesByPath[project.relativePath] != nil
						let checkoutOrCloneDependency = self.checkoutOrCloneDependency(dependency, submodulesByPath: submodulesByPath)

						// Disable binary downloads for the dependency if that
						// is already checked out as a submodule.
						if submoduleFound {
							return checkoutOrCloneDependency
						}

						return self.installBinariesForProject(project, atRevision: dependency.version.commitish)
							.flatMap(.merge) { installed -> SignalProducer<(), CarthageError> in
								if installed {
									return .empty
								} else {
									return checkoutOrCloneDependency
								}
							}
					}
			}
			.then(.empty)
	}

	/// Creates symlink between the dependency checkouts and the root checkouts
	private func symlinkCheckoutPathsForDependencyProject(dependency: ProjectIdentifier, subDependencies: Set<ProjectIdentifier>, rootDirectoryURL: URL) -> SignalProducer<(), CarthageError> {
		let rootCheckoutsURL = rootDirectoryURL.appendingPathComponent(CarthageProjectCheckoutsPath, isDirectory: true).resolvingSymlinksInPath()
		let rawDependencyURL = rootDirectoryURL.appendingPathComponent(dependency.relativePath, isDirectory: true)
		let dependencyURL = rawDependencyURL.resolvingSymlinksInPath()
		let dependencyCheckoutsURL = dependencyURL.appendingPathComponent(CarthageProjectCheckoutsPath, isDirectory: true).resolvingSymlinksInPath()
		let subDependencyNames = subDependencies.map { $0.name }
		let fileManager = FileManager.`default`

		let symlinksProducer = SignalProducer(subDependencyNames)
			.filter { name in
				let checkoutURL = rootCheckoutsURL.appendingPathComponent(name)
				do {
					return try checkoutURL.resourceValues(forKeys: [ .isDirectoryKey ]).isDirectory ?? false
				} catch {
					return false
				}
			}
			.attemptMap { name -> Result<(), CarthageError> in
				let dependencyCheckoutURL = dependencyCheckoutsURL.appendingPathComponent(name)
				let subdirectoryPath = (CarthageProjectCheckoutsPath as NSString).appendingPathComponent(name)
				let linkDestinationPath = relativeLinkDestinationForDependencyProject(dependency, subdirectory: subdirectoryPath)
				do {
					try fileManager.createSymbolicLink(atPath: dependencyCheckoutURL.carthage_path, withDestinationPath: linkDestinationPath)
				} catch let error as NSError {
					if !(error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError) {
						return .failure(.writeFailed(dependencyCheckoutURL, error))
					}
				}
				return .success()
		}


		return SignalProducer<(), CarthageError>
			.attempt {
				do {
					try fileManager.createDirectory(at: dependencyCheckoutsURL, withIntermediateDirectories: true)
				} catch let error as NSError {
					if !(error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError) {
						return .failure(.writeFailed(dependencyCheckoutsURL, error))
					}
				}
				return .success()
			}
			.then(symlinksProducer)
	}

	/// Attempts to build each Carthage dependency that has been checked out,
	/// optionally they are limited by the given list of dependency names.
	///
	/// Returns a producer-of-producers representing each scheme being built.
	public func buildCheckedOutDependenciesWithOptions(options: BuildOptions, dependenciesToBuild: [String]? = nil, sdkFilter: SDKFilterCallback = { .success($0.0) }) -> SignalProducer<BuildSchemeProducer, CarthageError> {
		return loadResolvedCartfile()
			.flatMap(.merge) { resolvedCartfile in
				return self.buildOrderForResolvedCartfile(resolvedCartfile, dependenciesToInclude: dependenciesToBuild)
			}
			.flatMap(.concat) { dependency -> SignalProducer<BuildSchemeProducer, CarthageError> in
				let dependencyPath = self.directoryURL.appendingPathComponent(dependency.project.relativePath, isDirectory: true).carthage_path
				if !FileManager.`default`.fileExists(atPath: dependencyPath) {
					return .empty
				}

				return buildDependencyProject(dependency.project, self.directoryURL, withOptions: options, sdkFilter: sdkFilter)
					.flatMapError { error in
						switch error {
						case .noSharedFrameworkSchemes:
							// Log that building the dependency is being skipped,
							// not to error out with `.noSharedFrameworkSchemes`
							// to continue building other dependencies.
							self._projectEventsObserver.send(value: .skippedBuilding(dependency.project, error.description))
							return .empty

						default:
							return SignalProducer(error: error)
						}
					}
			}
	}
}

/// Constructs a file URL to where the binary corresponding to the given
/// arguments should live.
private func fileURLToCachedBinary(project: ProjectIdentifier, _ release: Release, _ asset: Release.Asset) -> URL {
	// ~/Library/Caches/org.carthage.CarthageKit/binaries/ReactiveCocoa/v2.3.1/1234-ReactiveCocoa.framework.zip
	return CarthageDependencyAssetsURL.appendingPathComponent("\(project.name)/\(release.tag)/\(asset.ID)-\(asset.name)", isDirectory: false)
}

/// Caches the downloaded binary at the given URL, moving it to the other URL
/// given.
///
/// Sends the final file URL upon .success.
private func cacheDownloadedBinary(downloadURL: URL, toURL cachedURL: URL) -> SignalProducer<URL, CarthageError> {
	return SignalProducer(value: cachedURL)
		.attempt { fileURL in
			let parentDirectoryURL = fileURL.deletingLastPathComponent()
			do {
				try FileManager.`default`.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)
				return .success(())
			} catch let error as NSError {
				return .failure(.writeFailed(parentDirectoryURL, error))
			}
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
			do {
				try FileManager.`default`.moveItem(at: downloadURL, to: newDownloadURL)
				return .success(())
			} catch let error as NSError {
				return .failure(.writeFailed(newDownloadURL, error))
			}
		}
}

/// Sends the URL to each file found in the given directory conforming to the
/// given type identifier. If no type identifier is provided, all files are sent.
private func filesInDirectory(directoryURL: URL, _ typeIdentifier: String? = nil) -> SignalProducer<URL, CarthageError> {
	let producer = FileManager.`default`.carthage_enumerator(at: directoryURL, includingPropertiesForKeys: [ .typeIdentifierKey ], options: [ .skipsHiddenFiles, .skipsPackageDescendants ], catchErrors: true)
		.map { enumerator, url in url }
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
private func platformForFramework(frameworkURL: URL) -> SignalProducer<Platform, CarthageError> {
	return SignalProducer(value: frameworkURL)
		// Neither DTPlatformName nor CFBundleSupportedPlatforms can not be used
		// because Xcode 6 and below do not include either in macOS frameworks.
		.attemptMap { url -> Result<String, CarthageError> in
			let bundle = Bundle(url: url)

			func readFailed(message: String) -> CarthageError {
				let error = Result<(), NSError>.error(message)
				return .readFailed(frameworkURL, error)
			}

			guard let sdkName = bundle?.object(forInfoDictionaryKey: "DTSDKName") else {
				return .failure(readFailed("the DTSDKName key in its plist file is missing"))
			}

			if let sdkName = sdkName as? String {
				return .success(sdkName)
			} else {
				return .failure(readFailed("the value for the DTSDKName key in its plist file is not a string"))
			}
		}
		// Thus, the SDK name must be trimmed to match the platform name, e.g.
		// macosx10.10 -> macosx
		.map { sdkName in sdkName.trimmingCharacters(in: CharacterSet.letters.inverted) }
		.attemptMap { platform in SDK.fromString(platform).map { $0.platform } }
}

/// Sends the URL to each framework bundle found in the given directory.
private func frameworksInDirectory(directoryURL: URL) -> SignalProducer<URL, CarthageError> {
	return filesInDirectory(directoryURL, kUTTypeFramework as String)
		.filter { url in
			// Skip nested frameworks
			let frameworksInURL = url.carthage_pathComponents.filter { pathComponent in
				return (pathComponent as NSString).pathExtension == "framework"
			}
			return frameworksInURL.count == 1
		}
}

/// Sends the URL to each dSYM found in the given directory
private func dSYMsInDirectory(directoryURL: URL) -> SignalProducer<URL, CarthageError> {
	return filesInDirectory(directoryURL, "com.apple.xcode.dsym")
}

/// Sends the URL of the dSYM whose UUIDs match those of the given framework, or
/// errors if there was an error parsing a dSYM contained within the directory.
private func dSYMForFramework(frameworkURL: URL, inDirectoryURL directoryURL: URL) -> SignalProducer<URL, CarthageError> {
	return UUIDsForFramework(frameworkURL)
		.flatMap(.concat) { frameworkUUIDs in
			return dSYMsInDirectory(directoryURL)
				.flatMap(.merge) { dSYMURL in
					return UUIDsForDSYM(dSYMURL)
						.filter { dSYMUUIDs in
							return dSYMUUIDs == frameworkUUIDs
						}
						.map { _ in dSYMURL }
				}
		}
		.take(first: 1)
}

/// Sends the URL to each bcsymbolmap found in the given directory.
private func BCSymbolMapsInDirectory(directoryURL: URL) -> SignalProducer<URL, CarthageError> {
	return filesInDirectory(directoryURL)
		.filter { url in url.pathExtension == "bcsymbolmap" }
}

/// Sends the URLs of the bcsymbolmap files that match the given framework and are
/// located somewhere within the given directory.
private func BCSymbolMapsForFramework(frameworkURL: URL, inDirectoryURL directoryURL: URL) -> SignalProducer<URL, CarthageError> {
	return UUIDsForFramework(frameworkURL)
		.flatMap(.merge) { uuids -> SignalProducer<URL, CarthageError> in
			if uuids.isEmpty {
				return .empty
			}
			func filterUUIDs(signal: Signal<URL, CarthageError>) -> Signal<URL, CarthageError> {
				var remainingUUIDs = uuids
				let count = remainingUUIDs.count
				return signal
					.filter { fileURL in
						let basename = fileURL.deletingPathExtension().carthage_lastPathComponent
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
private func repositoryFileURLForProject(project: ProjectIdentifier, baseURL: URL = CarthageDependencyRepositoriesURL) -> URL {
	return baseURL.appendingPathComponent(project.name, isDirectory: true)
}


/// Returns the URL that the project's remote repository exists at.
private func repositoryURLForProject(project: ProjectIdentifier, preferHTTPS: Bool) -> GitURL {
	switch project {
	case let .gitHub(repository):
		if preferHTTPS {
			return repository.httpsURL
		} else {
			return repository.sshURL
		}

	case let .git(url):
		return url
	}
}

/// Returns the string representing a relative path from a dependency project back to the root
internal func relativeLinkDestinationForDependencyProject(dependency: ProjectIdentifier, subdirectory: String) -> String {
	let dependencySubdirectoryPath = (dependency.relativePath as NSString).appendingPathComponent(subdirectory)
	let componentsForGettingTheHellOutOfThisRelativePath = Array(count: (dependencySubdirectoryPath as NSString).pathComponents.count - 1, repeatedValue: "..")

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
public func cloneOrFetchProject(project: ProjectIdentifier, preferHTTPS: Bool, destinationURL: URL = CarthageDependencyRepositoriesURL, commitish: String? = nil) -> SignalProducer<(ProjectEvent?, URL), CarthageError> {
	let fileManager = FileManager.`default`
	let repositoryURL = repositoryFileURLForProject(project, baseURL: destinationURL)

	return SignalProducer.attempt { () -> Result<GitURL, CarthageError> in
			do {
				try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
			} catch let error as NSError {
				return .failure(.writeFailed(destinationURL, error))
			}

			return .success(repositoryURLForProject(project, preferHTTPS: preferHTTPS))
		}
		.flatMap(.merge) { remoteURL -> SignalProducer<(ProjectEvent?, URL), CarthageError> in
			return isGitRepository(repositoryURL)
				.flatMap(.merge) { isRepository -> SignalProducer<(ProjectEvent?, URL), CarthageError> in
					if isRepository {
						let fetchProducer: () -> SignalProducer<(ProjectEvent?, URL), CarthageError> = {
							guard FetchCache.needsFetch(forURL: remoteURL) else {
								return SignalProducer(value: (nil, repositoryURL))
							}

							return SignalProducer(value: (.fetching(project), repositoryURL))
								.concat(fetchRepository(repositoryURL, remoteURL: remoteURL, refspec: "+refs/heads/*:refs/heads/*").then(.empty))
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
						return SignalProducer(value: (.cloning(project), repositoryURL))
							.concat(cloneRepository(remoteURL, repositoryURL).then(.empty))
					}
			}
		}
}
