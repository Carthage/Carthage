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
public func launchGitTask(arguments: [String], repositoryFileURL: NSURL? = nil) -> ColdSignal<String> {
	let taskDescription = TaskDescription(launchPath: "/usr/bin/git", arguments: arguments, workingDirectoryPath: repositoryFileURL?.path)
	return launchTask(taskDescription).map { NSString(data: $0, encoding: NSUTF8StringEncoding) as String }
}

/// Returns a signal that completes when cloning completes successfully.
public func cloneRepository(cloneURLString: String, destinationURL: NSURL) -> ColdSignal<String> {
	precondition(destinationURL.fileURL)

	return launchGitTask([ "clone", "--bare", "--recursive", cloneURLString, destinationURL.path! ])
}

/// Returns a signal that completes when the fetch completes successfully.
public func fetchRepository(repositoryFileURL: NSURL) -> ColdSignal<String> {
	precondition(repositoryFileURL.fileURL)

	return launchGitTask([ "fetch", "--tags", "--prune" ], repositoryFileURL: repositoryFileURL)
}
