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

/// A Git submodule.
public struct Submodule: Equatable {
	/// The name of the submodule. Usually (but not always) the same as the
	/// path.
	public let name: String

	/// The relative path at which the submodule is checked out.
	public let path: String

	/// The URL from which the submodule should be cloned, if present.
	public let URLString: String

	/// The SHA checked out in the submodule.
	public let SHA: String

	public init(name: String, path: String, URLString: String, SHA: String) {
		self.name = name
		self.path = path
		self.URLString = URLString
		self.SHA = SHA
	}
}

public func ==(lhs: Submodule, rhs: Submodule) -> Bool {
	return lhs.name == rhs.name && lhs.path == rhs.path && lhs.URLString == rhs.URLString && lhs.SHA == rhs.SHA
}

extension Submodule: Hashable {
	public var hashValue: Int {
		return name.hashValue
	}
}

extension Submodule: Printable {
	public var description: String {
		return "\(name) @ \(SHA)"
	}
}

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

	return launchGitTask([ "clone", "--bare", "--quiet", cloneURLString, destinationURL.path! ])
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

/// Clones the given submodule into the working directory of its parent
/// repository, but without any Git metadata.
public func cloneSubmoduleInWorkingDirectory(submodule: Submodule, workingDirectoryURL: NSURL) -> ColdSignal<()> {
	let submoduleDirectoryURL = workingDirectoryURL.URLByAppendingPathComponent(submodule.path, isDirectory: true)
	let purgeGitDirectories = ColdSignal<()> { subscriber in
		let enumerator = NSFileManager.defaultManager().enumeratorAtURL(submoduleDirectoryURL, includingPropertiesForKeys: [ NSURLIsDirectoryKey!, NSURLNameKey! ], options: nil, errorHandler: nil)!

		while !subscriber.disposable.disposed {
			let URL: NSURL! = enumerator.nextObject() as? NSURL
			if URL == nil {
				break
			}

			var name: AnyObject?
			var error: NSError?
			if !URL.getResourceValue(&name, forKey: NSURLNameKey, error: &error) {
				subscriber.put(.Error(error ?? RACError.Empty.error))
				return
			}

			if let name = name as? NSString {
				if name != ".git" {
					continue
				}
			} else {
				continue
			}

			var isDirectory: AnyObject?
			if !URL.getResourceValue(&isDirectory, forKey: NSURLIsDirectoryKey, error: &error) || isDirectory == nil {
				subscriber.put(.Error(error ?? RACError.Empty.error))
				return
			}

			if let directory = isDirectory?.boolValue {
				if directory {
					enumerator.skipDescendants()
				}
			}

			if !NSFileManager.defaultManager().removeItemAtURL(URL, error: &error) {
				subscriber.put(.Error(error ?? RACError.Empty.error))
				return
			}
		}

		subscriber.put(.Completed)
	}

	return launchGitTask([ "clone", submodule.URLString, submodule.path, "--depth", "1", "--quiet", "--recursive" ], repositoryFileURL: workingDirectoryURL)
		.then(purgeGitDirectories)
}

/// Parses each key/value entry from the given config file contents, optionally
/// stripping a known prefix/suffix off of each key.
private func parseConfigEntries(contents: String, keyPrefix: String = "", keySuffix: String = "") -> ColdSignal<(String, String)> {
	let entries = split(contents, { $0 == "\0" }, allowEmptySlices: false)

	return ColdSignal { subscriber in
		for entry in entries {
			if subscriber.disposable.disposed {
				break
			}

			let components = split(entry, { $0 == "\n" }, maxSplit: 1, allowEmptySlices: true)
			if components.count != 2 {
				continue
			}

			let key = components[0]
			let value = components[1]

			if !key.hasPrefix(keyPrefix) || !key.hasSuffix(keySuffix) {
				continue
			}

			let suffixLength = countElements(keySuffix)
			let prefixLength = countElements(keyPrefix)

			var keyCharacters = Array(key)
			keyCharacters.removeRange(Range(start: keyCharacters.count - suffixLength, end: suffixLength))
			keyCharacters.removeRange(Range(start: 0, end: prefixLength))

			let trimmedKey = String(keyCharacters)
			subscriber.put(.Next(Box((trimmedKey, value))))
		}

		subscriber.put(.Completed)
	}
}

/// Determines the SHA that the submodule at the given path is pinned to, in the
/// revision of the parent repository specified.
public func submoduleSHAForPath(path: String, repositoryFileURL: NSURL, revision: String) -> ColdSignal<String> {
	return launchGitTask([ "ls-tree", "-z", revision, path ], repositoryFileURL: repositoryFileURL)
		.tryMap { string -> Result<String> in
			// Example:
			// 160000 commit 083fd81ecf00124cbdaa8f86ef10377737f6325a	External/ObjectiveGit
			let components = split(string, { $0 == " " || $0 == "\t" }, maxSplit: 3, allowEmptySlices: false)
			if components.count >= 3 {
				return success(components[2])
			} else {
				// TODO: Real error here.
				return failure()
			}
		}
}

/// Returns each submodule found in the given repository revision, or an empty
/// signal if none exist.
public func submodulesInRepository(repositoryFileURL: NSURL, revision: String) -> ColdSignal<Submodule> {
	let modulesObject = "\(revision):.gitmodules"
	let baseArguments = [ "config", "--blob", modulesObject, "-z" ]

	return launchGitTask(baseArguments + [ "--get-regexp", "submodule\\..*\\.path" ], repositoryFileURL: repositoryFileURL, standardError: SinkOf<NSData> { _ in () })
		.catch { _ in .empty() }
		.map { parseConfigEntries($0, keyPrefix: "submodule.", keySuffix: ".path") }
		.merge(identity)
		.map { (name, path) -> ColdSignal<Submodule> in
			return launchGitTask(baseArguments + [ "--get", "submodule.\(name).url" ], repositoryFileURL: repositoryFileURL)
				// TODO: This should be a zip.
				.combineLatestWith(submoduleSHAForPath(path, repositoryFileURL, revision))
				.map { (URLString, SHA) in
					return Submodule(name: name, path: path, URLString: URLString, SHA: SHA)
				}
		}
		.merge(identity)
}
