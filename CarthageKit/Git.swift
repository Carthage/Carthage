//
//  Git.swift
//  Carthage
//
//  Created by Alan Rogers on 14/10/2014.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit

let dependenciesPath = "~/.carthage/dependencies".stringByExpandingTildeInPath

public func cloneOrUpdateDependency(dependency: Dependency) -> Result<()> {
    let destinationPath = dependenciesPath.stringByAppendingPathComponent("\(dependency.repository.name)")

    var isDirectory : ObjCBool = false

    if NSFileManager.defaultManager().fileExistsAtPath(destinationPath, isDirectory: &isDirectory) {
        if isDirectory {
            // This is probably a git repo
            // TODO: Also check the remote matches and warn if it doesn't
            return updateDependency(dependency, destinationPath)
        }
        println("A file already exists at \(destinationPath) and it is not a git repository. Please delete it and try again.")
        return failure()
    }

	return cloneDependency(dependency, destinationPath)
}

public func cloneDependency(dependency: Dependency, destinationPath: String) -> Result<()> {
    let arguments = [
        "clone",
        "--bare",
        dependency.repository.cloneURL.absoluteString!,
        destinationPath,
    ]

    let taskDescription = TaskDescription(launchPath: "/usr/bin/git", arguments: arguments)
    let promise = launchTask(taskDescription)

    let exitStatus = promise.await()

    if exitStatus < 0 {
        return failure()
    }
    return success()
}

public func updateDependency(dependency: Dependency, destinationPath: String) -> Result<()> {
    let arguments = [
        "fetch",
        dependency.repository.cloneURL.absoluteString!,
    ]

    let taskDescription = TaskDescription(launchPath: "/usr/bin/git", workingDirectoryPath: destinationPath, arguments: arguments)
    let promise = launchTask(taskDescription)

    let exitStatus = promise.await()

    if exitStatus < 0 {
        return failure()
    }
    return success()
}

public func checkoutDependency(dependency: Dependency, destinationPath: String) -> Result<()> {
	let dependencyPath : String = dependenciesPath.stringByAppendingPathComponent("\(dependency.repository.name)")

	let cloneURL : String = NSURL.fileURLWithPath(dependencyPath, isDirectory:true)!.absoluteString!

	var arguments = [
        "clone",
		"--local",
		cloneURL,
        destinationPath,
    ]

	if strlen(dependency.versionString) > 0 {
		arguments = arguments + ["--branch=\(dependency.versionString)"]
	}

    let taskDescription = TaskDescription(launchPath: "/usr/bin/git", arguments: arguments)
    let promise = launchTask(taskDescription)

    let exitStatus = promise.await()

    if exitStatus < 0 {
        return failure()
    }
    return success()
}
