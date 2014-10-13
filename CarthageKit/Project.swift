//
//  Project.swift
//  Carthage
//
//  Created by Alan Rogers on 12/10/2014.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit

/// Represents a Project that is using Carthage.
public struct Project {
	/// Path to the root folder
    public var path: String

	/// The project's cart file
	public var cartfile: Cartfile?

	public init(path: String) {
		self.path = path

		let cartfileURL : NSURL? = NSURL.fileURLWithPath(self.path)?.URLByAppendingPathComponent("Cartfile")

		if (cartfileURL != nil) {
			let result : Result<Cartfile> = parseJSONAtURL(cartfileURL!)

			if (result.error() != nil) {
				return
			}
			cartfile = result.value()
		}
	}

	public func cloneDependencies() -> Result<()> {
		if let dependencies = cartfile?.dependencies {
			for dependency in dependencies {
				if let cloneURL = dependency.repository.cloneURL {
					let arguments = [
							"clone",
							"--depth=1",
							cloneURL.absoluteString!,
							"Dependencies/\(dependency.repository.name)-\(dependency.version)",
						]

					let taskDescription = TaskDescription(launchPath: "/usr/bin/git", arguments: arguments)
					let promise = launchTask(taskDescription)

					let exitStatus = promise.await()

					if exitStatus < 0 {
						return failure()
					}
				}
			}
		}

		return success()
	}
}
