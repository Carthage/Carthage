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

let dependenciesURL = NSURL.fileURLWithPath("~/.carthage/dependencies".stringByExpandingTildeInPath, isDirectory:true)!

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

/// Checks out the dependencies listed in the project's Cartfile
public func checkoutProjectDependencies(project: Project) -> ColdSignal<()> {
    return ColdSignal.fromValues(project.cartfile.dependencies)
        .map({ dependency -> ColdSignal<String> in
            let destinationURL = dependenciesURL.URLByAppendingPathComponent("\(dependency.repository.name)")
            return cloneRepository(dependency.repository.cloneURL.absoluteString!, destinationURL)
                .catch( {error in
                    println(error.localizedDescription)
                    if error.code == CarthageError.RepositoryAlreadyCloned(location: destinationURL).error.code {
                        return fetchRepository(destinationURL).catch { _ in return .empty() }
                    }
                    return ColdSignal.empty()
                })
        })
        .concat(identity)
        .then(.empty())
}
