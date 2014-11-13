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

public func launchGitTask(arguments: [String] = [], repositoryURL: NSURL? = nil) -> ColdSignal<String> {
	let taskDescription = TaskDescription(launchPath: "/usr/bin/git", arguments: arguments, workingDirectoryPath: repositoryURL?.path)
	return launchTask(taskDescription).map { NSString(data:$0, encoding: NSUTF8StringEncoding) as String }
}

/// Returns a cold signal that completes when cloning is complete, or errors if
/// the repository cannot be cloned.
public func cloneRepository(cloneURL: String, destinationURL: NSURL) -> ColdSignal<String> {
	var isDirectory: ObjCBool = false

	if NSFileManager.defaultManager().fileExistsAtPath(destinationURL.path!, isDirectory: &isDirectory) {
        let error = isDirectory ? CarthageError.RepositoryAlreadyCloned(location: destinationURL) : CarthageError.RepositoryCloneFailed(location: destinationURL)
		return ColdSignal.error(error.error)
	}

	let arguments = [
		"clone",
		"--bare",
		"--recursive",
		cloneURL,
		destinationURL.path!,
	]
	return launchGitTask(arguments: arguments)
}

public func fetchRepository(repositoryURL: NSURL) -> ColdSignal<String> {
	return launchGitTask(arguments: [ "fetch" ], repositoryURL: repositoryURL)
}
