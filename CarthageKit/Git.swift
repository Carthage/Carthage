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

public func repositoryRemote(repositoryURL: NSURL) -> ColdSignal<String> {
	// TODO: Perhaps don't assume it is 'origin'?
	let arguments = [
		"config",
		"--get",
		"remote.origin.url",
	]
	return launchGitTask(arguments: arguments, repositoryURL: repositoryURL)
		.map { $0.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet()) }
}

/// Returns a cold signal that completes when cloning is complete, or errors if
/// the repository cannot be cloned.
public func cloneRepository(cloneURL: String, destinationURL: NSURL) -> ColdSignal<String> {
	var isDirectory: ObjCBool = false

	if NSFileManager.defaultManager().fileExistsAtPath(destinationURL.path!, isDirectory: &isDirectory) {
		if isDirectory {
			return repositoryRemote(destinationURL)
				.map({ remoteURL in
					let error = remoteURL == cloneURL ? CarthageError.RepositoryAlreadyCloned(location: destinationURL) : CarthageError.RepositoryRemoteMismatch(expected: cloneURL, actual: remoteURL)
					return ColdSignal.error(error.error)
				})
				.merge(identity)
		}
		let error = CarthageError.RepositoryCloneFailed(location: destinationURL)
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
