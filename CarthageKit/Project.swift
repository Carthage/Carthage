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

/// Represents a Project that is using Carthage.
public struct Project {
	/// Path to the root folder
	public var path: String

	/// The project's Cartfile
	public let cartfile: Cartfile

	public init?(path: String) {
		self.path = path

		let cartfileURL: NSURL? = NSURL.fileURLWithPath(self.path)?.URLByAppendingPathComponent("Cartfile")
		if cartfileURL == nil { return nil }

		let cartfileContents: NSString? = NSString(contentsOfURL: cartfileURL!, encoding: NSUTF8StringEncoding, error: nil)
		if (cartfileContents == nil) { return nil }

		let cartfile: Cartfile? = Cartfile.fromString(cartfileContents!).value()
		if (cartfile == nil) { return nil }

		self.cartfile = cartfile!
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
