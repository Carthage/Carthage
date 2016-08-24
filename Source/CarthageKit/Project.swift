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

/// Carthage’s bundle identifier.
public let CarthageKitBundleIdentifier = NSBundle(forClass: Project.self).bundleIdentifier!

/// The fallback dependencies URL to be used in case
/// the intended ~/Library/Caches/org.carthage.CarthageKit cannot
/// be found or created.
private let fallbackDependenciesURL: NSURL = {
	let homePath: String
	if let homeEnvValue = NSProcessInfo.processInfo().environment["HOME"] {
		homePath = (homeEnvValue as NSString).stringByAppendingPathComponent(".carthage")
	} else {
		homePath = ("~/.carthage" as NSString).stringByExpandingTildeInPath
	}
	return NSURL.fileURLWithPath(homePath, isDirectory:true)
}()

/// ~/Library/Caches/org.carthage.CarthageKit/
private let CarthageUserCachesURL: NSURL = {
	let fileManager = NSFileManager.defaultManager()
	
	let URLResult: Result<NSURL, NSError> = `try` { (error: NSErrorPointer) -> NSURL? in
		return try? fileManager.URLForDirectory(NSSearchPathDirectory.CachesDirectory, inDomain: NSSearchPathDomainMask.UserDomainMask, appropriateForURL: nil, create: true)
	}.flatMap { cachesURL in
		let dependenciesURL = cachesURL.appendingPathComponent(CarthageKitBundleIdentifier, isDirectory: true)
		let dependenciesPath = dependenciesURL.carthage_absoluteString
		
		if fileManager.fileExistsAtPath(dependenciesPath, isDirectory:nil) {
			if fileManager.isWritableFileAtPath(dependenciesPath) {
				return Result(value: dependenciesURL)
			} else {
				let error = NSError(domain: CarthageKitBundleIdentifier, code: 0, userInfo: nil)
				return Result(error: error)
			}
		} else {
			return Result(attempt: {
				try fileManager.createDirectoryAtURL(dependenciesURL, withIntermediateDirectories: true, attributes: [NSFilePosixPermissions : 0o755])
				return dependenciesURL
			})
		}
	}

	switch URLResult {
	case let .Success(URL):
		_ = try? NSFileManager.defaultManager().removeItemAtURL(fallbackDependenciesURL)
		return URL
	case let .Failure(error):
		NSLog("Warning: No Caches directory could be found or created: \(error.localizedDescription). (\(error))")
		return fallbackDependenciesURL
	}
}()

/// The file URL to the directory in which downloaded release binaries will be
/// stored.
///
/// ~/Library/Caches/org.carthage.CarthageKit/binaries/
public let CarthageDependencyAssetsURL: NSURL = CarthageUserCachesURL.appendingPathComponent("binaries", isDirectory: true)

/// The file URL to the directory in which cloned dependencies will be stored.
///
/// ~/Library/Caches/org.carthage.CarthageKit/dependencies/
public let CarthageDependencyRepositoriesURL: NSURL = CarthageUserCachesURL.appendingPathComponent("dependencies", isDirectory: true)

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
	case Cloning(ProjectIdentifier)

	/// The project is beginning a fetch.
	case Fetching(ProjectIdentifier)
	
	/// The project is being checked out to the specified revision.
	case CheckingOut(ProjectIdentifier, String)

	/// Any available binaries for the specified release of the project are
	/// being downloaded. This may still be followed by `CheckingOut` event if
	/// there weren't any viable binaries after all.
	case DownloadingBinaries(ProjectIdentifier, String)

	/// Downloading any available binaries of the project is being skipped,
	/// because of a GitHub API request failure which is due to authentication
	/// or rate-limiting.
	case SkippedDownloadingBinaries(ProjectIdentifier, String)

	/// Building the project is being skipped, since the project is not sharing
	/// any framework schemes.
	case SkippedBuilding(ProjectIdentifier, String)
}

/// Represents a project that is using Carthage.
public final class Project {
	/// File URL to the root directory of the project.
	public let directoryURL: NSURL

	/// The file URL to the project's Cartfile.
	public var cartfileURL: NSURL {
		return directoryURL.appendingPathComponent(CarthageProjectCartfilePath, isDirectory: false)
	}

	/// The file URL to the project's Cartfile.resolved.
	public var resolvedCartfileURL: NSURL {
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

	public init(directoryURL: NSURL) {
		precondition(directoryURL.fileURL)

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
			case let .ReadFailed(_, underlyingError):
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
				return Cartfile.fromFile(cartfileURL)
			}
			.flatMapError { error -> SignalProducer<Cartfile, CarthageError> in
				if isNoSuchFileError(error) && NSFileManager.defaultManager().fileExistsAtPath(privateCartfileURL.path!) {
					return SignalProducer(value: Cartfile())
				}

				return SignalProducer(error: error)
			}

		let privateCartfile = SignalProducer.attempt {
				return Cartfile.fromFile(privateCartfileURL)
			}
			.flatMapError { error -> SignalProducer<Cartfile, CarthageError> in
				if isNoSuchFileError(error) {
					return SignalProducer(value: Cartfile())
				}

				return SignalProducer(error: error)
			}

		return zip(cartfile, privateCartfile)
			.attemptMap { cartfile, privateCartfile -> Result<Cartfile, CarthageError> in
				var cartfile = cartfile

				let duplicateDeps = cartfile.duplicateProjects().map { DuplicateDependency(project: $0, locations: ["\(CarthageProjectCartfilePath)"]) }
					+ privateCartfile.duplicateProjects().map { DuplicateDependency(project: $0, locations: ["\(CarthageProjectPrivateCartfilePath)"]) }
					+ duplicateProjectsInCartfiles(cartfile, privateCartfile).map { DuplicateDependency(project: $0, locations: ["\(CarthageProjectCartfilePath)", "\(CarthageProjectPrivateCartfilePath)"]) }

				if duplicateDeps.count == 0 {
					cartfile.appendCartfile(privateCartfile)
					return .Success(cartfile)
				}

				return .Failure(.DuplicateDependencies(duplicateDeps))
			}
	}

	/// Reads the project's Cartfile.resolved.
	public func loadResolvedCartfile() -> SignalProducer<ResolvedCartfile, CarthageError> {
		return SignalProducer.attempt {
			do {
				let resolvedCartfileContents = try NSString(contentsOfURL: self.resolvedCartfileURL, encoding: NSUTF8StringEncoding)
				return ResolvedCartfile.fromString(resolvedCartfileContents as String)
			} catch let error as NSError {
				return .Failure(.ReadFailed(self.resolvedCartfileURL, error))
			}
		}
	}

	/// Writes the given Cartfile.resolved out to the project's directory.
	public func writeResolvedCartfile(resolvedCartfile: ResolvedCartfile) -> Result<(), CarthageError> {
		do {
			try resolvedCartfile.description.writeToURL(resolvedCartfileURL, atomically: true, encoding: NSUTF8StringEncoding)
			return .Success(())
		} catch let error as NSError {
			return .Failure(.WriteFailed(resolvedCartfileURL, error))
		}
	}

	private let gitOperationQueue = ProducerQueue(name: "org.carthage.CarthageKit.Project.gitOperationQueue")

	/// Clones the given dependency to the global repositories folder, or fetches
	/// inside it if it has already been cloned.
	///
	/// Returns a signal which will send the URL to the repository's folder on
	/// disk once cloning or fetching has completed.
	private func cloneOrFetchDependency(project: ProjectIdentifier, commitish: String? = nil) -> SignalProducer<NSURL, CarthageError> {
		return cloneOrFetchProject(project, preferHTTPS: self.preferHTTPS, commitish: commitish)
			.on(next: { event, _ in
				if let event = event {
					self._projectEventsObserver.sendNext(event)
				}
			})
			.map { _, URL in URL }
			.takeLast(1)
			.startOnQueue(gitOperationQueue)
	}

	/// Sends all versions available for the given project.
	///
	/// This will automatically clone or fetch the project's repository as
	/// necessary.
	private func versionsForProject(project: ProjectIdentifier) -> SignalProducer<PinnedVersion, CarthageError> {
		let fetchVersions = cloneOrFetchDependency(project)
			.flatMap(.Merge) { repositoryURL in listTags(repositoryURL) }
			.map { PinnedVersion($0) }
			.collect()
			.on(next: { newVersions in
				self.cachedVersions[project] = newVersions
			})
			.flatMap(.Concat) { versions in SignalProducer<PinnedVersion, CarthageError>(values: versions) }

		return SignalProducer.attempt {
				return .Success(self.cachedVersions)
			}
			.flatMap(.Merge) { versionsByProject -> SignalProducer<PinnedVersion, CarthageError> in
				if let versions = versionsByProject[project] {
					return SignalProducer(values: versions)
				} else {
					return fetchVersions
				}
			}
			.startOnQueue(cachedVersionsQueue)
			.collect()
			.flatMap(.Concat) { versions -> SignalProducer<PinnedVersion, CarthageError> in
				if versions.isEmpty {
					return SignalProducer(error: .TaggedVersionNotFound(project))
				}
				
				return SignalProducer(values: versions)
			}
	}
	
	/// Loads the Cartfile for the given dependency, at the given version.
	private func cartfileForDependency(dependency: Dependency<PinnedVersion>) -> SignalProducer<Cartfile, CarthageError> {
		let revision = dependency.version.commitish
		return self.cloneOrFetchDependency(dependency.project, commitish: revision)
			.flatMap(.Concat) { repositoryURL in
				return contentsOfFileInRepository(repositoryURL, CarthageProjectCartfilePath, revision: revision)
			}
			.flatMapError { _ in .empty }
			.attemptMap(Cartfile.fromString)
	}

	/// Attempts to resolve a Git reference to a version.
	private func resolvedGitReference(project: ProjectIdentifier, reference: String) -> SignalProducer<PinnedVersion, CarthageError> {
		let repositoryURL = repositoryFileURLForProject(project)
		return cloneOrFetchDependency(project, commitish: reference)
			.flatMap(.Concat) { _ in
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
		let resolver = Resolver(versionsForDependency: versionsForProject, cartfileForDependency: cartfileForDependency, resolvedGitReference: resolvedGitReference)

		let resolvedCartfile: SignalProducer<ResolvedCartfile?, CarthageError> = loadResolvedCartfile()
			.map(Optional.init)
			.flatMapError { _ in .init(value: nil) }

		return zip(loadCombinedCartfile(), resolvedCartfile)
			.flatMap(.Merge) { cartfile, resolvedCartfile in
				return resolver.resolveDependenciesInCartfile(cartfile, lastResolved: resolvedCartfile, dependenciesToUpdate: dependenciesToUpdate)
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
		let outdatedDependencies = combineLatest(currentDependencies, updatedDependencies)
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

		return combineLatest(outdatedDependencies, explicitDependencyProjects)
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
				return .Success(self.useBinaries)
			}
			.flatMap(.Merge) { useBinaries -> SignalProducer<Bool, CarthageError> in
				if !useBinaries {
					return SignalProducer(value: false)
				}

				let checkoutDirectoryURL = self.directoryURL.appendingPathComponent(project.relativePath, isDirectory: true)

				switch project {
				case let .GitHub(repository):
					let client = Client(repository: repository)
					return self.downloadMatchingBinariesForProject(project, atRevision: revision, fromRepository: repository, client: client)
						.flatMapError { error -> SignalProducer<NSURL, CarthageError> in
							if !client.authenticated {
								return SignalProducer(error: error)
							}
							return self.downloadMatchingBinariesForProject(project, atRevision: revision, fromRepository: repository, client: Client(repository: repository, authenticated: false))
						}
						.flatMap(.Concat, transform: unzipArchiveToTemporaryDirectory)
						.flatMap(.Concat) { directoryURL in
							return frameworksInDirectory(directoryURL)
								.flatMap(.Merge, transform: self.copyFrameworkToBuildFolder)
								.flatMap(.Merge) { frameworkURL in
									return self.copyDSYMToBuildFolderForFramework(frameworkURL, fromDirectoryURL: directoryURL)
										.then(self.copyBCSymbolMapsToBuildFolderForFramework(frameworkURL, fromDirectoryURL: directoryURL))
								}
								.on(completed: {
									_ = try? NSFileManager.defaultManager().trashItemAtURL(checkoutDirectoryURL, resultingItemURL: nil)
								})
								.then(SignalProducer(value: directoryURL))
						}
						.attemptMap { (temporaryDirectoryURL: NSURL) -> Result<Bool, CarthageError> in
							do {
								try NSFileManager.defaultManager().removeItemAtURL(temporaryDirectoryURL)
								return .Success(true)
							} catch let error as NSError {
								return .Failure(.WriteFailed(temporaryDirectoryURL, error))
							}
						}
						.concat(SignalProducer(value: false))
						.take(1)

				case .Git:
					return SignalProducer(value: false)
				}
			}
	}

	/// Downloads any binaries and debug symbols that may be able to be used 
	/// instead of a repository checkout.
	///
	/// Sends the URL to each downloaded zip, after it has been moved to a
	/// less temporary location.
	private func downloadMatchingBinariesForProject(project: ProjectIdentifier, atRevision revision: String, fromRepository repository: Repository, client: Client) -> SignalProducer<NSURL, CarthageError> {
		return client.releaseForTag(revision, inRepository: repository)
			.map { _, release in release }
			.filter { release in
				return !release.draft && !release.assets.isEmpty
			}
			.flatMapError { error -> SignalProducer<Release, CarthageError> in
				switch error {
				case .DoesNotExist:
					return .empty
					
				case let .APIError(_, _, error):
					// Log the GitHub API request failure, not to error out,
					// because that should not be fatal error.
					self._projectEventsObserver.sendNext(.SkippedDownloadingBinaries(project, error.message))
					return .empty

				default:
					return SignalProducer(error: .GitHubAPIRequestFailed(error))
				}
			}
			.on(next: { release in
				self._projectEventsObserver.sendNext(.DownloadingBinaries(project, release.nameWithFallback))
			})
			.flatMap(.Concat) { release -> SignalProducer<NSURL, CarthageError> in
				return SignalProducer<Release.Asset, CarthageError>(values: release.assets)
					.filter { asset in
						let name = asset.name as NSString
						if name.rangeOfString(CarthageProjectBinaryAssetPattern).location == NSNotFound {
							return false
						}
						return CarthageProjectBinaryAssetContentTypes.contains(asset.contentType)
					}
					.flatMap(.Concat) { asset -> SignalProducer<NSURL, CarthageError> in
						let fileURL = fileURLToCachedBinary(project, release, asset)

						if NSFileManager.defaultManager().fileExistsAtPath(fileURL.path!) {
							return SignalProducer(value: fileURL)
						} else {
							return client.downloadAsset(asset)
								.mapError(CarthageError.GitHubAPIRequestFailed)
								.flatMap(.Concat) { downloadURL in cacheDownloadedBinary(downloadURL, toURL: fileURL) }
						}
					}
			}
	}

	/// Copies the framework at the given URL into the current project's build
	/// folder.
	///
	/// Sends the URL to the framework after copying.
	private func copyFrameworkToBuildFolder(frameworkURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
		return platformForFramework(frameworkURL)
			.flatMap(.Merge) { platform -> SignalProducer<NSURL, CarthageError> in
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
	public func copyDSYMToBuildFolderForFramework(frameworkURL: NSURL, fromDirectoryURL directoryURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
		let destinationDirectoryURL = frameworkURL.URLByDeletingLastPathComponent!
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
	public func copyBCSymbolMapsToBuildFolderForFramework(frameworkURL: NSURL, fromDirectoryURL directoryURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
		let destinationDirectoryURL = frameworkURL.URLByDeletingLastPathComponent!
		return BCSymbolMapsForFramework(frameworkURL, inDirectoryURL: directoryURL)
			.copyFileURLsIntoDirectory(destinationDirectoryURL)
	}

	/// Checks out the given project into its intended working directory,
	/// cloning it first if need be.
	private func checkoutOrCloneProject(project: ProjectIdentifier, atRevision revision: String, submodulesByPath: [String: Submodule]) -> SignalProducer<(), CarthageError> {
		return cloneOrFetchDependency(project, commitish: revision)
			.flatMap(.Merge) { repositoryURL -> SignalProducer<(), CarthageError> in
				let workingDirectoryURL = self.directoryURL.appendingPathComponent(project.relativePath, isDirectory: true)
				var submodule: Submodule?
				
				if var foundSubmodule = submodulesByPath[project.relativePath] {
					foundSubmodule.URL = repositoryURLForProject(project, preferHTTPS: self.preferHTTPS)
					foundSubmodule.SHA = revision
					submodule = foundSubmodule
				} else if self.useSubmodules {
					submodule = Submodule(name: project.relativePath, path: project.relativePath, URL: repositoryURLForProject(project, preferHTTPS: self.preferHTTPS), SHA: revision)
				}
				
				if let submodule = submodule {
					return addSubmoduleToRepository(self.directoryURL, submodule, GitURL(repositoryURL.path!))
						.startOnQueue(self.gitOperationQueue)
				} else {
					return checkoutRepositoryToDirectory(repositoryURL, workingDirectoryURL, revision: revision)
				}
			}
			.on(started: {
				self._projectEventsObserver.sendNext(.CheckingOut(project, revision))
			})
	}
	
	public func buildOrderForResolvedCartfile(cartfile: ResolvedCartfile, dependenciesToInclude: [String]? = nil) -> SignalProducer<Dependency<PinnedVersion>, CarthageError> {
		typealias DependencyGraph = [ProjectIdentifier: Set<ProjectIdentifier>]
		// A resolved cartfile already has all the recursive dependencies. All we need to do is sort
		// out the relationships between them. Loading the cartfile will each will give us its
		// dependencies. Building a recursive lookup table with this information will let us sort
		// dependencies before the projects that depend on them.
		return SignalProducer<Dependency<PinnedVersion>, CarthageError>(values: cartfile.dependencies)
			.flatMap(.Merge) { (dependency: Dependency<PinnedVersion>) -> SignalProducer<DependencyGraph, CarthageError> in
				return self.cartfileForDependency(dependency)
					.map { (cartfile: Cartfile) -> DependencyGraph in
						return [ dependency.project: Set(cartfile.dependencies.map { $0.project }) ]
					}
					.concat(SignalProducer(value: [ dependency.project: Set() ]))
					.take(1)
			}
			.reduce([:]) { (working: DependencyGraph, next: DependencyGraph) in
				var result = working
				next.forEach { result.updateValue($1, forKey: $0) }
				return result
			}
			.flatMap(.Latest) { (graph: DependencyGraph) -> SignalProducer<Dependency<PinnedVersion>, CarthageError> in
				let projectsToInclude = Set(graph
					.map { project, _ in project }
					.filter { project in dependenciesToInclude?.contains(project.name) ?? false })

				guard let sortedProjects = topologicalSort(graph, nodes: projectsToInclude) else {
					return SignalProducer(error: .DependencyCycle(graph))
				}

				let sortedDependencies = cartfile.dependencies
					.filter { dependency in sortedProjects.contains(dependency.project) }
					.sort { left, right in sortedProjects.indexOf(left.project) < sortedProjects.indexOf(right.project) }

				return SignalProducer(values: sortedDependencies)
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
			.flatMap(.Merge) { resolvedCartfile in
				return self
					.buildOrderForResolvedCartfile(resolvedCartfile, dependenciesToInclude: dependenciesToCheckout)
					.collect()
			}
			.zipWith(submodulesSignal)
			.flatMap(.Merge) { dependencies, submodulesByPath -> SignalProducer<(), CarthageError> in
				return SignalProducer<Dependency<PinnedVersion>, CarthageError>(values: dependencies)
					.flatMap(.Merge) { dependency -> SignalProducer<(), CarthageError> in
						let project = dependency.project
						let revision = dependency.version.commitish

						let submoduleFound = submodulesByPath[project.relativePath] != nil
						let checkoutOrCloneProject = self.checkoutOrCloneProject(project, atRevision: revision, submodulesByPath: submodulesByPath)

						// Disable binary downloads for the dependency if that
						// is already checked out as a submodule.
						if submoduleFound {
							return checkoutOrCloneProject
						}

						return self.installBinariesForProject(project, atRevision: revision)
							.flatMap(.Merge) { installed -> SignalProducer<(), CarthageError> in
								if installed {
									return .empty
								} else {
									return checkoutOrCloneProject
								}
							}
					}
			}
			.then(.empty)
	}

	/// Attempts to build each Carthage dependency that has been checked out, 
	/// optionally they are limited by the given list of dependency names.
	///
	/// Returns a producer-of-producers representing each scheme being built.
	public func buildCheckedOutDependenciesWithOptions(options: BuildOptions, dependenciesToBuild: [String]? = nil, sdkFilter: SDKFilterCallback = { .Success($0.0) }) -> SignalProducer<BuildSchemeProducer, CarthageError> {
		return loadResolvedCartfile()
			.flatMap(.Merge) { resolvedCartfile in
				return self.buildOrderForResolvedCartfile(resolvedCartfile, dependenciesToInclude: dependenciesToBuild)
			}
			.flatMap(.Concat) { dependency -> SignalProducer<BuildSchemeProducer, CarthageError> in
				let dependencyPath = self.directoryURL.appendingPathComponent(dependency.project.relativePath, isDirectory: true).path!
				if !NSFileManager.defaultManager().fileExistsAtPath(dependencyPath) {
					return .empty
				}

				return buildDependencyProject(dependency.project, self.directoryURL, withOptions: options, sdkFilter: sdkFilter)
					.flatMapError { error in
						switch error {
						case .NoSharedFrameworkSchemes:
							// Log that building the dependency is being skipped,
							// not to error out with `.NoSharedFrameworkSchemes`
							// to continue building other dependencies.
							self._projectEventsObserver.sendNext(.SkippedBuilding(dependency.project, error.description))
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
private func fileURLToCachedBinary(project: ProjectIdentifier, _ release: Release, _ asset: Release.Asset) -> NSURL {
	// ~/Library/Caches/org.carthage.CarthageKit/binaries/ReactiveCocoa/v2.3.1/1234-ReactiveCocoa.framework.zip
	return CarthageDependencyAssetsURL.appendingPathComponent("\(project.name)/\(release.tag)/\(asset.ID)-\(asset.name)", isDirectory: false)
}

/// Caches the downloaded binary at the given URL, moving it to the other URL
/// given.
///
/// Sends the final file URL upon .success.
private func cacheDownloadedBinary(downloadURL: NSURL, toURL cachedURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	return SignalProducer(value: cachedURL)
		.attempt { fileURL in
			let parentDirectoryURL = fileURL.URLByDeletingLastPathComponent!
			do {
				try NSFileManager.defaultManager().createDirectoryAtURL(parentDirectoryURL, withIntermediateDirectories: true, attributes: nil)
				return .Success(())
			} catch let error as NSError {
				return .Failure(.WriteFailed(parentDirectoryURL, error))
			}
		}
		.attempt { newDownloadURL in
			// Tries `rename()` system call at first.
			if rename(downloadURL.fileSystemRepresentation, newDownloadURL.fileSystemRepresentation) == 0 {
				return .Success(())
			}

			if errno != EXDEV {
				return .Failure(.TaskError(.POSIXError(errno)))
			}

			// If the “Cross-device link” error occurred, then falls back to
			// `NSFileManager.moveItemAtURL()`.
			//
			// See https://github.com/Carthage/Carthage/issues/706 and
			// https://github.com/Carthage/Carthage/issues/711.
			do {
				try NSFileManager.defaultManager().moveItemAtURL(downloadURL, toURL: newDownloadURL)
				return .Success(())
			} catch let error as NSError {
				return .Failure(.WriteFailed(newDownloadURL, error))
			}
		}
}

/// Sends the URL to each file found in the given directory conforming to the
/// given type identifier. If no type identifier is provided, all files are sent.
private func filesInDirectory(directoryURL: NSURL, _ typeIdentifier: String? = nil) -> SignalProducer<NSURL, CarthageError> {
	let producer = NSFileManager.defaultManager().carthage_enumeratorAtURL(directoryURL, includingPropertiesForKeys: [ NSURLTypeIdentifierKey ], options: [ .SkipsHiddenFiles, .SkipsPackageDescendants ], catchErrors: true)
		.map { enumerator, URL in URL }
	if let typeIdentifier = typeIdentifier {
		return producer
			.filter { URL in
				return URL.typeIdentifier
					.analysis(ifSuccess: { identifier in
						return UTTypeConformsTo(identifier, typeIdentifier)
					}, ifFailure: { _ in false })
			}
	} else {
		return producer
	}
}

/// Sends the platform specified in the given Info.plist.
private func platformForFramework(frameworkURL: NSURL) -> SignalProducer<Platform, CarthageError> {
	return SignalProducer(value: frameworkURL)
		// Neither DTPlatformName nor CFBundleSupportedPlatforms can not be used
		// because Xcode 6 and below do not include either in Mac OSX frameworks.
		.attemptMap { URL -> Result<String, CarthageError> in
			let bundle = NSBundle(URL: URL)

			func readFailed(message: String) -> CarthageError {
				let error = Result<(), NSError>.error(message)
				return .ReadFailed(frameworkURL, error)
			}

			guard let sdkName = bundle?.objectForInfoDictionaryKey("DTSDKName") else {
				return .Failure(readFailed("the DTSDKName key in its plist file is missing"))
			}

			if let sdkName = sdkName as? String {
				return .Success(sdkName)
			} else {
				return .Failure(readFailed("the value for the DTSDKName key in its plist file is not a string"))
			}
		}
		// Thus, the SDK name must be trimmed to match the platform name, e.g.
		// macosx10.10 -> macosx
		.map { sdkName in sdkName.stringByTrimmingCharactersInSet(NSCharacterSet.letterCharacterSet().invertedSet) }
		.attemptMap { platform in SDK.fromString(platform).map { $0.platform } }
}

/// Sends the URL to each framework bundle found in the given directory.
private func frameworksInDirectory(directoryURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	return filesInDirectory(directoryURL, kUTTypeFramework as String)
		.filter { URL in
			// Skip nested frameworks
			let frameworksInURL = URL.pathComponents?.filter { pathComponent in
				return (pathComponent as NSString).pathExtension == "framework"
			}
			return frameworksInURL?.count == 1
		}
}

/// Sends the URL to each dSYM found in the given directory
private func dSYMsInDirectory(directoryURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	return filesInDirectory(directoryURL, "com.apple.xcode.dsym")
}

/// Sends the URL of the dSYM whose UUIDs match those of the given framework, or
/// errors if there was an error parsing a dSYM contained within the directory.
private func dSYMForFramework(frameworkURL: NSURL, inDirectoryURL directoryURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	return UUIDsForFramework(frameworkURL)
		.flatMap(.Concat) { frameworkUUIDs in
			return dSYMsInDirectory(directoryURL)
				.flatMap(.Merge) { dSYMURL in
					return UUIDsForDSYM(dSYMURL)
						.filter { dSYMUUIDs in
							return dSYMUUIDs == frameworkUUIDs
						}
						.map { _ in dSYMURL }
				}
		}
		.take(1)
}

/// Sends the URL to each bcsymbolmap found in the given directory.
private func BCSymbolMapsInDirectory(directoryURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	return filesInDirectory(directoryURL)
		.filter { URL in URL.pathExtension == "bcsymbolmap" }
}

/// Sends the URLs of the bcsymbolmap files that match the given framework and are
/// located somewhere within the given directory.
private func BCSymbolMapsForFramework(frameworkURL: NSURL, inDirectoryURL directoryURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	return UUIDsForFramework(frameworkURL)
		.flatMap(.Merge) { UUIDs -> SignalProducer<NSURL, CarthageError> in
			if UUIDs.isEmpty {
				return .empty
			}
			func filterUUIDs(signal: Signal<NSURL, CarthageError>) -> Signal<NSURL, CarthageError> {
				var remainingUUIDs = UUIDs
				let count = remainingUUIDs.count
				return signal
					.filter { fileURL in
						if let basename = fileURL.URLByDeletingPathExtension?.lastPathComponent, fileUUID = NSUUID(UUIDString: basename) {
							return remainingUUIDs.remove(fileUUID) != nil
						} else {
							return false
						}
					}
					.take(count)
			}
			return BCSymbolMapsInDirectory(directoryURL)
				.lift(filterUUIDs)
	}
}

/// Returns the file URL at which the given project's repository will be
/// located.
private func repositoryFileURLForProject(project: ProjectIdentifier, baseURL: NSURL = CarthageDependencyRepositoriesURL) -> NSURL {
	return baseURL.appendingPathComponent(project.name, isDirectory: true)
}


/// Returns the URL that the project's remote repository exists at.
private func repositoryURLForProject(project: ProjectIdentifier, preferHTTPS: Bool) -> GitURL {
	switch project {
	case let .GitHub(repository):
		if preferHTTPS {
			return repository.HTTPSURL
		} else {
			return repository.SSHURL
		}

	case let .Git(URL):
		return URL
	}
}

/// Clones the given project to the given destination URL (defaults to the global
/// repositories folder), or fetches inside it if it has already been cloned.
/// Optionally takes a commitish to check for prior to fetching.
///
/// Returns a signal which will send the operation type once started, and
/// the URL to where the repository's folder will exist on disk, then complete
/// when the operation completes.
public func cloneOrFetchProject(project: ProjectIdentifier, preferHTTPS: Bool, destinationURL: NSURL = CarthageDependencyRepositoriesURL, commitish: String? = nil) -> SignalProducer<(ProjectEvent?, NSURL), CarthageError> {
	let fileManager = NSFileManager.defaultManager()
	let repositoryURL = repositoryFileURLForProject(project, baseURL: destinationURL)

	return SignalProducer.attempt { () -> Result<GitURL, CarthageError> in
			do {
				try fileManager.createDirectoryAtURL(destinationURL, withIntermediateDirectories: true, attributes: nil)
			} catch let error as NSError {
				return .Failure(.WriteFailed(destinationURL, error))
			}

			return .Success(repositoryURLForProject(project, preferHTTPS: preferHTTPS))
		}
		.flatMap(.Merge) { remoteURL -> SignalProducer<(ProjectEvent?, NSURL), CarthageError> in
			return isGitRepository(repositoryURL)
				.flatMap(.Merge) { isRepository -> SignalProducer<(ProjectEvent?, NSURL), CarthageError> in
					if isRepository {
						let fetchProducer: () -> SignalProducer<(ProjectEvent?, NSURL), CarthageError> = {
							guard FetchCache.needsFetch(forURL: remoteURL) else {
								return SignalProducer(value: (nil, repositoryURL))
							}

							return SignalProducer(value: (.Fetching(project), repositoryURL))
								.concat(fetchRepository(repositoryURL, remoteURL: remoteURL, refspec: "+refs/heads/*:refs/heads/*").then(.empty))
						}

						// If we've already cloned the repo, check for the revision, possibly skipping an unnecessary fetch
						if let commitish = commitish {
							return zip(
									branchExistsInRepository(repositoryURL, pattern: commitish),
									commitExistsInRepository(repositoryURL, revision: commitish)
								)
								.flatMap(.Concat) { branchExists, commitExists -> SignalProducer<(ProjectEvent?, NSURL), CarthageError> in
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
						_ = try? fileManager.removeItemAtURL(repositoryURL)
						return SignalProducer(value: (.Cloning(project), repositoryURL))
							.concat(cloneRepository(remoteURL, repositoryURL).then(.empty))
					}
			}
		}
}
