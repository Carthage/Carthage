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

	public required init(directoryURL: NSURL, cartfile: Cartfile) {
		self.directoryURL = directoryURL
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

	/// Returns a string representing the URL that the project's remote repository
	/// exists at.
	private func repositoryURLStringForProject(project: ProjectIdentifier) -> String {
		switch project {
		case let .GitHub(repository):
			return repository.cloneURLString
		}
	}

	/// Returns the file URL at which the given project's repository will be
	/// located.
	private func repositoryFileURLForProject(project: ProjectIdentifier) -> NSURL {
		return CarthageDependencyRepositoriesURL.URLByAppendingPathComponent(project.name, isDirectory: true)
	}

	/// Sends all versions available for the given project.
	///
	/// This will automatically clone or fetch the project's repository as
	/// necessary.
	private func versionsForProject(project: ProjectIdentifier) -> ColdSignal<SemanticVersion> {
		let repositoryURL = repositoryFileURLForProject(project)
		let fetchVersions = ColdSignal<()>.lazy {
				var error: NSError?
				if !NSFileManager.defaultManager().createDirectoryAtURL(CarthageDependencyRepositoriesURL, withIntermediateDirectories: true, attributes: nil, error: &error) {
					return .error(error ?? CarthageError.WriteFailed(CarthageDependencyRepositoriesURL).error)
				}

				let remoteURLString = self.repositoryURLStringForProject(project)
				if NSFileManager.defaultManager().createDirectoryAtURL(repositoryURL, withIntermediateDirectories: false, attributes: nil, error: nil) {
					// If we created the directory, we're now responsible for
					// cloning it.
					return cloneRepository(remoteURLString, repositoryURL)
						.then(.empty())
						.on(subscribed: {
							println("*** Cloning \(project.name)")
						})
				} else {
					return fetchRepository(repositoryURL, remoteURLString: remoteURLString)
						.then(.empty())
						.on(subscribed: {
							println("*** Fetching \(project.name)")
						})
				}
			}
			.then(listTags(repositoryURL))
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

		return contentsOfFileInRepository(repositoryURL, CarthageProjectCartfilePath, pinnedVersion.tag)
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

	/// Checks out the dependencies listed in the project's Cartfile.lock.
	public func checkoutLockedDependencies() -> ColdSignal<()> {
		return ColdSignal<CartfileLock>.lazy {
				return ColdSignal.fromResult(self.readCartfileLock())
			}
			.map { cartfileLock -> ColdSignal<Dependency<PinnedVersion>> in
				return ColdSignal.fromValues(cartfileLock.dependencies)
			}
			.merge(identity)
			.map { dependency -> ColdSignal<()> in
				let repositoryURL = self.repositoryFileURLForProject(dependency.project)
				let workingDirectoryURL = self.directoryURL.URLByAppendingPathComponent(dependency.project.relativePath, isDirectory: true)

				return checkoutRepositoryToDirectory(repositoryURL, workingDirectoryURL, dependency.version.tag)
					.then(.empty())
					.on(subscribed: {
						println("*** Checking out \(dependency.project.name) at \(dependency.version)")
					})
			}
			.merge(identity)
			.then(.empty())
	}
}
