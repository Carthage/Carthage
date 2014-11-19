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

/// The file URL to the directory in which cloned dependencies will be stored.
public let CarthageDependencyRepositoriesURL = NSURL.fileURLWithPath("~/.carthage/dependencies".stringByExpandingTildeInPath, isDirectory:true)!

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

	/// Clones the given project to the global repositories folder, or fetches
	/// inside it if it has already been cloned.
	///
	/// Returns a signal which will send the URL to the repository's folder on
	/// disk.
	private func cloneOrFetchProject(project: ProjectIdentifier) -> ColdSignal<NSURL> {
		let repositoryURL = repositoryFileURLForProject(project)

		return ColdSignal { subscriber in
			let schedulerDisposable = self.gitOperationScheduler.schedule {
				var error: NSError?
				if !NSFileManager.defaultManager().createDirectoryAtURL(CarthageDependencyRepositoriesURL, withIntermediateDirectories: true, attributes: nil, error: &error) {
					subscriber.put(.Error(error ?? CarthageError.WriteFailed(CarthageDependencyRepositoriesURL).error))
					return
				}

				let remoteURL = self.repositoryURLForProject(project)
				var result: Result<()>?

				if NSFileManager.defaultManager().createDirectoryAtURL(repositoryURL, withIntermediateDirectories: false, attributes: nil, error: nil) {
					// If we created the directory, we're now responsible for
					// cloning it.
					self._projectEventsSink.put(.Cloning(project))
					result = cloneRepository(remoteURL, repositoryURL).wait()
				} else {
					self._projectEventsSink.put(.Fetching(project))
					result = fetchRepository(repositoryURL, remoteURL: remoteURL).wait()
				}

				switch result! {
				case .Success:
					subscriber.put(.Next(Box(repositoryURL)))
					subscriber.put(.Completed)

				case let .Failure(error):
					subscriber.put(.Error(error))
				}
			}

			subscriber.disposable.addDisposable(schedulerDisposable)
		}.deliverOn(QueueScheduler())
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
	private func checkoutOrCloneProject(project: ProjectIdentifier, atRevision revision: String) -> ColdSignal<()> {
		let repositoryURL = self.repositoryFileURLForProject(project)
		let workingDirectoryURL = self.directoryURL.URLByAppendingPathComponent(project.relativePath, isDirectory: true)

		let checkoutSignal = checkoutRepositoryToDirectory(repositoryURL, workingDirectoryURL, revision: revision)
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
			.then(.empty())
	}

	/// Checks out the dependencies listed in the project's Cartfile.lock.
	public func checkoutLockedDependencies() -> ColdSignal<()> {
		return ColdSignal<CartfileLock>.lazy {
				return ColdSignal.fromResult(self.readCartfileLock())
			}
			.map { cartfileLock -> ColdSignal<Dependency<PinnedVersion>> in
				return ColdSignal.fromValues(cartfileLock.dependencies)
			}
			.merge(identity)
			.map { dependency in self.checkoutOrCloneProject(dependency.project, atRevision: dependency.version.tag) }
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

				return ColdSignal.lazy {
					let outputDisposable = buildOutput.observe(stdoutSink)

					return schemeSignals
						.on(disposed: {
							outputDisposable.dispose()
						})
				}
			}
			.concat(identity)

		return (stdoutSignal, schemeSignals)
	}
}
