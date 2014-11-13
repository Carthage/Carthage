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

/// Shells out to `git` with the given arguments, optionally in the directory
/// of an existing repository.
public func launchGitTask(arguments: [String], repositoryFileURL: NSURL? = nil, standardError: SinkOf<NSData>? = nil, environment: [String: String]? = nil) -> ColdSignal<String> {
	let taskDescription = TaskDescription(launchPath: "/usr/bin/git", arguments: arguments, workingDirectoryPath: repositoryFileURL?.path, environment: environment)

	return launchTask(taskDescription, standardError: standardError)
		.map { NSString(data: $0, encoding: NSUTF8StringEncoding) as String }
}

/// Returns a signal that completes when cloning completes successfully.
public func cloneRepository(cloneURLString: String, destinationURL: NSURL) -> ColdSignal<String> {
	precondition(destinationURL.fileURL)

	return launchGitTask([ "clone", "--bare", "--quiet", "--recursive", cloneURLString, destinationURL.path! ])
}

/// Returns a signal that completes when the fetch completes successfully.
public func fetchRepository(repositoryFileURL: NSURL, remoteURLString: String? = nil) -> ColdSignal<String> {
	precondition(repositoryFileURL.fileURL)

	var arguments = [ "fetch", "--tags", "--prune", "--quiet" ]
	if let remoteURLString = remoteURLString {
		arguments.append(remoteURLString)
	}

	return launchGitTask(arguments, repositoryFileURL: repositoryFileURL)
}
