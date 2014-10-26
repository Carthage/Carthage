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

public func runGitTask(withArguments arguments: [String] = ["--version"]) -> ColdSignal<String> {
	let taskDescription = TaskDescription(launchPath: "/usr/bin/git", arguments: arguments)
	return launchTask(taskDescription).map { NSString(data:$0, encoding: NSUTF8StringEncoding) as String }
}

public func repositoryRemote(repositoryPath: String) -> ColdSignal<String> {
	// TODO: Perhaps don't assume it's origin?
	let arguments = [
		"config",
		"--get",
		"remote.origin.url",
	]
	return runGitTask(withArguments: arguments)
}

/// Returns a cold signal that completes when cloning is complete, or errors if
/// the repository cannot be cloned.
public func cloneRepository(cloneURL: String, destinationPath: String) -> ColdSignal<String> {
    var isDirectory : ObjCBool = false

    if NSFileManager.defaultManager().fileExistsAtPath(destinationPath, isDirectory: &isDirectory) {
        if isDirectory {
			return repositoryRemote(destinationPath)
				.map({ remoteURL in
					var error : NSError? = nil

					if remoteURL == cloneURL {
						error = NSError(domain:"", code: -1, userInfo: [ NSLocalizedDescriptionKey: "Git repo already exists at \(destinationPath). Try calling fetchRepository() instead." ])
					} else {
						error = NSError(domain:"", code: -1, userInfo: [ NSLocalizedDescriptionKey: "A git repository with a different remoteURL exists at \(destinationPath). Please remove it before trying again." ])
					}
					return ColdSignal.error(error!)
				})
				.merge(identity)
        }
        return ColdSignal.error(NSError(domain:"", code: -1, userInfo: [ NSLocalizedDescriptionKey: "A file already exists at \(destinationPath) and it is not a git repository. Please remove it before trying again" ]))
    }

	let arguments = [
        "clone",
        cloneURL,
        destinationPath,
    ]
	return runGitTask(withArguments: arguments)
}

//public func updateDependency(dependency: Dependency, destinationPath: String) -> ColdSignal<()> {
//    let arguments = [
//        "fetch",
//        dependency.repository.cloneURL.absoluteString!,
//    ]
//	return runGitTask(withArguments: arguments)
//}
//
//public func checkoutDependency(dependency: Dependency, destinationPath: String) -> ColdSignal<()> {
//	let dependencyPath : String = dependenciesPath.stringByAppendingPathComponent("\(dependency.repository.name)")
//
//	let cloneURLString = NSURL.fileURLWithPath(dependencyPath, isDirectory:true)?.absoluteString?
//
//	if cloneURLString == nil {
//		// TODO: Real errors
//        return ColdSignal.error(NSError(domain:"", code: -1, userInfo: [ NSLocalizedDescriptionKey: "The dependency \(dependency) doesn't have a URL to clone from." ]))
//	}
//
//	var arguments = [
//        "clone",
//		"--local",
//		cloneURLString!,
//        destinationPath,
//    ]
//
//	if let versionString = dependency.version.version?.raw {
//		arguments = arguments + ["--branch=\(versionString)"]
//	}
//
//	return runGitTask(withArguments: arguments)
//}
