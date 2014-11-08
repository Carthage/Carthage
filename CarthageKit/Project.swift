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

	/// The project's cart file
	public let cartfile: Cartfile?

	public init(path: String) {
		self.path = path

		if let cartfileURL = NSURL.fileURLWithPath(self.path)?.URLByAppendingPathComponent("Cartfile") {
			if let cartfile = NSString(contentsOfURL: cartfileURL, encoding: NSUTF8StringEncoding, error: nil) {
				self.cartfile = Cartfile.fromString(cartfile).value()
			}
		}
	}

	public func checkoutDependencies() -> ColdSignal<()> {
		if let dependencies = cartfile?.dependencies {
			return ColdSignal.fromValues(dependencies)
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
		return ColdSignal.error(CarthageError.NoCartfile.error)
	}
}
