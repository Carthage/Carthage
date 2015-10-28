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

/// Carthage’s bundle identifier.
public let CarthageKitBundleIdentifier = NSBundle(forClass: Project.self).bundleIdentifier!

/// The fallback dependencies URL to be used in case
/// the intended ~/Library/Caches/org.carthage.CarthageKit cannot
/// be found or created.
private let fallbackDependenciesURL: NSURL = {
	let homePath: String
	if let homeEnvValue = NSProcessInfo.processInfo().environment["HOME"] as? NSString {
		homePath = homeEnvValue.stringByAppendingPathComponent(".carthage")
	} else {
		homePath = "~/.carthage".stringByExpandingTildeInPath
	}
	return NSURL.fileURLWithPath(homePath, isDirectory:true)!
}()

/// ~/Library/Caches/org.carthage.CarthageKit/
private let CarthageUserCachesURL: NSURL = {
	let fileManager = NSFileManager.defaultManager()
	
	let URLResult: Result<NSURL, NSError> = try({ (error: NSErrorPointer) -> NSURL? in
		fileManager.URLForDirectory(NSSearchPathDirectory.CachesDirectory, inDomain: NSSearchPathDomainMask.UserDomainMask, appropriateForURL: nil, create: true, error: error)
	}).flatMap { cachesURL in
		let dependenciesURL = cachesURL.URLByAppendingPathComponent(CarthageKitBundleIdentifier, isDirectory: true)
		let dependenciesPath = dependenciesURL.absoluteString!
		
		if fileManager.fileExistsAtPath(dependenciesPath, isDirectory:nil) {
			if fileManager.isWritableFileAtPath(dependenciesPath) {
				return Result(value: dependenciesURL)
			} else {
				let error = NSError(domain: CarthageKitBundleIdentifier, code: 0, userInfo: nil)
				return Result(error: error)
			}
		} else {
			return try { fileManager.createDirectoryAtURL(dependenciesURL, withIntermediateDirectories: true, attributes: [NSFilePosixPermissions : NSNumber(short:755)], error: $0) }.map { dependenciesURL }
		}
	}

	switch URLResult {
	case let .Success(URL):
		NSFileManager.defaultManager().removeItemAtURL(fallbackDependenciesURL, error: nil)
		return URL.value
	case let .Failure(error):
		NSLog("Warning: No Caches directory could be found or created: \(error.value.localizedDescription). (\(error.value))")
		return fallbackDependenciesURL
	}
}()

/// The file URL to the directory in which downloaded release binaries will be
/// stored.
///
/// ~/Library/Caches/org.carthage.CarthageKit/binaries/
public let CarthageDependencyAssetsURL = CarthageUserCachesURL.URLByAppendingPathComponent("binaries", isDirectory: true)

/// The file URL to the directory in which cloned dependencies will be stored.
///
/// ~/Library/Caches/org.carthage.CarthageKit/dependencies/
public let CarthageDependencyRepositoriesURL = CarthageUserCachesURL.URLByAppendingPathComponent("dependencies", isDirectory: true)

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
		return directoryURL.URLByAppendingPathComponent(CarthageProjectCartfilePath, isDirectory: false)
	}

	/// The file URL to the project's Cartfile.resolved.
	public var resolvedCartfileURL: NSURL {
		return directoryURL.URLByAppendingPathComponent(CarthageProjectResolvedCartfilePath, isDirectory: false)
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
		sendCompleted(_projectEventsObserver)
	}

	private typealias CachedVersions = [ProjectIdentifier: [PinnedVersion]]

	/// Caches versions to avoid expensive lookups, and unnecessary
	/// fetching/cloning.
	private var cachedVersions: CachedVersions = [:]
	private let cachedVersionsQueue = ProducerQueue(name: "org.carthage.CarthageKit.Project.cachedVersionsQueue")

	/// Attempts to load Cartfile or Cartfile.private from the given directory,
	/// merging their dependencies.
	public func loadCombinedCartfile() -> SignalProducer<Cartfile, CarthageError> {
		let cartfileURL = directoryURL.URLByAppendingPathComponent(CarthageProjectCartfilePath, isDirectory: false)
		let privateCartfileURL = directoryURL.URLByAppendingPathComponent(CarthageProjectPrivateCartfilePath, isDirectory: false)

		let isNoSuchFileError = { (error: CarthageError) -> Bool in
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

		let cartfile = SignalProducer.try {
				return Cartfile.fromFile(cartfileURL)
			}
			|> catch { error -> SignalProducer<Cartfile, CarthageError> in
				if isNoSuchFileError(error) && NSFileManager.defaultManager().fileExistsAtPath(privateCartfileURL.path!) {
					return SignalProducer(value: Cartfile())
				}

				return SignalProducer(error: error)
			}

		let privateCartfile = SignalProducer.try {
				return Cartfile.fromFile(privateCartfileURL)
			}
			|> catch { error -> SignalProducer<Cartfile, CarthageError> in
				if isNoSuchFileError(error) {
					return SignalProducer(value: Cartfile())
				}

				return SignalProducer(error: error)
			}

		return cartfile
			|> zipWith(privateCartfile)
			|> tryMap { (var cartfile, privateCartfile) -> Result<Cartfile, CarthageError> in
				let duplicateDeps = cartfile.duplicateProjects().map { DuplicateDependency(project: $0, locations: ["\(CarthageProjectCartfilePath)"]) }
					+ privateCartfile.duplicateProjects().map { DuplicateDependency(project: $0, locations: ["\(CarthageProjectPrivateCartfilePath)"]) }
					+ duplicateProjectsInCartfiles(cartfile, privateCartfile).map { DuplicateDependency(project: $0, locations: ["\(CarthageProjectCartfilePath)", "\(CarthageProjectPrivateCartfilePath)"]) }

				if duplicateDeps.count == 0 {
					cartfile.appendCartfile(privateCartfile)
					return .success(cartfile)
				}

				return .failure(.DuplicateDependencies(duplicateDeps))
			}
	}

	/// Reads the project's Cartfile.resolved.
	public func loadResolvedCartfile() -> SignalProducer<ResolvedCartfile, CarthageError> {
		return SignalProducer.try {
			var error: NSError?
			let resolvedCartfileContents = NSString(contentsOfURL: self.resolvedCartfileURL, encoding: NSUTF8StringEncoding, error: &error)
			if let resolvedCartfileContents = resolvedCartfileContents {
				return ResolvedCartfile.fromString(resolvedCartfileContents as String)
			} else {
				return .failure(.ReadFailed(self.resolvedCartfileURL, error))
			}
		}
	}

	/// Writes the given Cartfile.resolved out to the project's directory.
	public func writeResolvedCartfile(resolvedCartfile: ResolvedCartfile) -> Result<(), CarthageError> {
		var error: NSError?
		if resolvedCartfile.description.writeToURL(resolvedCartfileURL, atomically: true, encoding: NSUTF8StringEncoding, error: &error) {
			return .success(())
		} else {
			return .failure(.WriteFailed(resolvedCartfileURL, error))
		}
	}

	private let gitOperationQueue = ProducerQueue(name: "org.carthage.CarthageKit.Project.gitOperationQueue")

	/// Clones the given dependency to the global repositories folder, or fetches
	/// inside it if it has already been cloned.
	///
	/// Returns a signal which will send the URL to the repository's folder on
	/// disk once cloning or fetching has completed.
	private func cloneOrFetchDependency(project: ProjectIdentifier) -> SignalProducer<NSURL, CarthageError> {
		return cloneOrFetchProject(project, preferHTTPS: self.preferHTTPS)
			|> on(next: { event, _ in
				sendNext(self._projectEventsObserver, event)
			})
			|> map { _, URL in URL }
			|> takeLast(1)
			|> startOnQueue(gitOperationQueue)
	}

	/// Sends all versions available for the given project.
	///
	/// This will automatically clone or fetch the project's repository as
	/// necessary.
	private func versionsForProject(project: ProjectIdentifier) -> SignalProducer<PinnedVersion, CarthageError> {
		let fetchVersions = cloneOrFetchDependency(project)
			|> flatMap(.Merge) { repositoryURL in listTags(repositoryURL) }
			|> map { PinnedVersion($0) }
			|> collect
			|> on(next: { newVersions in
				self.cachedVersions[project] = newVersions
			})
			|> flatMap(.Concat) { versions in SignalProducer(values: versions) }

		return SignalProducer.try {
				return .success(self.cachedVersions)
			}
			|> promoteErrors(CarthageError.self)
			|> flatMap(.Merge) { versionsByProject -> SignalProducer<PinnedVersion, CarthageError> in
				if let versions = versionsByProject[project] {
					return SignalProducer(values: versions)
				} else {
					return fetchVersions
				}
			}
			|> startOnQueue(cachedVersionsQueue)
	}

	/// Attempts to resolve a Git reference to a version.
	private func resolvedGitReference(project: ProjectIdentifier, reference: String) -> SignalProducer<PinnedVersion, CarthageError> {
		return versionsForProject(project)
			|> collect
			|> flatMap(.Concat) { (versions: [PinnedVersion]) in
				let referencedVersion = PinnedVersion(reference)

				if contains(versions, referencedVersion) {
					// If the reference is an exact tag, resolves it to the tag.
					return SignalProducer(value: referencedVersion)
				} else {
					// Otherwise, it is resolved to an object SHA.
					return resolveReferenceInRepository(repositoryFileURLForProject(project), reference)
						|> map { PinnedVersion($0) }
				}
			}
	}

	/// Attempts to determine the latest satisfiable version of the project's
	/// Carthage dependencies.
	///
	/// This will fetch dependency repositories as necessary, but will not check
	/// them out into the project's working directory.
	public func updatedResolvedCartfile() -> SignalProducer<ResolvedCartfile, CarthageError> {
		let resolver = Resolver(versionsForDependency: versionsForProject, cartfileForDependency: cartfileForDependency, resolvedGitReference: resolvedGitReference)

		return loadCombinedCartfile()
			|> flatMap(.Merge) { cartfile in resolver.resolveDependenciesInCartfile(cartfile) }
			|> collect
			|> map { ResolvedCartfile(dependencies: $0) }
	}

	/// Updates the dependencies of the project to the latest version. The
	/// changes will be reflected in Cartfile.resolved, and also in the working
	/// directory checkouts if the given parameter is true.
	public func updateDependencies(shouldCheckout: Bool = true) -> SignalProducer<(), CarthageError> {
		return updatedResolvedCartfile()
			|> tryMap { resolvedCartfile -> Result<(), CarthageError> in
				return self.writeResolvedCartfile(resolvedCartfile)
			}
			|> then(shouldCheckout ? checkoutResolvedDependencies() : .empty)
	}

	/// Installs binaries and debug symbols for the given project, if available.
	///
	/// Sends a boolean indicating whether binaries were installed.
	private func installBinariesForProject(project: ProjectIdentifier, atRevision revision: String) -> SignalProducer<Bool, CarthageError> {
		return SignalProducer.try {
				return .success(self.useBinaries)
			}
			|> flatMap(.Merge) { useBinaries -> SignalProducer<Bool, CarthageError> in
				if !useBinaries {
					return SignalProducer(value: false)
				}

				let checkoutDirectoryURL = self.directoryURL.URLByAppendingPathComponent(project.relativePath, isDirectory: true)

				switch project {
				case let .GitHub(repository):
					return loadGitHubAuthorization(forServer: repository.server)
						|> flatMap(.Concat) { authorizationHeaderValue in
							return self.downloadMatchingBinariesForProject(project, atRevision: revision, fromRepository: repository, withAuthorizationHeaderValue: authorizationHeaderValue)
								|> catch { error in
									if authorizationHeaderValue == nil {
										return SignalProducer(error: error)
									}
									return self.downloadMatchingBinariesForProject(project, atRevision: revision, fromRepository: repository, withAuthorizationHeaderValue: nil)
								}
						}
						|> flatMap(.Concat, unzipArchiveToTemporaryDirectory)
						|> flatMap(.Concat) { directoryURL in
							return frameworksInDirectory(directoryURL)
								|> flatMap(.Merge, self.copyFrameworkToBuildFolder)
								|> flatMap(.Merge) { frameworkURL in
									return self.copyDSYMToBuildFolderForFramework(frameworkURL, fromDirectoryURL: directoryURL)
										|> then(self.copyBCSymbolMapsToBuildFolderForFramework(frameworkURL, fromDirectoryURL: directoryURL))
								}
								|> on(completed: {
									_ = NSFileManager.defaultManager().trashItemAtURL(checkoutDirectoryURL, resultingItemURL: nil, error: nil)
								})
								|> then(SignalProducer(value: directoryURL))
						}
						|> tryMap { (temporaryDirectoryURL: NSURL) -> Result<Bool, CarthageError> in
							var error: NSError?
							if NSFileManager.defaultManager().removeItemAtURL(temporaryDirectoryURL, error: &error) {
								return .success(true)
							} else {
								return .failure(.WriteFailed(temporaryDirectoryURL, error))
							}
						}
						|> concat(SignalProducer(value: false))
						|> take(1)

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
	private func downloadMatchingBinariesForProject(project: ProjectIdentifier, atRevision revision: String, fromRepository repository: GitHubRepository, withAuthorizationHeaderValue authorizationHeaderValue: String?) -> SignalProducer<NSURL, CarthageError> {
		return releaseForTag(revision, repository, authorizationHeaderValue)
			|> filter(binaryFrameworksCanBeProvidedByRelease)
			|> catch { error in
				switch error {
				case .GitHubAPIRequestFailed:
					// Log the GitHub API request failure, not to error out,
					// because that should not be fatal error.
					sendNext(self._projectEventsObserver, .SkippedDownloadingBinaries(project, error.description))
					return .empty

				default:
					return SignalProducer(error: error)
				}
			}
			|> on(next: { release in
				sendNext(self._projectEventsObserver, .DownloadingBinaries(project, release.nameWithFallback))
			})
			|> flatMap(.Concat) { release -> SignalProducer<NSURL, CarthageError> in
				return SignalProducer(values: release.assets)
					|> filter(binaryFrameworksCanBeProvidedByAsset)
					|> flatMap(.Concat) { asset -> SignalProducer<NSURL, CarthageError> in
						let fileURL = fileURLToCachedBinary(project, release, asset)

						if NSFileManager.defaultManager().fileExistsAtPath(fileURL.path!) {
							return SignalProducer(value: fileURL)
						} else {
							return downloadAsset(asset, authorizationHeaderValue)
								|> flatMap(.Concat) { downloadURL in cacheDownloadedBinary(downloadURL, toURL: fileURL) }
						}
					}
			}
	}

	/// Copies the framework at the given URL into the current project's build
	/// folder.
	///
	/// Sends the URL to the framework after copying.
	private func copyFrameworkToBuildFolder(frameworkURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
		return infoPlistForFramework(frameworkURL)
			|> flatMap(.Merge) { infoPlistURL in platformForInfoPlist(infoPlistURL) }
			|> flatMap(.Merge) { platform in
				let platformFolderURL = self.directoryURL.URLByAppendingPathComponent(platform.relativePath, isDirectory: true)
				return copyFileURLsFromProducer(SignalProducer(value: frameworkURL), intoDirectory: platformFolderURL)
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
		let dSYMProducer = dSYMForFramework(frameworkURL, inDirectoryURL:directoryURL)
		return copyFileURLsFromProducer(dSYMProducer, intoDirectory: destinationDirectoryURL)
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
		let bcsymbolmapsProducer = BCSymbolMapsForFramework(frameworkURL, inDirectoryURL: directoryURL)
		return copyFileURLsFromProducer(bcsymbolmapsProducer, intoDirectory: destinationDirectoryURL)
	}

	/// Checks out the given project into its intended working directory,
	/// cloning it first if need be.
	private func checkoutOrCloneProject(project: ProjectIdentifier, atRevision revision: String, submodulesByPath: [String: Submodule]) -> SignalProducer<(), CarthageError> {
		let repositoryURL = repositoryFileURLForProject(project)
		let workingDirectoryURL = directoryURL.URLByAppendingPathComponent(project.relativePath, isDirectory: true)

		let checkoutSignal = SignalProducer.try { () -> Result<Submodule?, CarthageError> in
				var submodule: Submodule?

				if var foundSubmodule = submodulesByPath[project.relativePath] {
					foundSubmodule.URL = repositoryURLForProject(project, preferHTTPS: self.preferHTTPS)
					foundSubmodule.SHA = revision
					submodule = foundSubmodule
				} else if self.useSubmodules {
					submodule = Submodule(name: project.relativePath, path: project.relativePath, URL: repositoryURLForProject(project, preferHTTPS: self.preferHTTPS), SHA: revision)
				}

				return .success(submodule)
			}
			|> flatMap(.Merge) { submodule -> SignalProducer<(), CarthageError> in
				if let submodule = submodule {
					return addSubmoduleToRepository(self.directoryURL, submodule, GitURL(repositoryURL.path!))
						|> startOnQueue(self.gitOperationQueue)
				} else {
					return checkoutRepositoryToDirectory(repositoryURL, workingDirectoryURL, revision: revision)
				}
			}
			|> on(started: {
				sendNext(self._projectEventsObserver, .CheckingOut(project, revision))
			})

		return commitExistsInRepository(repositoryURL, revision: revision)
			|> promoteErrors(CarthageError.self)
			|> flatMap(.Merge) { exists -> SignalProducer<NSURL, CarthageError> in
				if exists {
					return .empty
				} else {
					return self.cloneOrFetchDependency(project)
				}
			}
			|> then(checkoutSignal)
	}

	/// Checks out the dependencies listed in the project's Cartfile.resolved.
	public func checkoutResolvedDependencies() -> SignalProducer<(), CarthageError> {
		/// Determine whether the repository currently holds any submodules (if
		/// it even is a repository).
		let submodulesSignal = submodulesInRepository(self.directoryURL)
			|> reduce([:]) { (var submodulesByPath: [String: Submodule], submodule) in
				submodulesByPath[submodule.path] = submodule
				return submodulesByPath
			}

		return loadResolvedCartfile()
			|> zipWith(submodulesSignal)
			|> flatMap(.Merge) { resolvedCartfile, submodulesByPath -> SignalProducer<(), CarthageError> in
				return SignalProducer(values: resolvedCartfile.dependencies)
					|> flatMap(.Merge) { dependency in
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
							|> flatMap(.Merge) { installed in
								if installed {
									return .empty
								} else {
									return checkoutOrCloneProject
								}
							}
					}
			}
			|> then(.empty)
	}

	/// Attempts to build each Carthage dependency that has been checked out.
	///
	/// Returns a producer-of-producers representing each scheme being built.
	public func buildCheckedOutDependenciesWithConfiguration(configuration: String, forPlatforms platforms: Set<Platform>, sdkFilter: SDKFilterCallback = { .success($0.0) }) -> SignalProducer<BuildSchemeProducer, CarthageError> {
		return loadResolvedCartfile()
			|> flatMap(.Merge) { resolvedCartfile in SignalProducer(values: resolvedCartfile.dependencies) }
			|> flatMap(.Concat) { dependency -> SignalProducer<BuildSchemeProducer, CarthageError> in
				let dependencyPath = self.directoryURL.URLByAppendingPathComponent(dependency.project.relativePath, isDirectory: true).path!
				if !NSFileManager.defaultManager().fileExistsAtPath(dependencyPath) {
					return .empty
				}

				return buildDependencyProject(dependency.project, self.directoryURL, withConfiguration: configuration, platforms: platforms, sdkFilter: sdkFilter)
					|> catch { error in
						switch error {
						case .NoSharedFrameworkSchemes:
							// Log that building the dependency is being skipped,
							// not to error out with `.NoSharedFrameworkSchemes`
							// to continue building other dependencies.
							sendNext(self._projectEventsObserver, .SkippedBuilding(dependency.project, error.description))
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
private func fileURLToCachedBinary(project: ProjectIdentifier, release: GitHubRelease, asset: GitHubRelease.Asset) -> NSURL {
	// ~/Library/Caches/org.carthage.CarthageKit/binaries/ReactiveCocoa/v2.3.1/1234-ReactiveCocoa.framework.zip
	return CarthageDependencyAssetsURL.URLByAppendingPathComponent("\(project.name)/\(release.tag)/\(asset.ID)-\(asset.name)", isDirectory: false)
}

/// Caches the downloaded binary at the given URL, moving it to the other URL
/// given.
///
/// Sends the final file URL upon .success.
private func cacheDownloadedBinary(downloadURL: NSURL, toURL cachedURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	return SignalProducer(value: cachedURL)
		|> try { fileURL in
			var error: NSError?
			let parentDirectoryURL = fileURL.URLByDeletingLastPathComponent!
			if NSFileManager.defaultManager().createDirectoryAtURL(parentDirectoryURL, withIntermediateDirectories: true, attributes: nil, error: &error) {
				return .success(())
			} else {
				return .failure(.WriteFailed(parentDirectoryURL, error))
			}
		}
		|> try { newDownloadURL in
			// Tries `rename()` system call at first.
			if rename(downloadURL.fileSystemRepresentation, newDownloadURL.fileSystemRepresentation) == 0 {
				return .success(())
			}

			if errno != EXDEV {
				return .failure(.TaskError(.POSIXError(errno)))
			}

			// If the “Cross-device link” error occurred, then falls back to
			// `NSFileManager.moveItemAtURL()`.
			//
			// See https://github.com/Carthage/Carthage/issues/706 and
			// https://github.com/Carthage/Carthage/issues/711.
			var error: NSError?
			if NSFileManager.defaultManager().moveItemAtURL(downloadURL, toURL: newDownloadURL, error: &error) {
				return .success(())
			} else {
				return .failure(.WriteFailed(newDownloadURL, error))
			}
		}
}

/// Sends the URL to each file found in the given directory conforming to the
/// given type identifier. If no type identifier is provided, all files are sent.
private func filesInDirectory(directoryURL: NSURL, _ typeIdentifier: String? = nil) -> SignalProducer<NSURL, CarthageError> {
	let producer = NSFileManager.defaultManager().carthage_enumeratorAtURL(directoryURL, includingPropertiesForKeys: [ NSURLTypeIdentifierKey ], options: .SkipsHiddenFiles | .SkipsPackageDescendants, catchErrors: true)
		|> map { enumerator, URL in URL }
	if let typeIdentifier = typeIdentifier {
		return producer
			|> filter { URL in
				return URL.typeIdentifier
					.analysis(ifSuccess: { identifier in
						return UTTypeConformsTo(identifier, typeIdentifier) != 0
					}, ifFailure: { _ in false })
			}
	} else {
		return producer
	}
}

/// Sends the URL for the Info.plist of the specified Framework.
private func infoPlistForFramework(frameworkURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	// The paths at which the Info.plist can be located within a framework:
	let infoPlistCantidatePaths = [
		// iOS, watchOS, and tvOS
		"/Info.plist",
		// Mac OSX
		"/Resources/Info.plist",
	]

	return SignalProducer(values: infoPlistCantidatePaths.map { frameworkURL.URLByAppendingPathComponent($0) })
		|> filter { infoPlistCantidateURL in
			var isDirectory: ObjCBool = false
			return NSFileManager.defaultManager().fileExistsAtPath(infoPlistCantidateURL.path!, isDirectory: &isDirectory) && !isDirectory
		}
		|> filter { (infoPlistCantidateURL: NSURL) in
			return infoPlistCantidateURL.typeIdentifier
				.analysis(ifSuccess: { identifier in
					return UTTypeConformsTo(identifier, "com.apple.property-list") != 0
				}, ifFailure: { _ in false })
		}
		|> take(1)
}

/// Sends the platform specified in the given Info.plist.
private func platformForInfoPlist(plistURL: NSURL) -> SignalProducer<Platform, CarthageError> {
	return SignalProducer.try { () -> Result<NSData, CarthageError> in
			var error: NSError?
			if let data = NSData(contentsOfURL: plistURL, options: nil, error: &error) {
				return .success(data)
			}
			return .failure(.ReadFailed(plistURL, error))
		}
		|> startOn(QueueScheduler(name: "org.carthage.CarthageKit.Project.platformForInfoPlist"))
		|> tryMap { (data: NSData) -> Result<AnyObject, CarthageError> in
			var error: NSError?
			let options = NSPropertyListReadOptions(NSPropertyListMutabilityOptions.Immutable.rawValue)
			let plist: AnyObject? = NSPropertyListSerialization.propertyListWithData(data, options: options, format: nil, error: &error)
			if let pist: AnyObject = plist {
				return .success(pist)
			}
			return .failure(.ReadFailed(plistURL, error))
		}
		|> tryMap { plist -> Result<[String: AnyObject], CarthageError> in
			if let plist = plist as? [String: AnyObject] {
				return .success(plist)
			}
			return .failure(.InfoPlistParseFailed(plistURL: plistURL, reason: "the root plist object is not a dictionary of values by strings"))
		}
		// Neither DTPlatformName nor CFBundleSupportedPlatforms can not be used 
		// because Xcode 6 and below do not include either in Mac OSX frameworks.
		|> tryMap { plist -> Result<String, CarthageError> in
			if let sdkName = plist["DTSDKName"] as? String {
				return .success(sdkName)
			}
			return .failure(.InfoPlistParseFailed(plistURL: plistURL, reason: "the value for the DTSDKName key is not a string"))
		}
		// Thus, the SDK name must be trimmed to match the platform name, e.g.
		// macosx10.10 -> macosx
		|> map { sdkName in sdkName.stringByTrimmingCharactersInSet(NSCharacterSet.letterCharacterSet().invertedSet) }
		|> tryMap { platform in SDK.fromString(platform).map { $0.platform } }
}

/// Sends the URL to each framework bundle found in the given directory.
private func frameworksInDirectory(directoryURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	return filesInDirectory(directoryURL, (kUTTypeFramework as! String))
		|> filter { URL in
			// Skip nested frameworks
			let frameworksInURL = URL.pathComponents?.filter { pathComponent in
				return (pathComponent as? String)?.pathExtension == "framework"
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
		|> flatMap(.Concat) { frameworkUUIDs in
			return dSYMsInDirectory(directoryURL)
				|> flatMap(.Merge) { dSYMURL in
					return UUIDsForDSYM(dSYMURL)
						|> filter { dSYMUUIDs in
							return dSYMUUIDs == frameworkUUIDs
						}
						|> map { _ in dSYMURL }
				}
		}
		|> take(1)
}

/// Sends the URL to each bcsymbolmap found in the given directory.
private func BCSymbolMapsInDirectory(directoryURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	return filesInDirectory(directoryURL)
		|> filter { URL in URL.pathExtension == "bcsymbolmap" }
}

/// Sends the URLs of the bcsymbolmap files that match the given framework and are
/// located somewhere within the given directory.
private func BCSymbolMapsForFramework(frameworkURL: NSURL, inDirectoryURL directoryURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	return UUIDsForFramework(frameworkURL)
		|> flatMap(.Merge) { UUIDs in
			if UUIDs.isEmpty {
				return .empty
			}
			func filterUUIDs(signal: Signal<NSURL, CarthageError>) -> Signal<NSURL, CarthageError> {
				var remainingUUIDs = UUIDs
				let count = remainingUUIDs.count
				return signal
					|> filter { fileURL in
						if let basename = fileURL.lastPathComponent?.stringByDeletingPathExtension, fileUUID = NSUUID(UUIDString: basename) {
							return remainingUUIDs.remove(fileUUID) != nil
						} else {
							return false
						}
					}
					|> take(count)
			}
			return BCSymbolMapsInDirectory(directoryURL)
				|> filterUUIDs
	}
}

/// Determines whether a Release is a suitable candidate for binary frameworks.
private func binaryFrameworksCanBeProvidedByRelease(release: GitHubRelease) -> Bool {
	return !release.draft && !release.assets.isEmpty
}

/// Determines whether a release asset is a suitable candidate for binary
/// frameworks.
private func binaryFrameworksCanBeProvidedByAsset(asset: GitHubRelease.Asset) -> Bool {
	let name = asset.name as NSString
	if name.rangeOfString(CarthageProjectBinaryAssetPattern).location == NSNotFound {
		return false
	}

	return contains(CarthageProjectBinaryAssetContentTypes, asset.contentType)
}

/// Returns the file URL at which the given project's repository will be
/// located.
private func repositoryFileURLForProject(project: ProjectIdentifier) -> NSURL {
	return CarthageDependencyRepositoriesURL.URLByAppendingPathComponent(project.name, isDirectory: true)
}

/// Loads the Cartfile for the given dependency, at the given version.
private func cartfileForDependency(dependency: Dependency<PinnedVersion>) -> SignalProducer<Cartfile, CarthageError> {
	let repositoryURL = repositoryFileURLForProject(dependency.project)

	return contentsOfFileInRepository(repositoryURL, CarthageProjectCartfilePath, revision: dependency.version.commitish)
		|> catch { _ in .empty }
		|> tryMap { Cartfile.fromString($0) }
}

/// Returns the URL that the project's remote repository exists at.
private func repositoryURLForProject(project: ProjectIdentifier, #preferHTTPS: Bool) -> GitURL {
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

/// Clones the given project to the global repositories folder, or fetches
/// inside it if it has already been cloned.
///
/// Returns a signal which will send the operation type once started, and
/// the URL to where the repository's folder will exist on disk, then complete
/// when the operation completes.
public func cloneOrFetchProject(project: ProjectIdentifier, #preferHTTPS: Bool) -> SignalProducer<(ProjectEvent, NSURL), CarthageError> {
	let fileManager = NSFileManager.defaultManager()
	let repositoryURL = repositoryFileURLForProject(project)

	return SignalProducer.try { () -> Result<GitURL, CarthageError> in
			var error: NSError?
			if !fileManager.createDirectoryAtURL(CarthageDependencyRepositoriesURL, withIntermediateDirectories: true, attributes: nil, error: &error) {
				return .failure(.WriteFailed(CarthageDependencyRepositoriesURL, error))
			}

			return .success(repositoryURLForProject(project, preferHTTPS: preferHTTPS))
		}
		|> flatMap(.Merge) { remoteURL in
			let cloneProducer: () -> SignalProducer<(ProjectEvent, NSURL), CarthageError> = {
				let cloneProducer = cloneRepository(remoteURL, repositoryURL)

				return SignalProducer(value: (.Cloning(project), repositoryURL))
					|> concat(cloneProducer |> then(.empty))
			}

			if fileManager.createDirectoryAtURL(repositoryURL, withIntermediateDirectories: false, attributes: nil, error: nil) {
				// If we created the directory, we're now responsible for
				// cloning it.
				return cloneProducer()
			} else {
				return isGitRepository(repositoryURL)
					|> promoteErrors(CarthageError.self)
					|> flatMap(.Concat) { isRepository in
						if isRepository {
							let fetchProducer = fetchRepository(repositoryURL, remoteURL: remoteURL, refspec: "+refs/heads/*:refs/heads/*") /* lol syntax highlighting */

							return SignalProducer(value: (.Fetching(project), repositoryURL))
								|> concat(fetchProducer |> then(.empty))
						} else {
							// If the directory isn't a repository (that might
							// happen if the process is quitted right after
							// creating the directory), remove the directory then
							// clone it.
							fileManager.removeItemAtURL(repositoryURL, error: nil)
							return cloneProducer()
						}
					}
			}
		}
}
