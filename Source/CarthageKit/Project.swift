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

/// ~/Library/Caches/
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

	return URL.value() ?? fallbackDependenciesURL
}()

/// The file URL to the directory in which cloned dependencies will be stored.
///
/// ~/Library/Caches/org.carthage.CarthageKit/dependencies/
public let CarthageDependencyRepositoriesURL = CarthageUserCachesURL.URLByAppendingPathComponent(CarthageKitBundleIdentifier, isDirectory: true).URLByAppendingPathComponent("dependencies", isDirectory: true)

/// The relative path to a project's Cartfile.
public let CarthageProjectCartfilePath = "Cartfile"

/// The relative path to a project's Cartfile.resolved.
public let CarthageProjectResolvedCartfilePath = "Cartfile.resolved"

/// Describes an event occurring to or with a project.
public enum ProjectEvent {
	/// The project is beginning to clone.
	case Cloning(ProjectIdentifier)

	/// The project is beginning a fetch.
	case Fetching(ProjectIdentifier)

	/// The project is being checked out to the specified revision.
	case CheckingOut(ProjectIdentifier, String)
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

	/// Sends each event that occurs to a project underneath the receiver (or
	/// the receiver itself).
	public let projectEvents: HotSignal<ProjectEvent>
	private let _projectEventsSink: SinkOf<ProjectEvent>

	public init(directoryURL: NSURL) {
		precondition(directoryURL.fileURL)

		let (signal, sink) = HotSignal<ProjectEvent>.pipe()
		projectEvents = signal
		_projectEventsSink = sink

		self.directoryURL = directoryURL
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

	/// Reads the project's Cartfile.
	public func readCartfile() -> Result<Cartfile> {
		var error: NSError?
		let cartfileContents = NSString(contentsOfURL: cartfileURL, encoding: NSUTF8StringEncoding, error: &error)
		if let cartfileContents = cartfileContents {
			return Cartfile.fromString(cartfileContents)
		} else {
			return failure(error ?? CarthageError.ReadFailed(cartfileURL).error)
		}
	}

	/// Reads the project's Cartfile.resolved.
	public func readResolvedCartfile() -> Result<ResolvedCartfile> {
		var error: NSError?
		let resolvedCartfileContents = NSString(contentsOfURL: resolvedCartfileURL, encoding: NSUTF8StringEncoding, error: &error)
		if let resolvedCartfileContents = resolvedCartfileContents {
			return ResolvedCartfile.fromString(resolvedCartfileContents)
		} else {
			return failure(error ?? CarthageError.ReadFailed(resolvedCartfileURL).error)
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

	/// Returns the URL that the project's remote repository exists at.
	private func repositoryURLForProject(project: ProjectIdentifier) -> GitURL {
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

	/// Clones the given project to the global repositories folder, or fetches
	/// inside it if it has already been cloned.
	///
	/// Returns a signal which will send the URL to the repository's folder on
	/// disk.
	private func cloneOrFetchProject(project: ProjectIdentifier) -> ColdSignal<NSURL> {
		let repositoryURL = repositoryFileURLForProject(project)
		let operation = ColdSignal<NSURL>.lazy {
			var error: NSError?
			if !NSFileManager.defaultManager().createDirectoryAtURL(CarthageDependencyRepositoriesURL, withIntermediateDirectories: true, attributes: nil, error: &error) {
				return .error(error ?? CarthageError.WriteFailed(CarthageDependencyRepositoriesURL).error)
			}

			let remoteURL = self.repositoryURLForProject(project)
			if NSFileManager.defaultManager().createDirectoryAtURL(repositoryURL, withIntermediateDirectories: false, attributes: nil, error: nil) {
				// If we created the directory, we're now responsible for
				// cloning it.
				self._projectEventsSink.put(.Cloning(project))

				return cloneRepository(remoteURL, repositoryURL)
					.then(.single(repositoryURL))
			} else {
				self._projectEventsSink.put(.Fetching(project))

				return fetchRepository(repositoryURL, remoteURL: remoteURL, refspec: "+refs/heads/*:refs/heads/*") /* lol syntax highlighting */
					.then(.single(repositoryURL))
			}
		}

		return runGitOperation(operation)
	}

	/// Sends all versions available for the given project.
	///
	/// This will automatically clone or fetch the project's repository as
	/// necessary.
	private func versionsForProject(project: ProjectIdentifier) -> ColdSignal<PinnedVersion> {
		let fetchVersions = cloneOrFetchProject(project)
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
		return cloneOrFetchProject(project)
			.map { repositoryURL in
				return resolveReferenceInRepository(repositoryURL, reference)
			}
			.merge(identity)
			.map { PinnedVersion($0) }
	}

	/// Attempts to determine the latest satisfiable version of the project's
	/// Carthage dependencies.
	///
	/// This will fetch dependency repositories as necessary, but will not check
	/// them out into the project's working directory.
	public func updatedResolvedCartfile() -> ColdSignal<ResolvedCartfile> {
		let resolver = Resolver(versionsForDependency: versionsForProject, cartfileForDependency: cartfileForDependency, resolvedGitReference: resolvedGitReference)

		return ColdSignal.lazy {
				return .fromResult(self.readCartfile())
			}
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

	/// Checks out the given project into its intended working directory,
	/// cloning it first if need be.
	private func checkoutOrCloneProject(project: ProjectIdentifier, atRevision revision: String, submodulesByPath: [String: Submodule]) -> ColdSignal<()> {
		let repositoryURL = repositoryFileURLForProject(project)
		let workingDirectoryURL = directoryURL.URLByAppendingPathComponent(project.relativePath, isDirectory: true)

		let checkoutSignal = ColdSignal<()>.lazy {
				var submodule: Submodule?

				if var foundSubmodule = submodulesByPath[project.relativePath] {
					foundSubmodule.URL = self.repositoryURLForProject(project)
					foundSubmodule.SHA = revision
					submodule = foundSubmodule
				} else if self.useSubmodules {
					submodule = Submodule(name: project.relativePath, path: project.relativePath, URL: self.repositoryURLForProject(project), SHA: revision)
				}

				if let submodule = submodule {
					return self.runGitOperation(addSubmoduleToRepository(self.directoryURL, submodule, GitURL(repositoryURL.path!)))
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
					return self.cloneOrFetchProject(project)
				}
			}
			.merge(identity)
			.then(checkoutSignal)
	}

	/// Checks out the dependencies listed in the project's Cartfile.resolved.
	public func checkoutResolvedDependencies() -> ColdSignal<()> {
		/// Determine whether the repository currently holds any submodules (if
		/// it even is a repository).
		let submodulesSignal = submodulesInRepository(self.directoryURL)
			.reduce(initial: [:]) { (var submodulesByPath: [String: Submodule], submodule) in
				submodulesByPath[submodule.path] = submodule
				return submodulesByPath
			}

		return ColdSignal<ResolvedCartfile>.lazy {
				return ColdSignal.fromResult(self.readResolvedCartfile())
			}
			.zipWith(submodulesSignal)
			.map { (resolvedCartfile, submodulesByPath) -> ColdSignal<()> in
				return ColdSignal.fromValues(resolvedCartfile.dependencies)
					.map { dependency in
						return self.checkoutOrCloneProject(dependency.project, atRevision: dependency.version.commitish, submodulesByPath: submodulesByPath)
					}
					.merge(identity)
			}
			.merge(identity)
			.then(.empty())
	}

	/// Attempts to build each Carthage dependency that has been checked out.
	///
	/// Returns a signal of all standard output from `xcodebuild`, and a
	/// signal-of-signals representing each scheme being built.
	public func buildCheckedOutDependencies(configuration: String) -> (HotSignal<NSData>, ColdSignal<BuildSchemeSignal>) {
		let (stdoutSignal, stdoutSink) = HotSignal<NSData>.pipe()
		let schemeSignals = ColdSignal<ResolvedCartfile>.lazy {
				return .fromResult(self.readResolvedCartfile())
			}
			.map { resolvedCartfile in ColdSignal.fromValues(resolvedCartfile.dependencies) }
			.merge(identity)
			.map { dependency -> ColdSignal<BuildSchemeSignal> in
				let (buildOutput, schemeSignals) = buildDependencyProject(dependency.project, self.directoryURL, withConfiguration: configuration)
				buildOutput.observe(stdoutSink)

				return schemeSignals
			}
			.concat(identity)

		return (stdoutSignal, schemeSignals)
	}
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
