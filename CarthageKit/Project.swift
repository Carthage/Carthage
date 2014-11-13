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
public struct Project {
	/// File URL to the root directory of the project.
	public let directoryURL: NSURL

	/// The project's Cartfile.
	public let cartfile: Cartfile

	/// The file URL to the project's Cartfile.lock.
	private var cartfileLockURL: NSURL {
		return directoryURL.URLByAppendingPathComponent(CarthageProjectCartfileLockPath, isDirectory: false)
	}

	/// Attempts to load project information from the given directory.
	public static func loadFromDirectory(directoryURL: NSURL) -> Result<Project> {
		precondition(directoryURL.fileURL)

		let cartfileURL = directoryURL.URLByAppendingPathComponent(CarthageProjectCartfilePath, isDirectory: false)

		var error: NSError?
		let cartfileContents = NSString(contentsOfURL: cartfileURL, encoding: NSUTF8StringEncoding, error: &error)
		if let cartfileContents = cartfileContents {
			return Cartfile.fromString(cartfileContents).map { cartfile in
				return self(directoryURL: directoryURL, cartfile: cartfile)
			}
		} else {
			return failure(error ?? CarthageError.NoCartfile.error)
		}
	}

	/// Reads the project's Cartfile.lock.
	public func readCartfileLock() -> Result<CartfileLock> {
		var error: NSError?
		let cartfileLockContents = NSString(contentsOfURL: cartfileLockURL, encoding: NSUTF8StringEncoding, error: &error)
		if let cartfileLockContents = cartfileLockContents {
			return CartfileLock.fromString(cartfileLockContents)
		} else {
			return failure(error ?? CarthageError.NoCartfile.error)
		}
	}

	/// Writes the given Cartfile.lock out to the project's directory.
	public func writeCartfileLock(cartfileLock: CartfileLock) -> Result<()> {
		var error: NSError?
		if cartfileLock.description.writeToURL(cartfileLockURL, atomically: true, encoding: NSUTF8StringEncoding, error: &error) {
			return success(())
		} else {
			return failure(error ?? RACError.Empty.error)
		}
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

/// Caches versions to avoid expensive lookups, and unnecessary
/// fetching/cloning.
typealias CachedVersionMap = [ProjectIdentifier: [SemanticVersion]]
private var cachedVersions: CachedVersionMap = [:]
private let cachedVersionsScheduler = QueueScheduler()

/// Sends all versions available for the given project.
///
/// This will automatically clone or fetch the project's repository as
/// necessary.
private func versionsForProject(project: ProjectIdentifier) -> ColdSignal<SemanticVersion> {
	let repositoryURL = repositoryFileURLForProject(project)
	let fetchVersions = ColdSignal<()>.lazy {
			var error: NSError?
			if !NSFileManager.defaultManager().createDirectoryAtURL(CarthageDependencyRepositoriesURL, withIntermediateDirectories: true, attributes: nil, error: &error) {
				return .error(error ?? RACError.Empty.error)
			}

			let remoteURLString = repositoryURLStringForProject(project)
			if NSFileManager.defaultManager().createDirectoryAtURL(repositoryURL, withIntermediateDirectories: false, attributes: nil, error: nil) {
				// If we created the directory, we're now responsible for
				// cloning it.
				return cloneRepository(remoteURLString, repositoryURL)
					.then(.empty())
					.on(subscribed: {
						println("*** Cloning \(project.name)")
					}, terminated: {
						println()
					})
			} else {
				return fetchRepository(repositoryURL, remoteURLString: remoteURLString)
					.then(.empty())
					.on(subscribed: {
						println("*** Fetching \(project.name)")
					}, terminated: {
						println()
					})
			}
		}
		.then(launchGitTask([ "tag" ], repositoryFileURL: repositoryURL))
		.map { (allTags: String) -> ColdSignal<String> in
			return ColdSignal { subscriber in
				let string = allTags as NSString

				string.enumerateSubstringsInRange(NSMakeRange(0, string.length), options: NSStringEnumerationOptions.ByLines | NSStringEnumerationOptions.Reverse) { (line, substringRange, enclosingRange, stop) in
					if subscriber.disposable.disposed {
						stop.memory = true
					}

					subscriber.put(.Next(Box(line as String)))
				}

				subscriber.put(.Completed)
			}
		}
		.merge(identity)
		.map { PinnedVersion(tag: $0) }
		.map { version -> ColdSignal<SemanticVersion> in
			return ColdSignal.fromResult(SemanticVersion.fromPinnedVersion(version))
				.catch { _ in .empty() }
		}
		.merge(identity)
		.on(next: { version in
			cachedVersionsScheduler.schedule {
				if var versions = cachedVersions[project] {
					versions.append(version)
					cachedVersions[project] = versions
				} else {
					cachedVersions[project] = [ version ]
				}
			}

			return ()
		})

	return ColdSignal.lazy {
			return .single(cachedVersions)
		}
		.subscribeOn(cachedVersionsScheduler)
		.deliverOn(QueueScheduler())
		.map { (versionsByProject: CachedVersionMap) -> ColdSignal<SemanticVersion> in
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
	let showObject = "\(pinnedVersion.tag):\(CarthageProjectCartfilePath)"

	let repositoryURL = repositoryFileURLForProject(dependency.project)
	return launchGitTask([ "show", showObject ], repositoryFileURL: repositoryURL, standardError: SinkOf<NSData> { _ in () })
		.catch { _ in .empty() }
		.tryMap { Cartfile.fromString($0) }
}

/// Attempts to determine the latest satisfiable version of the given project's
/// Carthage dependencies.
///
/// This will fetch dependency repositories as necessary, but will not check
/// them out into the project's working directory.
public func updatedDependenciesForProject(project: Project) -> ColdSignal<CartfileLock> {
	let resolver = Resolver(versionsForDependency: versionsForProject, cartfileForDependency: cartfileForDependency)
	return resolver.resolveDependenciesInCartfile(project.cartfile)
		.map { dependency -> Dependency<PinnedVersion> in
			return dependency.map { $0.pinnedVersion! }
		}
		.reduce(initial: []) { $0 + [ $1 ] }
		.map { CartfileLock(dependencies: $0) }
}

/// Updates the dependencies of the given project to the latest version. The
/// changes will be reflected in the working directory checkouts and
/// Cartfile.lock.
public func updateDependenciesInProject(project: Project) -> ColdSignal<()> {
	return updatedDependenciesForProject(project)
		.tryMap { cartfileLock -> Result<()> in
			return project.writeCartfileLock(cartfileLock)
		}
		.then(checkoutLockedDependencies(project))
}

/// Checks out the dependencies listed in the project's Cartfile.lock.
public func checkoutLockedDependencies(project: Project) -> ColdSignal<()> {
	return ColdSignal<CartfileLock>.lazy {
			return ColdSignal.fromResult(project.readCartfileLock())
		}
		.map { cartfileLock -> ColdSignal<Dependency<PinnedVersion>> in
			return ColdSignal.fromValues(cartfileLock.dependencies)
		}
		.merge(identity)
		.map { dependency -> ColdSignal<()> in
			let repositoryURL = repositoryFileURLForProject(dependency.project)
			let workingDirectoryURL = project.directoryURL.URLByAppendingPathComponent(dependency.project.relativePath, isDirectory: true)

			return ColdSignal.lazy {
				println("*** Checking out \(dependency.project.name)")

				var error: NSError?
				if !NSFileManager.defaultManager().createDirectoryAtURL(workingDirectoryURL, withIntermediateDirectories: true, attributes: nil, error: &error) {
					return .error(error ?? RACError.Empty.error)
				}

				var environment = NSProcessInfo.processInfo().environment as [String: String]
				environment["GIT_WORK_TREE"] = workingDirectoryURL.path!

				return launchGitTask([ "checkout", "--quiet", "--force", dependency.version.tag ], repositoryFileURL: repositoryURL, environment: environment)
					.then(.empty())
			}
		}
		.merge(identity)
		.then(.empty())
}
