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

/// Represents a project that is using Carthage.
public struct Project {
	/// File URL to the root directory of the project.
	public let directoryURL: NSURL

	/// The project's Cartfile.
	public let cartfile: Cartfile

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
}

/// Returns a signal that completes when cloning completes successfully.
private func cloneProject(project: ProjectIdentifier, destinationURL: NSURL) -> ColdSignal<String> {
	switch project {
	case let .GitHub(repository):
		return cloneRepository(repository.cloneURLString, destinationURL)
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

	var updateSignal: ColdSignal<()>!
	if NSFileManager.defaultManager().fileExistsAtPath(repositoryURL.path!) {
		updateSignal = fetchRepository(repositoryURL)
			.then(.empty())
			.on(subscribed: {
				println("*** Fetching \(project.name)")
			}, terminated: {
				println()
			})
	} else {
		updateSignal = cloneProject(project, repositoryURL)
			.then(.empty())
			.on(subscribed: {
				println("*** Cloning \(project.name)")
			}, terminated: {
				println()
			})
	}

	let tagsSignal = launchGitTask([ "tag", "--sort=-version:refname" ], repositoryFileURL: repositoryURL)
	return updateSignal
		.then(tagsSignal)
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
		.concat(identity)
		.map { PinnedVersion(tag: $0) }
		.map { version -> ColdSignal<SemanticVersion> in
			return ColdSignal.fromResult(SemanticVersion.fromPinnedVersion(version))
				.catch { _ in .empty() }
		}
		.merge(identity)
}

/// Loads the Cartfile for the given dependency, at the given version.
private func cartfileForDependency(dependency: Dependency<SemanticVersion>) -> ColdSignal<Cartfile> {
	precondition(dependency.version.pinnedVersion != nil)

	let pinnedVersion = dependency.version.pinnedVersion!
	let showObject = "\(pinnedVersion.tag):\(CarthageProjectCartfilePath)"

	let repositoryURL = repositoryFileURLForProject(dependency.project)
	return launchGitTask([ "show", showObject ], repositoryFileURL: repositoryURL)
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

/// Checks out the dependencies listed in the project's Cartfile.
public func checkoutProjectDependencies(project: Project) -> ColdSignal<()> {
	return ColdSignal.fromValues(project.cartfile.dependencies)
		.map { dependency -> ColdSignal<String> in
			switch dependency.project {
			case let .GitHub(repository):
				let destinationURL = CarthageDependencyRepositoriesURL.URLByAppendingPathComponent(repository.name)

				var isDirectory: ObjCBool = false
				if NSFileManager.defaultManager().fileExistsAtPath(destinationURL.path!, isDirectory: &isDirectory) {
					return fetchRepository(destinationURL)
						.on(subscribed: {
							println("*** Fetching \(dependency.project.name)")
						}, terminated: {
							println()
						})
				} else {
					return cloneRepository(repository.cloneURLString, destinationURL)
						.on(subscribed: {
							println("*** Cloning \(dependency.project.name)")
						}, terminated: {
							println()
						})
				}
			}
		}
		.concat(identity)
		.then(.empty())
}
