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
private let CarthageBundleIdentifier = NSBundle(forClass: Project.self).bundleIdentifier!

/// ~/Library/Caches/
private let CarthageCachesURL: NSURL = {
	let URL = NSFileManager.defaultManager().URLForDirectory(NSSearchPathDirectory.CachesDirectory, inDomain: NSSearchPathDomainMask.UserDomainMask, appropriateForURL: nil, create: true, error: nil)
	if URL == nil {
		println("Error: No Caches directory could be found or created.")
		exit(1)
	}

	// Make a best-effort attempt to clean up the old dependencies dir.
	NSFileManager.defaultManager().removeItemAtURL(NSURL.fileURLWithPath("~/.carthage/dependencies".stringByExpandingTildeInPath, isDirectory:true)!, error: nil)

	return URL!
}()

/// The file URL to the directory in which cloned dependencies will be stored.
///
/// ~/Library/Caches/org.carthage.CarthageKit/dependencies/
public let CarthageDependencyRepositoriesURL = CarthageCachesURL.URLByAppendingPathComponent(CarthageBundleIdentifier, isDirectory: true).URLByAppendingPathComponent("dependencies", isDirectory: true)

/// The relative path to a project's Cartfile.
public let CarthageProjectCartfilePath = "Cartfile"

/// The relative path to a project's Cartfile.lock.
public let CarthageProjectCartfileLockPath = "Cartfile.lock"

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

	/// The project's Cartfile.
	public let cartfile: Cartfile

	/// The file URL to the project's Cartfile.lock.
	public var cartfileLockURL: NSURL {
		return directoryURL.URLByAppendingPathComponent(CarthageProjectCartfileLockPath, isDirectory: false)
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

	public required init(directoryURL: NSURL, cartfile: Cartfile) {
		let (signal, sink) = HotSignal<ProjectEvent>.pipe()
		projectEvents = signal
		_projectEventsSink = sink

		self.directoryURL = directoryURL

		// TODO: Load this lazily.
		self.cartfile = cartfile
	}

	/// Caches versions to avoid expensive lookups, and unnecessary
	/// fetching/cloning.
	private var cachedVersions: [ProjectIdentifier: [SemanticVersion]] = [:]
	private let cachedVersionsScheduler = QueueScheduler()

	/// Reads the current value of `cachedVersions` on the appropriate
	/// scheduler.
	private func readCachedVersions() -> ColdSignal<[ProjectIdentifier: [SemanticVersion]]> {
		return ColdSignal.lazy {
				return .single(self.cachedVersions)
			}
			.subscribeOn(cachedVersionsScheduler)
			.deliverOn(QueueScheduler())
	}

	/// Adds a given version to `cachedVersions` on the appropriate scheduler.
	private func addCachedVersion(version: SemanticVersion, forProject project: ProjectIdentifier) {
		self.cachedVersionsScheduler.schedule {
			if var versions = self.cachedVersions[project] {
				versions.append(version)
				self.cachedVersions[project] = versions
			} else {
				self.cachedVersions[project] = [ version ]
			}
		}
	}

	/// Attempts to load project information from the given directory.
	public class func loadFromDirectory(directoryURL: NSURL) -> Result<Project> {
		precondition(directoryURL.fileURL)

		let cartfileURL = directoryURL.URLByAppendingPathComponent(CarthageProjectCartfilePath, isDirectory: false)

		// TODO: Load this lazily.
		var error: NSError?
		let cartfileContents = NSString(contentsOfURL: cartfileURL, encoding: NSUTF8StringEncoding, error: &error)
		if let cartfileContents = cartfileContents {
			return Cartfile.fromString(cartfileContents).map { cartfile in
				return self(directoryURL: directoryURL, cartfile: cartfile)
			}
		} else {
			return failure(error ?? CarthageError.ReadFailed(cartfileURL).error)
		}
	}

	/// Reads the project's Cartfile.lock.
	public func readCartfileLock() -> Result<CartfileLock> {
		var error: NSError?
		let cartfileLockContents = NSString(contentsOfURL: cartfileLockURL, encoding: NSUTF8StringEncoding, error: &error)
		if let cartfileLockContents = cartfileLockContents {
			return CartfileLock.fromString(cartfileLockContents)
		} else {
			return failure(error ?? CarthageError.ReadFailed(cartfileLockURL).error)
		}
	}

	/// Writes the given Cartfile.lock out to the project's directory.
	public func writeCartfileLock(cartfileLock: CartfileLock) -> Result<()> {
		var error: NSError?
		if cartfileLock.description.writeToURL(cartfileLockURL, atomically: true, encoding: NSUTF8StringEncoding, error: &error) {
			return success(())
		} else {
			return failure(error ?? CarthageError.WriteFailed(cartfileLockURL).error)
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

	/// Returns the file URL at which the given project's repository will be
	/// located.
	private func repositoryFileURLForProject(project: ProjectIdentifier) -> NSURL {
		return CarthageDependencyRepositoriesURL.URLByAppendingPathComponent(project.name, isDirectory: true)
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

				return fetchRepository(repositoryURL, remoteURL: remoteURL)
					.then(.single(repositoryURL))
			}
		}

		return runGitOperation(operation)
	}

	/// Sends all versions available for the given project.
	///
	/// This will automatically clone or fetch the project's repository as
	/// necessary.
	private func versionsForProject(project: ProjectIdentifier) -> ColdSignal<SemanticVersion> {
		let fetchVersions = cloneOrFetchProject(project)
			.map { repositoryURL in listTags(repositoryURL) }
			.merge(identity)
			.map { PinnedVersion(tag: $0) }
			.map { version -> ColdSignal<SemanticVersion> in
				return ColdSignal.fromResult(SemanticVersion.fromPinnedVersion(version))
					.catch { _ in .empty() }
			}
			.merge(identity)
			.on(next: { self.addCachedVersion($0, forProject: project) })

		return readCachedVersions()
			.map { versionsByProject -> ColdSignal<SemanticVersion> in
				if let versions = versionsByProject[project] {
					return .fromValues(versions)
				} else {
					return fetchVersions
				}
			}
			.merge(identity)
	}

	/// Loads the Cartfile for the given dependency, at the given version.
	private func cartfileForDependency(dependency: Dependency<SemanticVersion>) -> ColdSignal<Cartfile> {
		precondition(dependency.version.pinnedVersion != nil)

		let pinnedVersion = dependency.version.pinnedVersion!
		let repositoryURL = repositoryFileURLForProject(dependency.project)

		return contentsOfFileInRepository(repositoryURL, CarthageProjectCartfilePath, revision: pinnedVersion.tag)
			.catch { _ in .empty() }
			.tryMap { Cartfile.fromString($0) }
	}

	/// Attempts to determine the latest satisfiable version of the project's
	/// Carthage dependencies.
	///
	/// This will fetch dependency repositories as necessary, but will not check
	/// them out into the project's working directory.
	public func updatedCartfileLock() -> ColdSignal<CartfileLock> {
		let resolver = Resolver(versionsForDependency: versionsForProject, cartfileForDependency: cartfileForDependency)
		return resolver.resolveDependenciesInCartfile(self.cartfile)
			.map { dependency -> Dependency<PinnedVersion> in
				return dependency.map { $0.pinnedVersion! }
			}
			.reduce(initial: []) { $0 + [ $1 ] }
			.map { CartfileLock(dependencies: $0) }
	}

	/// Updates the dependencies of the project to the latest version. The
	/// changes will be reflected in the working directory checkouts and
	/// Cartfile.lock.
	public func updateDependencies() -> ColdSignal<()> {
		return updatedCartfileLock()
			.tryMap { cartfileLock -> Result<()> in
				return self.writeCartfileLock(cartfileLock)
			}
			.then(checkoutLockedDependencies())
	}

	/// Checks out the given project into its intended working directory,
	/// cloning it first if need be.
	private func checkoutOrCloneProject(project: ProjectIdentifier, atRevision revision: String, submodulesByPath: [String: Submodule]) -> ColdSignal<()> {
		let repositoryURL = self.repositoryFileURLForProject(project)
		let workingDirectoryURL = self.directoryURL.URLByAppendingPathComponent(project.relativePath, isDirectory: true)

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
			.on(subscribed: {
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

	/// Checks out the dependencies listed in the project's Cartfile.lock.
	public func checkoutLockedDependencies() -> ColdSignal<()> {
		/// Determine whether the repository currently holds any submodules (if
		/// it even is a repository).
		let submodulesSignal = submodulesInRepository(self.directoryURL)
			.reduce(initial: [:]) { (var submodulesByPath: [String: Submodule], submodule) in
				submodulesByPath[submodule.path] = submodule
				return submodulesByPath
			}

		return ColdSignal<CartfileLock>.lazy {
				return ColdSignal.fromResult(self.readCartfileLock())
			}
			// TODO: This should be a zip.
			.combineLatestWith(submodulesSignal)
			.map { (cartfileLock, submodulesByPath) -> ColdSignal<()> in
				return ColdSignal.fromValues(cartfileLock.dependencies)
					.map { dependency in
						return self.checkoutOrCloneProject(dependency.project, atRevision: dependency.version.tag, submodulesByPath: submodulesByPath)
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
		let schemeSignals = ColdSignal<CartfileLock>.lazy {
				return .fromResult(self.readCartfileLock())
			}
			.map { lockFile in ColdSignal.fromValues(lockFile.dependencies) }
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
