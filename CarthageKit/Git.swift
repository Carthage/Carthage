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

/// Sends each tag found in the given Git repository.
public func listTags(repositoryFileURL: NSURL) -> ColdSignal<String> {
	return launchGitTask([ "tag" ], repositoryFileURL: repositoryFileURL)
		.map { (allTags: String) -> ColdSignal<String> in
			return ColdSignal { subscriber in
				let string = allTags as NSString

				string.enumerateSubstringsInRange(NSMakeRange(0, string.length), options: NSStringEnumerationOptions.ByLines | NSStringEnumerationOptions.Reverse) { (line, substringRange, enclosingRange, stop) in
					if subscriber.disposable.disposed {
						stop.memory = true
					}

					subscriber.put(.Next(Box(line as String)))
				}

				subscriber.put(.Completed)
			}
		}
		.merge(identity)
}

/// Returns the text contents of the path at the given revision, or an error if
/// the path could not be loaded.
public func contentsOfFileInRepository(repositoryFileURL: NSURL, path: String, revision: String) -> ColdSignal<String> {
	let showObject = "\(revision):\(path)"
	return launchGitTask([ "show", showObject ], repositoryFileURL: repositoryFileURL, standardError: SinkOf<NSData> { _ in () })
}

/// Checks out the working tree of the given (ideally bare) repository, at the
/// specified revision, to the given folder. If the folder does not exist, it
/// will be created.
public func checkoutRepositoryToDirectory(repositoryFileURL: NSURL, workingDirectoryURL: NSURL, revision: String) -> ColdSignal<String> {
	return ColdSignal.lazy {
		var error: NSError?
		if !NSFileManager.defaultManager().createDirectoryAtURL(workingDirectoryURL, withIntermediateDirectories: true, attributes: nil, error: &error) {
			return .error(error ?? RACError.Empty.error)
		}

		var environment = NSProcessInfo.processInfo().environment as [String: String]
		environment["GIT_WORK_TREE"] = workingDirectoryURL.path!

		return launchGitTask([ "checkout", "--quiet", "--force", revision ], repositoryFileURL: repositoryFileURL, environment: environment)
	}
}
