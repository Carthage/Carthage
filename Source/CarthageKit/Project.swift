//
//  Project.swift
//  Carthage
//
//  Created by Alan Rogers on 12/10/2014.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa

/// Carthage’s bundle identifier.
public let CarthageKitBundleIdentifier = NSBundle(forClass: Project.self).bundleIdentifier!

// TODO: remove this once we’ve bumped LlamaKit.
private func try<T>(f: NSErrorPointer -> T?) -> Result<T> {
	var error: NSError?
	let because = -1
	return f(&error).map(success) ?? failure(error ?? NSError(domain: CarthageKitBundleIdentifier, code: because, userInfo: nil))
}

/// ~/Library/Caches/org.carthage.CarthageKit/
private let CarthageUserCachesURL: NSURL = {
	let URL = try { error in
		NSFileManager.defaultManager().URLForDirectory(NSSearchPathDirectory.CachesDirectory, inDomain: NSSearchPathDomainMask.UserDomainMask, appropriateForURL: nil, create: true, error: error)
	}

	let fallbackDependenciesURL = NSURL.fileURLWithPath("~/.carthage".stringByExpandingTildeInPath, isDirectory:true)!

	switch URL {
	case .Success:
		NSFileManager.defaultManager().removeItemAtURL(fallbackDependenciesURL, error: nil)

	case let .Failure(error):
		NSLog("Warning: No Caches directory could be found or created: \(error.localizedDescription). (\(error))")
	}

	return URL.value()?.URLByAppendingPathComponent(CarthageKitBundleIdentifier, isDirectory: true) ?? fallbackDependenciesURL
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
}

/// The settings for identifying and configuring a Carthage project.
public struct ProjectSettings: Equatable {
	/// File URL to the root directory of the project.
	public let directoryURL: NSURL

	/// Whether to prefer HTTPS for cloning (vs. SSH).
	public var preferHTTPS = true

	/// Whether to use submodules for dependencies, or just check out their
	/// working directories.
	public var useSubmodules = false

	/// Whether to download binaries for dependencies, or just check out their
	/// repositories.
	public var useBinaries = false

	public init(directoryURL: NSURL) {
		precondition(directoryURL.fileURL)

		self.directoryURL = directoryURL
	}
}

public func == (lhs: ProjectSettings, rhs: ProjectSettings) -> Bool {
	return lhs.directoryURL == rhs.directoryURL && lhs.preferHTTPS == rhs.preferHTTPS && lhs.useSubmodules == rhs.useSubmodules && lhs.useBinaries == rhs.useBinaries
}

extension ProjectSettings: Hashable {
	public var hashValue: Int {
		return directoryURL.hashValue
	}
}

extension ProjectSettings: Printable {
	public var description: String {
		return "ProjectSettings { path = \(directoryURL.path!), preferHTTPS = \(preferHTTPS), useSubmodules = \(useSubmodules), useBinaries = \(useBinaries) }"
	}
}

/// Represents a project that is using Carthage.
public final class Project {
	/// The settings with which this project is configured.
	public let settings: ProjectSettings

	/// The file URL to the project's Cartfile.
	public var cartfileURL: NSURL {
		return settings.directoryURL.URLByAppendingPathComponent(CarthageProjectCartfilePath, isDirectory: false)
	}

	/// The file URL to the project's Cartfile.resolved.
	public var resolvedCartfileURL: NSURL {
		return settings.directoryURL.URLByAppendingPathComponent(CarthageProjectResolvedCartfilePath, isDirectory: false)
	}

	/// Sends each event that occurs to a project underneath the receiver (or
	/// the receiver itself).
	public let projectEvents: HotSignal<ProjectEvent>
	private let _projectEventsSink: SinkOf<ProjectEvent>

	public init(settings: ProjectSettings) {
		self.settings = settings

		let (signal, sink) = HotSignal<ProjectEvent>.pipe()
		projectEvents = signal
		_projectEventsSink = sink
	}

	/// Caches versions to avoid expensive lookups, and unnecessary
	/// fetching/cloning.
	private var cachedVersions: [ProjectIdentifier: [PinnedVersion]] = [:]
	private let cachedVersionsScheduler = QueueScheduler()

	/// Reads the current value of `cachedVersions` on the appropriate
	/// scheduler.
	private func readCachedVersions() -> ColdSignal<[ProjectIdentifier: [PinnedVersion]]> {
		return ColdSignal.lazy {
				return .single(self.cachedVersions)
			}
			.evaluateOn(cachedVersionsScheduler)
			.deliverOn(QueueScheduler())
	}

	/// Adds a given version to `cachedVersions` on the appropriate scheduler.
	private func addCachedVersion(version: PinnedVersion, forProject project: ProjectIdentifier) {
		self.cachedVersionsScheduler.schedule {
			if var versions = self.cachedVersions[project] {
				versions.append(version)
				self.cachedVersions[project] = versions
			} else {
				self.cachedVersions[project] = [ version ]
			}
		}
	}

	/// Attempts to load Cartfile or Cartfile.private from the given directory,
	/// merging their dependencies.
	public func loadCombinedCartfile() -> ColdSignal<Cartfile> {
		let cartfileURL = settings.directoryURL.URLByAppendingPathComponent(CarthageProjectCartfilePath, isDirectory: false)
		let privateCartfileURL = settings.directoryURL.URLByAppendingPathComponent(CarthageProjectPrivateCartfilePath, isDirectory: false)

		let isNoSuchFileError = { (error: NSError) -> Bool in
			return error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
		}

		let cartfile = ColdSignal.lazy {
				.fromResult(Cartfile.fromFile(cartfileURL))
			}
			.catch { error -> ColdSignal<Cartfile> in
				if isNoSuchFileError(error) && NSFileManager.defaultManager().fileExistsAtPath(privateCartfileURL.path!) {
					return .single(Cartfile())
				}

				return .error(error)
			}

		let privateCartfile = ColdSignal.lazy {
				.fromResult(Cartfile.fromFile(privateCartfileURL))
			}
			.catch { error -> ColdSignal<Cartfile> in
				if isNoSuchFileError(error) {
					return .single(Cartfile())
				}

				return .error(error)
		}

		return cartfile.zipWith(privateCartfile)
			.map { (var cartfile, privateCartfile) -> Cartfile in
				cartfile.appendCartfile(privateCartfile)

				return cartfile
			}
	}

	/// Reads the project's Cartfile.resolved.
	public func loadResolvedCartfile() -> ColdSignal<ResolvedCartfile> {
		return ColdSignal.lazy {
			var error: NSError?
			let resolvedCartfileContents = NSString(contentsOfURL: self.resolvedCartfileURL, encoding: NSUTF8StringEncoding, error: &error)
			if let resolvedCartfileContents = resolvedCartfileContents {
				return .fromResult(ResolvedCartfile.fromString(resolvedCartfileContents))
			} else {
				return .error(error ?? CarthageError.ReadFailed(self.resolvedCartfileURL).error)
			}
		}
	}

	/// Writes the given Cartfile.resolved out to the project's directory.
	public func writeResolvedCartfile(resolvedCartfile: ResolvedCartfile) -> Result<()> {
		var error: NSError?
		if resolvedCartfile.description.writeToURL(resolvedCartfileURL, atomically: true, encoding: NSUTF8StringEncoding, error: &error) {
			return success(())
		} else {
			return failure(error ?? CarthageError.WriteFailed(resolvedCartfileURL).error)
		}
	}

	/// A scheduler used to serialize all Git operations within this project.
	private let gitOperationScheduler = QueueScheduler()

	/// Runs the given Git operation, blocking the `gitOperationScheduler` until
	/// it has completed.
	private func runGitOperation<T>(operation: ColdSignal<T>) -> ColdSignal<T> {
		return ColdSignal { (sink, disposable) in
			let schedulerDisposable = self.gitOperationScheduler.schedule {
				let results = operation
					.reduce(initial: []) { $0 + [ $1 ] }
					.first()

				switch results {
				case let .Success(values):
					ColdSignal.fromValues(values.unbox).startWithSink { valuesDisposable in
						disposable.addDisposable(valuesDisposable)
						return sink
					}

				case let .Failure(error):
					sink.put(.Error(error))
				}
			}

			disposable.addDisposable(schedulerDisposable)
		}.deliverOn(QueueScheduler())
	}

	/// Clones the given dependency to the global repositories folder, or fetches
	/// inside it if it has already been cloned.
	///
	/// Returns a signal which will send the URL to the repository's folder on
	/// disk once cloning or fetching has completed.
	private func cloneOrFetchDependency(project: ProjectIdentifier) -> ColdSignal<NSURL> {
		let operation = cloneOrFetchProject(project, preferHTTPS: settings.preferHTTPS)
			.on(next: { event, _ in
				self._projectEventsSink.put(event)
			})
			.map { _, URL in URL }
			.takeLast(1)

		return runGitOperation(operation)
	}

	/// Sends all versions available for the given project.
	///
	/// This will automatically clone or fetch the project's repository as
	/// necessary.
	private func versionsForProject(project: ProjectIdentifier) -> ColdSignal<PinnedVersion> {
		let fetchVersions = cloneOrFetchDependency(project)
			.map { repositoryURL in listTags(repositoryURL) }
			.merge(identity)
			.map { PinnedVersion($0) }
			.on(next: { self.addCachedVersion($0, forProject: project) })

		return readCachedVersions()
			.map { versionsByProject -> ColdSignal<PinnedVersion> in
				if let versions = versionsByProject[project] {
					return .fromValues(versions)
				} else {
					return fetchVersions
				}
			}
			.merge(identity)
	}

	/// Attempts to resolve a Git reference to a version.
	private func resolvedGitReference(project: ProjectIdentifier, reference: String) -> ColdSignal<PinnedVersion> {
		// We don't need the version list, but this takes care of
		// cloning/fetching for us, while avoiding duplication.
		return versionsForProject(project)
			.then(resolveReferenceInRepository(repositoryFileURLForProject(project), reference))
			.map { PinnedVersion($0) }
	}

	/// Attempts to determine the latest satisfiable version of the project's
	/// Carthage dependencies.
	///
	/// This will fetch dependency repositories as necessary, but will not check
	/// them out into the project's working directory.
	public func updatedResolvedCartfile() -> ColdSignal<ResolvedCartfile> {
		let resolver = Resolver(versionsForDependency: versionsForProject, cartfileForDependency: cartfileForDependency, resolvedGitReference: resolvedGitReference)

		return loadCombinedCartfile()
			.mergeMap { cartfile in resolver.resolveDependenciesInCartfile(cartfile) }
			.reduce(initial: []) { $0 + [ $1 ] }
			.map { ResolvedCartfile(dependencies: $0) }
	}

	/// Updates the dependencies of the project to the latest version. The
	/// changes will be reflected in the working directory checkouts and
	/// Cartfile.resolved.
	public func updateDependencies() -> ColdSignal<()> {
		return updatedResolvedCartfile()
			.tryMap { resolvedCartfile -> Result<()> in
				return self.writeResolvedCartfile(resolvedCartfile)
			}
			.then(checkoutResolvedDependencies())
	}

	/// Installs binaries for the given project, if available.
	///
	/// Sends a boolean indicating whether binaries were installed.
	private func installBinariesForProject(project: ProjectIdentifier, atRevision revision: String) -> ColdSignal<Bool> {
		return ColdSignal.lazy {
			if !self.settings.useBinaries {
				return .single(false)
			}

			let checkoutDirectoryURL = self.settings.directoryURL.URLByAppendingPathComponent(project.relativePath, isDirectory: true)

			switch project {
			case let .GitHub(repository):
				return self.downloadMatchingBinariesForProject(project, atRevision: revision, fromRepository: repository, withCredentials: nil)
					.catch { error in
						// If we were unable to fetch releases, try loading credentials from Git.
						if error.domain == NSURLErrorDomain {
							return GitHubCredentials.loadFromGit()
								.mergeMap { credentials in
									if let credentials = credentials {
										return self.downloadMatchingBinariesForProject(project, atRevision: revision, fromRepository: repository, withCredentials: credentials)
									} else {
										return .error(error)
									}
								}
						} else {
							return .error(error)
						}
					}
					.concatMap(unzipArchiveToTemporaryDirectory)
					.concatMap { directoryURL in
						return frameworksInDirectory(directoryURL)
							.mergeMap(self.copyFrameworkToBuildFolder)
							.on(completed: {
								_ = NSFileManager.defaultManager().trashItemAtURL(checkoutDirectoryURL, resultingItemURL: nil, error: nil)
							})
							.then(.single(directoryURL))
					}
					.tryMap { (temporaryDirectoryURL: NSURL, error: NSErrorPointer) -> Bool? in
						if NSFileManager.defaultManager().removeItemAtURL(temporaryDirectoryURL, error: error) {
							return true
						} else {
							return nil
						}
					}
					.concat(.single(false))
					.take(1)

			case .Git:
				return .single(false)
			}
		}
	}

	/// Downloads any binaries that may be able to be used instead of a
	/// repository checkout.
	///
	/// Sends the URL to each downloaded zip, after it has been moved to a
	/// less temporary location.
	private func downloadMatchingBinariesForProject(project: ProjectIdentifier, atRevision revision: String, fromRepository repository: GitHubRepository, withCredentials credentials: GitHubCredentials?) -> ColdSignal<NSURL> {
		return releaseForTag(revision, repository, credentials)
			.filter(binaryFrameworksCanBeProvidedByRelease)
			.on(next: { release in
				self._projectEventsSink.put(.DownloadingBinaries(project, release.name))
			})
			.concatMap { release in
				return ColdSignal
					.fromValues(release.assets)
					.filter(binaryFrameworksCanBeProvidedByAsset)
					.concatMap { asset in
						let fileURL = fileURLToCachedBinary(project, release, asset)

						return ColdSignal<NSURL>.lazy {
							if NSFileManager.defaultManager().fileExistsAtPath(fileURL.path!) {
								return .single(fileURL)
							} else {
								return downloadAsset(asset, credentials)
									.concatMap { downloadURL in cacheDownloadedBinary(downloadURL, toURL: fileURL) }
							}
						}
					}
			}
	}

	/// Copies the framework at the given URL into the current project's build
	/// folder.
	///
	/// Sends the URL to the framework after copying.
	private func copyFrameworkToBuildFolder(frameworkURL: NSURL) -> ColdSignal<NSURL> {
		return architecturesInFramework(frameworkURL)
			.filter { arch in arch.hasPrefix("arm") }
			.map { _ in SDK.iPhoneOS }
			.concat(ColdSignal.single(SDK.MacOSX))
			.take(1)
			.map { sdk in sdk.platform }
			.map { platform in self.settings.directoryURL.URLByAppendingPathComponent(platform.relativePath, isDirectory: true) }
			.map { platformFolderURL in platformFolderURL.URLByAppendingPathComponent(frameworkURL.lastPathComponent!) }
			.mergeMap { destinationFrameworkURL in copyFramework(frameworkURL, destinationFrameworkURL) }
	}

	/// Checks out the given project into its intended working directory,
	/// cloning it first if need be.
	private func checkoutOrCloneProject(project: ProjectIdentifier, atRevision revision: String, submodulesByPath: [String: Submodule]) -> ColdSignal<()> {
		let repositoryURL = repositoryFileURLForProject(project)
		let workingDirectoryURL = settings.directoryURL.URLByAppendingPathComponent(project.relativePath, isDirectory: true)

		let checkoutSignal = ColdSignal<()>.lazy {
				var submodule: Submodule?

				if var foundSubmodule = submodulesByPath[project.relativePath] {
					foundSubmodule.URL = repositoryURLForProject(project, preferHTTPS: self.settings.preferHTTPS)
					foundSubmodule.SHA = revision
					submodule = foundSubmodule
				} else if self.settings.useSubmodules {
					submodule = Submodule(name: project.relativePath, path: project.relativePath, URL: repositoryURLForProject(project, preferHTTPS: self.settings.preferHTTPS), SHA: revision)
				}

				if let submodule = submodule {
					return self.runGitOperation(addSubmoduleToRepository(self.settings.directoryURL, submodule, GitURL(repositoryURL.path!)))
				} else {
					return checkoutRepositoryToDirectory(repositoryURL, workingDirectoryURL, revision: revision)
				}
			}
			.on(started: {
				self._projectEventsSink.put(.CheckingOut(project, revision))
			})

		return commitExistsInRepository(repositoryURL, revision: revision)
			.map { exists -> ColdSignal<NSURL> in
				if exists {
					return .empty()
				} else {
					return self.cloneOrFetchDependency(project)
				}
			}
			.merge(identity)
			.then(checkoutSignal)
	}

	/// Checks out the dependencies listed in the project's Cartfile.resolved.
	public func checkoutResolvedDependencies() -> ColdSignal<()> {
		/// Determine whether the repository currently holds any submodules (if
		/// it even is a repository).
		let submodulesSignal = submodulesInRepository(settings.directoryURL)
			.reduce(initial: [:]) { (var submodulesByPath: [String: Submodule], submodule) in
				submodulesByPath[submodule.path] = submodule
				return submodulesByPath
			}

		return loadResolvedCartfile()
			.zipWith(submodulesSignal)
			.map { (resolvedCartfile, submodulesByPath) -> ColdSignal<()> in
				return ColdSignal.fromValues(resolvedCartfile.dependencies)
					.mergeMap { dependency in
						let project = dependency.project
						let revision = dependency.version.commitish

						return self.installBinariesForProject(project, atRevision: revision)
							.mergeMap { installed in
								if installed {
									return .empty()
								} else {
									return self.checkoutOrCloneProject(project, atRevision: revision, submodulesByPath: submodulesByPath)
								}
							}
					}
			}
			.merge(identity)
			.then(.empty())
	}

	/// Attempts to build each Carthage dependency that has been checked out.
	///
	/// Returns a signal of all standard output from `xcodebuild`, and a
	/// signal-of-signals representing each scheme being built.
	public func buildCheckedOutDependenciesWithConfiguration(configuration: String, forPlatform platform: Platform?) -> (HotSignal<NSData>, ColdSignal<BuildSchemeSignal>) {
		let (stdoutSignal, stdoutSink) = HotSignal<NSData>.pipe()
		let schemeSignals = loadResolvedCartfile()
			.map { resolvedCartfile in ColdSignal.fromValues(resolvedCartfile.dependencies) }
			.merge(identity)
			.map { dependency -> ColdSignal<BuildSchemeSignal> in
				return ColdSignal.lazy {
					let dependencyPath = self.settings.directoryURL.URLByAppendingPathComponent(dependency.project.relativePath, isDirectory: true).path!
					if !NSFileManager.defaultManager().fileExistsAtPath(dependencyPath) {
						return .empty()
					}

					let (buildOutput, schemeSignals) = buildDependencyProject(dependency.project, self.settings.directoryURL, withConfiguration: configuration, platform: platform)
					buildOutput.observe(stdoutSink)

					return schemeSignals
				}
			}
			.concat(identity)

		return (stdoutSignal, schemeSignals)
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
/// Sends the final file URL upon success.
private func cacheDownloadedBinary(downloadURL: NSURL, toURL cachedURL: NSURL) -> ColdSignal<NSURL> {
	return ColdSignal
		.single(cachedURL)
		.try { fileURL, error in
			let parentDirectoryURL = fileURL.URLByDeletingLastPathComponent!
			return NSFileManager.defaultManager().createDirectoryAtURL(parentDirectoryURL, withIntermediateDirectories: true, attributes: nil, error: error)
		}
		.try { newDownloadURL, error in
			if rename(downloadURL.fileSystemRepresentation, newDownloadURL.fileSystemRepresentation) == 0 {
				return true
			} else {
				error.memory = NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
				return false
			}
		}
}

/// Sends the URL to each framework bundle found in the given directory.
private func frameworksInDirectory(directoryURL: NSURL) -> ColdSignal<NSURL> {
	return NSFileManager.defaultManager()
		.carthage_enumeratorAtURL(directoryURL, includingPropertiesForKeys: [ NSURLTypeIdentifierKey ], options: NSDirectoryEnumerationOptions.SkipsHiddenFiles | NSDirectoryEnumerationOptions.SkipsPackageDescendants, catchErrors: true)
		.map { enumerator, URL in URL }
		.filter { URL in
			var typeIdentifier: AnyObject?
			if URL.getResourceValue(&typeIdentifier, forKey: NSURLTypeIdentifierKey, error: nil) {
				if let typeIdentifier: AnyObject = typeIdentifier {
					if UTTypeConformsTo(typeIdentifier as String, kUTTypeFramework) != 0 {
						return true
					}
				}
			}

			return false
		}
}

/// Determines whether a Release is a suitable candidate for binary frameworks.
private func binaryFrameworksCanBeProvidedByRelease(release: GitHubRelease) -> Bool {
	return !release.draft && !release.prerelease && !release.assets.isEmpty
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
private func cartfileForDependency(dependency: Dependency<PinnedVersion>) -> ColdSignal<Cartfile> {
	let repositoryURL = repositoryFileURLForProject(dependency.project)

	return contentsOfFileInRepository(repositoryURL, CarthageProjectCartfilePath, revision: dependency.version.commitish)
		.catch { _ in .empty() }
		.tryMap { Cartfile.fromString($0) }
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
public func cloneOrFetchProject(project: ProjectIdentifier, #preferHTTPS: Bool) -> ColdSignal<(ProjectEvent, NSURL)> {
	let repositoryURL = repositoryFileURLForProject(project)

	return ColdSignal.lazy {
		var error: NSError?
		if !NSFileManager.defaultManager().createDirectoryAtURL(CarthageDependencyRepositoriesURL, withIntermediateDirectories: true, attributes: nil, error: &error) {
			return .error(error ?? CarthageError.WriteFailed(CarthageDependencyRepositoriesURL).error)
		}

		let remoteURL = repositoryURLForProject(project, preferHTTPS: preferHTTPS)
		if NSFileManager.defaultManager().createDirectoryAtURL(repositoryURL, withIntermediateDirectories: false, attributes: nil, error: nil) {
			// If we created the directory, we're now responsible for
			// cloning it.
			let cloneSignal = cloneRepository(remoteURL, repositoryURL)

			return ColdSignal.single((ProjectEvent.Cloning(project), repositoryURL))
				.concat(cloneSignal.then(.empty()))
		} else {
			let fetchSignal = fetchRepository(repositoryURL, remoteURL: remoteURL, refspec: "+refs/heads/*:refs/heads/*") /* lol syntax highlighting */

			return ColdSignal.single((ProjectEvent.Fetching(project), repositoryURL))
				.concat(fetchSignal.then(.empty()))
		}
	}
}
