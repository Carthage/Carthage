//
//  Git.swift
//  Carthage
//
//  Created by Alan Rogers on 14/10/2014.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa

let dependenciesPath = "~/.carthage/dependencies".stringByExpandingTildeInPath

public func runGitTask(withArguments arguments: [String] = ["git", "--version"]) -> ColdSignal<()> {
	let taskDescription = TaskDescription(launchPath: "/usr/bin/git", arguments: arguments)
	return launchTask(taskDescription).then(.empty())
}

public func cloneOrUpdateDependency(dependency: Dependency) -> ColdSignal<()> {
    let destinationPath = dependenciesPath.stringByAppendingPathComponent("\(dependency.repository.name)")

    var isDirectory : ObjCBool = false

    if NSFileManager.defaultManager().fileExistsAtPath(destinationPath, isDirectory: &isDirectory) {
        if isDirectory {
            // This is probably a git repo
            // TODO: Also check the remote matches and warn if it doesn't
            return updateDependency(dependency, destinationPath)
        }
		// TODO: Real errors
        return ColdSignal.error(NSError(domain:"", code: -1, userInfo: [ NSLocalizedDescriptionKey: "A file already exists at \(destinationPath) and it is not a git repository. Please delete it and try again." ]))
    }

	return cloneDependency(dependency, destinationPath)
}

public func cloneDependency(dependency: Dependency, destinationPath: String) -> ColdSignal<()> {
    let arguments = [
        "clone",
        dependency.repository.cloneURL.absoluteString!,
        destinationPath,
    ]
	return runGitTask(withArguments: arguments)
}

public func updateDependency(dependency: Dependency, destinationPath: String) -> ColdSignal<()> {
    let arguments = [
        "fetch",
        dependency.repository.cloneURL.absoluteString!,
    ]
	return runGitTask(withArguments: arguments)
}

public func checkoutDependency(dependency: Dependency, destinationPath: String) -> ColdSignal<()> {
	let dependencyPath : String = dependenciesPath.stringByAppendingPathComponent("\(dependency.repository.name)")

	let cloneURLString = NSURL.fileURLWithPath(dependencyPath, isDirectory:true)?.absoluteString?

	if cloneURLString == nil {
		// TODO: Real errors
        return ColdSignal.error(NSError(domain:"", code: -1, userInfo: [ NSLocalizedDescriptionKey: "The dependency \(dependency) doesn't have a URL to clone from." ]))
	}

	var arguments = [
        "clone",
		"--local",
		cloneURLString!,
        destinationPath,
    ]

	if let versionString = dependency.version.version?.raw {
		arguments = arguments + ["--branch=\(versionString)"]
	}

	return runGitTask(withArguments: arguments)
}
