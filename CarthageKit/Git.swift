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

public func launchGitTask(arguments: [String] = ["--version"], repositoryPath: String? = nil) -> ColdSignal<String> {
	let taskDescription = TaskDescription(launchPath: "/usr/bin/git", arguments: arguments, workingDirectoryPath: repositoryPath)
	return launchTask(taskDescription).map { NSString(data:$0, encoding: NSUTF8StringEncoding) as String }
}

public func repositoryRemote(repositoryPath: String) -> ColdSignal<String> {
	// TODO: Perhaps don't assume it is 'origin'?
	let arguments = [
		"config",
		"--get",
		"remote.origin.url",
	]
	return launchGitTask(arguments: arguments, repositoryPath: repositoryPath)
		.map { $0.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet()) }
}

/// Returns a cold signal that completes when cloning is complete, or errors if
/// the repository cannot be cloned.
public func cloneRepository(cloneURL: String, destinationPath: String) -> ColdSignal<String> {
    var isDirectory : ObjCBool = false

    if NSFileManager.defaultManager().fileExistsAtPath(destinationPath, isDirectory: &isDirectory) {
        if isDirectory {
			return repositoryRemote(destinationPath)
				.map({ remoteURL in
					let error = remoteURL == cloneURL ? CarthageError.RepositoryAlreadyCloned(location: destinationPath) : CarthageError.RepositoryRemoteMismatch(expected: cloneURL, actual: remoteURL)
					return ColdSignal.error(error.error)
				})
				.merge(identity)
        }
		let error = CarthageError.RepositoryCloneFailed(location: destinationPath)
        return ColdSignal.error(error.error)
    }

	let arguments = [
        "clone",
        cloneURL,
        destinationPath,
    ]
	return launchGitTask(arguments: arguments)
}

public func fetchRepository(repositoryPath: String) -> ColdSignal<String> {
	return launchGitTask(arguments: [ "fetch" ], repositoryPath: repositoryPath)
}

/*
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
*/
