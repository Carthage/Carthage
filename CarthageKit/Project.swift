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

/// Represents a project that is using Carthage.
public struct Project {
	/// File URL to the root directory of the project.
	public let directoryURL: NSURL

	/// The project's Cartfile.
	public let cartfile: Cartfile

	/// Attempts to load project information from the given directory.
	public static func loadFromDirectory(directoryURL: NSURL) -> Result<Project> {
		precondition(directoryURL.fileURL)

		let cartfileURL = directoryURL.URLByAppendingPathComponent("Cartfile", isDirectory: false)

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
