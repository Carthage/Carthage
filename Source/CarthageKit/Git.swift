//
//  Git.swift
//  Carthage
//
//  Created by Alan Rogers on 14/10/2014.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import Result
import ReactiveCocoa
import ReactiveTask

/// Represents a URL for a Git remote.
public struct GitURL: Equatable {
	/// The string representation of the URL.
	public let URLString: String

	/// A normalized URL string, without protocol, authentication, or port
	/// information. This is mostly useful for comparison, and not for any
	/// actual Git operations.
	private var normalizedURLString: String {
		let parsedURL: NSURL? = NSURL(string: URLString)

		if let parsedURL = parsedURL {
			// Normal, valid URL.
			let host = parsedURL.host ?? ""
			let path = stripGitSuffix(parsedURL.path ?? "")
			return "\(host)\(path)"
		} else if URLString.hasPrefix("/") {
			// Local path.
			return stripGitSuffix(URLString)
		} else {
			// scp syntax.
			var strippedURLString = URLString

			if let index = find(strippedURLString, "@") {
				strippedURLString.removeRange(Range(start: strippedURLString.startIndex, end: index))
			}

			var host = ""
			if let index = find(strippedURLString, ":") {
				host = strippedURLString[Range(start: strippedURLString.startIndex, end: index.predecessor())]
				strippedURLString.removeRange(Range(start: strippedURLString.startIndex, end: index))
			}

			var path = strippedURLString
			if !path.hasPrefix("/") {
				// This probably isn't strictly legit, but we'll have a forward
				// slash for other URL types.
				path.insert("/", atIndex: path.startIndex)
			}

			return "\(host)\(path)"
		}
	}

	/// The name of the repository, if it can be inferred from the URL.
	public var name: String? {
		let components = split(URLString, allowEmptySlices: false) { $0 == "/" }

		return components.last.map { self.stripGitSuffix($0) }
	}

	public init(_ URLString: String) {
		self.URLString = URLString
	}

	/// Strips any trailing .git in the given name, if one exists.
	private func stripGitSuffix(string: String) -> String {
		if string.hasSuffix(".git") {
			let nsString = string as NSString
			return nsString.substringToIndex(nsString.length - 4) as String
		} else {
			return string
		}
	}
}

public func ==(lhs: GitURL, rhs: GitURL) -> Bool {
	return lhs.normalizedURLString == rhs.normalizedURLString
}

extension GitURL: Hashable {
	public var hashValue: Int {
		return normalizedURLString.hashValue
	}
}

extension GitURL: Printable {
	public var description: String {
		return URLString
	}
}

/// A Git submodule.
public struct Submodule: Equatable {
	/// The name of the submodule. Usually (but not always) the same as the
	/// path.
	public let name: String

	/// The relative path at which the submodule is checked out.
	public let path: String

	/// The URL from which the submodule should be cloned, if present.
	public var URL: GitURL

	/// The SHA checked out in the submodule.
	public var SHA: String

	public init(name: String, path: String, URL: GitURL, SHA: String) {
		self.name = name
		self.path = path
		self.URL = URL
		self.SHA = SHA
	}
}

public func ==(lhs: Submodule, rhs: Submodule) -> Bool {
	return lhs.name == rhs.name && lhs.path == rhs.path && lhs.URL == rhs.URL && lhs.SHA == rhs.SHA
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
public func launchGitTask(var arguments: [String], fileHandle: NSFileHandle, repositoryFileURL: NSURL? = nil, standardInput: SignalProducer<NSData, NoError>? = nil, environment: [String: String]? = nil) -> SignalProducer<String, CarthageError> {
	let escapedArgs = map(arguments) {
		return ($0 as NSString).containsString(" ") ? "\"\($0)\"" : $0
	}
	
	let argsStr = " ".join(escapedArgs)
	let workingDir = (repositoryFileURL != nil && repositoryFileURL!.path != nil
		? "\n      working dir: \(repositoryFileURL!.path!)"
		: "")
	let gitCallStr = "\n    Calling Git\n      arguments: \(argsStr)\(workingDir)\n" as NSString
	
	fileHandle.writeData(gitCallStr.dataUsingEncoding(NSUTF8StringEncoding)!)
	
	let taskDescription = TaskDescription(launchPath: "/usr/bin/env", arguments: [ "git" ] + arguments, workingDirectoryPath: repositoryFileURL?.path, environment: environment, standardInput: standardInput)

	return launchTask(taskDescription)
		|> mapError { .TaskError($0) }
		|> map { taskEvent in
			return taskEvent.value.map { data in
				return NSString(data: data, encoding: NSUTF8StringEncoding)! as String
			}
		}
		|> ignoreNil
}

/// Returns a signal that completes when cloning completes successfully.
public func cloneRepository(cloneURL: GitURL, destinationURL: NSURL, fileHandle: NSFileHandle, bare: Bool = true) -> SignalProducer<String, CarthageError> {
	precondition(destinationURL.fileURL)

	var arguments = [ "clone" ]
	if bare {
		arguments.append("--bare")
	}

	return launchGitTask(arguments + [ cloneURL.URLString, destinationURL.path! ], fileHandle)
}

/// Returns a signal that completes when the fetch completes successfully.
public func fetchRepository(repositoryFileURL: NSURL, fileHandle: NSFileHandle, remoteURL: GitURL? = nil, refspec: String? = nil) -> SignalProducer<String, CarthageError> {
	precondition(repositoryFileURL.fileURL)

	var arguments = [ "fetch", "--tags", "--prune" ]
	if let remoteURL = remoteURL {
		arguments.append(remoteURL.URLString)
	}

	if let refspec = refspec {
		arguments.append(refspec)
	}

	return launchGitTask(arguments, fileHandle, repositoryFileURL: repositoryFileURL)
}

/// Sends each tag found in the given Git repository.
public func listTags(repositoryFileURL: NSURL, fileHandle: NSFileHandle) -> SignalProducer<String, CarthageError> {
	return launchGitTask([ "tag" ], fileHandle, repositoryFileURL: repositoryFileURL)
		|> flatMap(.Concat) { (allTags: String) -> SignalProducer<String, CarthageError> in
			return SignalProducer { observer, disposable in
				let string = allTags as NSString

				string.enumerateSubstringsInRange(NSMakeRange(0, string.length), options: NSStringEnumerationOptions.ByLines | NSStringEnumerationOptions.Reverse) { line, substringRange, enclosingRange, stop in
					if disposable.disposed {
						stop.memory = true
					}

					sendNext(observer, line as String)
				}

				sendCompleted(observer)
			}
		}
}

/// Returns the text contents of the path at the given revision, or an error if
/// the path could not be loaded.
public func contentsOfFileInRepository(repositoryFileURL: NSURL, path: String, fileHandle: NSFileHandle, revision: String = "HEAD") -> SignalProducer<String, CarthageError> {
	let showObject = "\(revision):\(path)"
	return launchGitTask([ "show", showObject ], fileHandle, repositoryFileURL: repositoryFileURL)
}

/// Checks out the working tree of the given (ideally bare) repository, at the
/// specified revision, to the given folder. If the folder does not exist, it
/// will be created.
public func checkoutRepositoryToDirectory(repositoryFileURL: NSURL, workingDirectoryURL: NSURL, fileHandle: NSFileHandle, revision: String = "HEAD", shouldCloneSubmodule: Submodule -> Bool = { _ in true }) -> SignalProducer<(), CarthageError> {
	return SignalProducer.try {
			var error: NSError?
			if !NSFileManager.defaultManager().createDirectoryAtURL(workingDirectoryURL, withIntermediateDirectories: true, attributes: nil, error: &error) {
				return .failure(CarthageError.RepositoryCheckoutFailed(workingDirectoryURL: workingDirectoryURL, reason: "Could not create working directory", underlyingError: error))
			}

			var environment = NSProcessInfo.processInfo().environment as! [String: String]
			environment["GIT_WORK_TREE"] = workingDirectoryURL.path!
			return .success(environment)
		}
		|> flatMap(.Concat) { environment in launchGitTask([ "checkout", "--force", revision ], fileHandle, repositoryFileURL: repositoryFileURL, environment: environment) }
		|> then(cloneSubmodulesForRepository(repositoryFileURL, workingDirectoryURL, fileHandle, revision: revision, shouldCloneSubmodule: shouldCloneSubmodule))
}

/// Clones matching submodules for the given repository at the specified
/// revision, into the given working directory.
public func cloneSubmodulesForRepository(repositoryFileURL: NSURL, workingDirectoryURL: NSURL, fileHandle: NSFileHandle, revision: String = "HEAD", shouldCloneSubmodule: Submodule -> Bool = { _ in true }) -> SignalProducer<(), CarthageError> {
	return submodulesInRepository(repositoryFileURL, fileHandle, revision: revision)
		|> flatMap(.Concat) { submodule -> SignalProducer<(), CarthageError> in
			if shouldCloneSubmodule(submodule) {
				return cloneSubmoduleInWorkingDirectory(submodule, workingDirectoryURL, fileHandle)
			} else {
				return .empty
			}
		}
		|> filter { _ in false }
}

/// Clones the given submodule into the working directory of its parent
/// repository, but without any Git metadata.
public func cloneSubmoduleInWorkingDirectory(submodule: Submodule, workingDirectoryURL: NSURL, fileHandle: NSFileHandle) -> SignalProducer<(), CarthageError> {
	let submoduleDirectoryURL = workingDirectoryURL.URLByAppendingPathComponent(submodule.path, isDirectory: true)
	let purgeGitDirectories = NSFileManager.defaultManager().carthage_enumeratorAtURL(submoduleDirectoryURL, includingPropertiesForKeys: [ NSURLIsDirectoryKey, NSURLNameKey ], options: nil, catchErrors: true)
		|> flatMap(.Merge) { enumerator, URL -> SignalProducer<(), CarthageError> in
			var name: AnyObject?
			var error: NSError?
			if !URL.getResourceValue(&name, forKey: NSURLNameKey, error: &error) {
				return SignalProducer(error: CarthageError.RepositoryCheckoutFailed(workingDirectoryURL: submoduleDirectoryURL, reason: "could not enumerate name of descendant at \(URL.path!)", underlyingError: error))
			}

			if let name = name as? NSString {
				if name != ".git" {
					return .empty
				}
			} else {
				return .empty
			}

			var isDirectory: AnyObject?
			if !URL.getResourceValue(&isDirectory, forKey: NSURLIsDirectoryKey, error: &error) || isDirectory == nil {
				return SignalProducer(error: CarthageError.RepositoryCheckoutFailed(workingDirectoryURL: submoduleDirectoryURL, reason: "could not determine whether \(URL.path!) is a directory", underlyingError: error))
			}

			if let directory = isDirectory?.boolValue {
				if directory {
					enumerator.skipDescendants()
				}
			}

			if NSFileManager.defaultManager().removeItemAtURL(URL, error: &error) {
				return .empty
			} else {
				return SignalProducer(error: CarthageError.RepositoryCheckoutFailed(workingDirectoryURL: submoduleDirectoryURL, reason: "could not remove \(URL.path!)", underlyingError: error))
			}
		}

	return SignalProducer.try {
			var error: NSError?
			if !NSFileManager.defaultManager().removeItemAtURL(submoduleDirectoryURL, error: &error) {
				return .failure(CarthageError.RepositoryCheckoutFailed(workingDirectoryURL: submoduleDirectoryURL, reason: "could not remove submodule checkout", underlyingError: error))
			}

			return .success(workingDirectoryURL.URLByAppendingPathComponent(submodule.path))
		}
		|> flatMap(.Concat) { submoduleDirectoryURL in cloneRepository(submodule.URL, submoduleDirectoryURL, fileHandle, bare: false) }
		|> then(checkoutSubmodule(submodule, submoduleDirectoryURL, fileHandle))
		|> then(purgeGitDirectories)
}

/// Recursively checks out the given submodule's revision, in its working
/// directory.
private func checkoutSubmodule(submodule: Submodule, submoduleWorkingDirectoryURL: NSURL, fileHandle: NSFileHandle) -> SignalProducer<(), CarthageError> {
	return launchGitTask([ "checkout", submodule.SHA ], fileHandle, repositoryFileURL: submoduleWorkingDirectoryURL)
		|> then(launchGitTask([ "submodule", "update", "--init", "--recursive" ], fileHandle, repositoryFileURL: submoduleWorkingDirectoryURL))
		|> then(.empty)
}

/// Parses each key/value entry from the given config file contents, optionally
/// stripping a known prefix/suffix off of each key.
private func parseConfigEntries(contents: String, keyPrefix: String = "", keySuffix: String = "") -> SignalProducer<(String, String), NoError> {
	let entries = split(contents, allowEmptySlices: false) { $0 == "\0" }

	return SignalProducer { observer, disposable in
		for entry in entries {
			if disposable.disposed {
				break
			}

			let components = split(entry, maxSplit: 1, allowEmptySlices: true) { $0 == "\n" }
			if components.count != 2 {
				continue
			}

			let value = components[1]
			let scanner = NSScanner(string: components[0])

			if !scanner.scanString(keyPrefix, intoString: nil) {
				continue
			}

			var key: NSString?
			if !scanner.scanUpToString(keySuffix, intoString: &key) {
				continue
			}

			if let key = key as? String {
				sendNext(observer, (key, value))
			}
		}

		sendCompleted(observer)
	}
}

/// Determines the SHA that the submodule at the given path is pinned to, in the
/// revision of the parent repository specified.
public func submoduleSHAForPath(repositoryFileURL: NSURL, path: String, fileHandle: NSFileHandle, revision: String = "HEAD") -> SignalProducer<String, CarthageError> {
	return launchGitTask([ "ls-tree", "-z", revision, path ], fileHandle, repositoryFileURL: repositoryFileURL)
		|> tryMap { string in
			// Example:
			// 160000 commit 083fd81ecf00124cbdaa8f86ef10377737f6325a	External/ObjectiveGit
			let components = split(string, maxSplit: 3, allowEmptySlices: false) { $0 == " " || $0 == "\t" }
			if components.count >= 3 {
				return .success(components[2])
			} else {
				return .failure(CarthageError.ParseError(description: "expected submodule commit SHA in ls-tree output: \(string)"))
			}
		}
}

/// Returns each submodule found in the given repository revision, or an empty
/// signal if none exist.
public func submodulesInRepository(repositoryFileURL: NSURL, fileHandle: NSFileHandle, revision: String = "HEAD") -> SignalProducer<Submodule, CarthageError> {
	let modulesObject = "\(revision):.gitmodules"
	let baseArguments = [ "config", "--blob", modulesObject, "-z" ]

	return launchGitTask(baseArguments + [ "--get-regexp", "submodule\\..*\\.path" ], fileHandle, repositoryFileURL: repositoryFileURL)
		|> catch { _ in SignalProducer<String, NoError>.empty }
		|> flatMap(.Concat) { value in parseConfigEntries(value, keyPrefix: "submodule.", keySuffix: ".path") }
		|> promoteErrors(CarthageError.self)
		|> flatMap(.Concat) { name, path -> SignalProducer<Submodule, CarthageError> in
			return launchGitTask(baseArguments + [ "--get", "submodule.\(name).url" ], fileHandle, repositoryFileURL: repositoryFileURL)
				|> map { GitURL($0) }
				|> zipWith(submoduleSHAForPath(repositoryFileURL, path, fileHandle, revision: revision))
				|> map { URL, SHA in Submodule(name: name, path: path, URL: URL, SHA: SHA) }
		}
}

/// Determines whether the specified revision identifies a valid commit.
///
/// If the specified file URL does not represent a valid Git repository, `false`
/// will be sent.
public func commitExistsInRepository(repositoryFileURL: NSURL, fileHandle: NSFileHandle, revision: String = "HEAD") -> SignalProducer<Bool, NoError> {
	return SignalProducer { observer, disposable in
		// NSTask throws a hissy fit (a.k.a. exception) if the working directory
		// doesn't exist, so pre-emptively check for that.
		var isDirectory: ObjCBool = false
		if !NSFileManager.defaultManager().fileExistsAtPath(repositoryFileURL.path!, isDirectory: &isDirectory) || !isDirectory {
			sendNext(observer, false)
			sendCompleted(observer)
			return
		}

		launchGitTask([ "rev-parse", "\(revision)^{commit}" ], fileHandle, repositoryFileURL: repositoryFileURL)
			|> then(SignalProducer<Bool, CarthageError>(value: true))
			|> catch { _ in SignalProducer<Bool, NoError>(value: false) }
			|> startWithSignal { signal, signalDisposable in
				disposable.addDisposable(signalDisposable)
				signal.observe(observer)
			}
	}
}

/// Attempts to resolve the given reference into an object SHA.
public func resolveReferenceInRepository(repositoryFileURL: NSURL, fileHandle: NSFileHandle, reference: String) -> SignalProducer<String, CarthageError> {
	return launchGitTask([ "rev-parse", "\(reference)^{object}" ], fileHandle, repositoryFileURL: repositoryFileURL)
		|> map { string in string.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet()) }
		|> mapError { _ in CarthageError.RepositoryCheckoutFailed(workingDirectoryURL: repositoryFileURL, reason: "No object named \"\(reference)\" exists", underlyingError: nil) }
}

/// Returns the location of the .git folder within the given repository.
private func gitDirectoryURLInRepository(repositoryFileURL: NSURL) -> NSURL {
	return repositoryFileURL.URLByAppendingPathComponent(".git")
}

/// Attempts to determine whether the given directory represents a Git
/// repository.
private func isGitRepository(directoryURL: NSURL) -> Bool {
	return NSFileManager.defaultManager().fileExistsAtPath(gitDirectoryURLInRepository(directoryURL).path!)
}

/// Adds the given submodule to the given repository, cloning from `fetchURL` if
/// the desired revision does not exist or the submodule needs to be cloned.
public func addSubmoduleToRepository(repositoryFileURL: NSURL, submodule: Submodule, fetchURL: GitURL, fileHandle: NSFileHandle) -> SignalProducer<(), CarthageError> {
	let submoduleDirectoryURL = repositoryFileURL.URLByAppendingPathComponent(submodule.path, isDirectory: true)

	return SignalProducer<Bool, CarthageError> { observer, disposable in
			sendNext(observer, isGitRepository(submoduleDirectoryURL))
			sendCompleted(observer)
		}
		|> flatMap(.Merge) { submoduleExists in
			if (submoduleExists) {
				// Just check out and stage the correct revision.
				return fetchRepository(submoduleDirectoryURL, fileHandle, remoteURL: fetchURL, refspec: "+refs/heads/*:refs/remotes/origin/*")
					|> then(launchGitTask([ "config", "--file", ".gitmodules", "submodule.\(submodule.name).url", submodule.URL.URLString ], fileHandle, repositoryFileURL: repositoryFileURL))
					|> then(launchGitTask([ "submodule", "sync" ], fileHandle, repositoryFileURL: repositoryFileURL))
					|> then(checkoutSubmodule(submodule, submoduleDirectoryURL, fileHandle))
					|> then(launchGitTask([ "add", "--force", submodule.path ], fileHandle, repositoryFileURL: repositoryFileURL))
					|> then(.empty)
			} else {
				let addSubmodule = launchGitTask([ "submodule", "add", "--force", "--name", submodule.name, "--", submodule.URL.URLString, submodule.path ], fileHandle, repositoryFileURL: repositoryFileURL)
					// A .failure to add usually means the folder was already added
					// to the index. That's okay.
					|> catch { _ in SignalProducer<String, CarthageError>.empty }

				// If it doesn't exist, clone and initialize a submodule from our
				// local bare repository.
				return cloneRepository(fetchURL, submoduleDirectoryURL, fileHandle, bare: false)
					|> then(launchGitTask([ "remote", "set-url", "origin", submodule.URL.URLString ], fileHandle, repositoryFileURL: submoduleDirectoryURL))
					|> then(checkoutSubmodule(submodule, submoduleDirectoryURL, fileHandle))
					|> then(addSubmodule)
					|> then(launchGitTask([ "submodule", "init", "--", submodule.path ], fileHandle, repositoryFileURL: repositoryFileURL))
					|> then(.empty)
			}
		}
}

/// Moves an item within a Git repository, or within a simple directory if a Git
/// repository is not found.
///
/// Sends the new URL of the item after moving.
public func moveItemInPossibleRepository(repositoryFileURL: NSURL, #fromPath: String, #toPath: String, #fileHandle: NSFileHandle) -> SignalProducer<NSURL, CarthageError> {
	let toURL = repositoryFileURL.URLByAppendingPathComponent(toPath)
	let parentDirectoryURL = toURL.URLByDeletingLastPathComponent!

	return SignalProducer<Bool, CarthageError>.try {
			var error: NSError?
			if !NSFileManager.defaultManager().createDirectoryAtURL(parentDirectoryURL, withIntermediateDirectories: true, attributes: nil, error: &error) {
				return .failure(CarthageError.WriteFailed(parentDirectoryURL, error))
			}

			return .success(isGitRepository(repositoryFileURL))
		}
		|> flatMap(.Merge) { isRepository -> SignalProducer<NSURL, CarthageError> in
			if isRepository {
				return launchGitTask([ "mv", "-k", fromPath, toPath ], fileHandle, repositoryFileURL: repositoryFileURL)
					|> then(SignalProducer(value: toURL))
			} else {
				let fromURL = repositoryFileURL.URLByAppendingPathComponent(fromPath)

				var error: NSError?
				if NSFileManager.defaultManager().moveItemAtURL(fromURL, toURL: toURL, error: &error) {
					return SignalProducer(value: toURL)
				} else {
					return SignalProducer(error: .WriteFailed(toURL, error))
				}
			}
		}
}
