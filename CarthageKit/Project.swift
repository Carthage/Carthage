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
				if let cloneURL = dependency.repository.cloneURL? {
					let task = NSTask()
					task.launchPath = "/usr/bin/git"
					let arguments = [ "clone", cloneURL.absoluteString!, "Dependencies/\(dependency.repository.name)-\(dependency.version)" ]
					task.arguments = arguments

					let argumentString = join(" ", arguments)

					println("\(task.launchPath) \(argumentString)")

					let pipe = NSPipe()
					task.standardOutput = pipe
					task.standardError = pipe
					let fileHandle = pipe.fileHandleForReading

					fileHandle.readabilityHandler =  { (handle: NSFileHandle?) -> () in
						if let data = handle?.availableData {
							let output: String? = NSString(data: data, encoding: NSUTF8StringEncoding)

							println(output!)
						}
					}

					task.launch()
					task.waitUntilExit()

					let terminationStatus = task.terminationStatus
					if terminationStatus != 0 {
						return failure()
					}
				}
			}
		}

		return success()
	}
}
