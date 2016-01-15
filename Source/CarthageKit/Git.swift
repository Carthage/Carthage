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

/// The git version Carthage requires at least.
public let CarthageRequiredGitVersion = "2.3.0"

/// Represents a URL for a Git remote.
public struct GitURL: Equatable {
	/// The string representation of the URL.
	public let URLString: String

	/// A normalized URL string, without protocol, authentication, or port
	/// information. This is mostly useful for comparison, and not for any
	/// actual Git operations.
	private var normalizedURLString: String {
		let parsedURL: NSURL? = NSURL(string: URLString)

		if let parsedURL = parsedURL, host = parsedURL.host {
			// Normal, valid URL.
			let path = stripGitSuffix(parsedURL.path ?? "")
			return "\(host)\(path)"
		} else if URLString.hasPrefix("/") {
			// Local path.
			return stripGitSuffix(URLString)
		} else {
			// scp syntax.
			var strippedURLString = URLString

			if let index = strippedURLString.characters.indexOf("@") {
				strippedURLString.removeRange(strippedURLString.startIndex...index)
			}

			var host = ""
			if let index = strippedURLString.characters.indexOf(":") {
				host = strippedURLString[strippedURLString.startIndex..<index]
				strippedURLString.removeRange(strippedURLString.startIndex...index)
			}

			var path = stripGitSuffix(strippedURLString)
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
		let components = URLString.characters.split(allowEmptySlices: false) { $0 == "/" }

		return components
			.last
			.map(String.init)
			.map(stripGitSuffix)
	}

	public init(_ URLString: String) {
		self.URLString = URLString
	}
}

/// Strips any trailing .git in the given name, if one exists.
public func stripGitSuffix(string: String) -> String {
	if string.hasSuffix(".git") {
		return string[string.startIndex..<string.endIndex.advancedBy(-4)]
	} else {
		return string
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

extension GitURL: CustomStringConvertible {
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

extension Submodule: CustomStringConvertible {
	public var description: String {
		return "\(name) @ \(SHA)"
	}
}

/// Shells out to `git` with the given arguments, optionally in the directory
/// of an existing repository.
public func launchGitTask(arguments: [String], repositoryFileURL: NSURL? = nil, standardInput: SignalProducer<NSData, NoError>? = nil, environment: [String: String]? = nil) -> SignalProducer<String, CarthageError> {
	// See https://github.com/Carthage/Carthage/issues/219.
	var updatedEnvironment = environment ?? NSProcessInfo.processInfo().environment 
	updatedEnvironment["GIT_TERMINAL_PROMPT"] = "0"

	let taskDescription = Task("/usr/bin/env", arguments: [ "git" ] + arguments, workingDirectoryPath: repositoryFileURL?.path, environment: updatedEnvironment)

	return launchTask(taskDescription, standardInput: standardInput)
		.ignoreTaskData()
		.mapError(CarthageError.TaskError)
		.map { data in
			return NSString(data: data, encoding: NSUTF8StringEncoding)! as String
		}
}

/// Checks if the git version satisfies the given required version.
public func ensureGitVersion(requiredVersion: String = CarthageRequiredGitVersion) -> SignalProducer<Bool, CarthageError> {
	return launchGitTask([ "--version" ])
		.map { input -> Bool in
			let scanner = NSScanner(string: input)
			guard scanner.scanString("git version ", intoString: nil) else {
				return false
			}

			var version: NSString?
			if scanner.scanUpToString("", intoString: &version), let version = version {
				return version.compare(requiredVersion, options: [ .NumericSearch ]) != .OrderedAscending
			} else {
				return false
			}
		}
}

/// Returns a signal that completes when cloning completes successfully.
public func cloneRepository(cloneURL: GitURL, _ destinationURL: NSURL, bare: Bool = true) -> SignalProducer<String, CarthageError> {
	precondition(destinationURL.fileURL)

	var arguments = [ "clone" ]
	if bare {
		arguments.append("--bare")
	}

	return launchGitTask(arguments + [ "--quiet", cloneURL.URLString, destinationURL.path! ])
}

/// Returns a signal that completes when the fetch completes successfully.
public func fetchRepository(repositoryFileURL: NSURL, remoteURL: GitURL? = nil, refspec: String? = nil) -> SignalProducer<String, CarthageError> {
	precondition(repositoryFileURL.fileURL)

	var arguments = [ "fetch", "--tags", "--prune", "--quiet" ]
	if let remoteURL = remoteURL {
		arguments.append(remoteURL.URLString)
	}

	if let refspec = refspec {
		arguments.append(refspec)
	}

	return launchGitTask(arguments, repositoryFileURL: repositoryFileURL)
}

/// Sends each tag found in the given Git repository.
public func listTags(repositoryFileURL: NSURL) -> SignalProducer<String, CarthageError> {
	return launchGitTask([ "tag" ], repositoryFileURL: repositoryFileURL)
		.flatMap(.Concat) { (allTags: String) -> SignalProducer<String, CarthageError> in
			return SignalProducer { observer, disposable in
				allTags.enumerateSubstringsInRange(allTags.characters.indices, options: [ .ByLines, .Reverse ]) { line, substringRange, enclosingRange, stop in
					if disposable.disposed {
						stop = true
					}

					if let line = line {
						observer.sendNext(line)
					}
				}

				observer.sendCompleted()
			}
		}
}

/// Returns the text contents of the path at the given revision, or an error if
/// the path could not be loaded.
public func contentsOfFileInRepository(repositoryFileURL: NSURL, _ path: String, revision: String = "HEAD") -> SignalProducer<String, CarthageError> {
	let showObject = "\(revision):\(path)"
	return launchGitTask([ "show", showObject ], repositoryFileURL: repositoryFileURL)
}

/// Checks out the working tree of the given (ideally bare) repository, at the
/// specified revision, to the given folder. If the folder does not exist, it
/// will be created.
public func checkoutRepositoryToDirectory(repositoryFileURL: NSURL, _ workingDirectoryURL: NSURL, revision: String = "HEAD", shouldCloneSubmodule: Submodule -> Bool = { _ in true }) -> SignalProducer<(), CarthageError> {
	return SignalProducer.attempt {
			do {
				try NSFileManager.defaultManager().createDirectoryAtURL(workingDirectoryURL, withIntermediateDirectories: true, attributes: nil)
			} catch let error as NSError {
				return .Failure(CarthageError.RepositoryCheckoutFailed(workingDirectoryURL: workingDirectoryURL, reason: "Could not create working directory", underlyingError: error))
			}

			var environment = NSProcessInfo.processInfo().environment
			environment["GIT_WORK_TREE"] = workingDirectoryURL.path!
			return .Success(environment)
		}
		.flatMap(.Concat) { environment in launchGitTask([ "checkout", "--quiet", "--force", revision ], repositoryFileURL: repositoryFileURL, environment: environment) }
		.then(cloneSubmodulesForRepository(repositoryFileURL, workingDirectoryURL, revision: revision, shouldCloneSubmodule: shouldCloneSubmodule))
}

/// Clones matching submodules for the given repository at the specified
/// revision, into the given working directory.
public func cloneSubmodulesForRepository(repositoryFileURL: NSURL, _ workingDirectoryURL: NSURL, revision: String = "HEAD", shouldCloneSubmodule: Submodule -> Bool = { _ in true }) -> SignalProducer<(), CarthageError> {
	return submodulesInRepository(repositoryFileURL, revision: revision)
		.flatMap(.Concat) { submodule -> SignalProducer<(), CarthageError> in
			if shouldCloneSubmodule(submodule) {
				return cloneSubmoduleInWorkingDirectory(submodule, workingDirectoryURL)
			} else {
				return .empty
			}
		}
		.filter { _ in false }
}

/// Clones the given submodule into the working directory of its parent
/// repository, but without any Git metadata.
public func cloneSubmoduleInWorkingDirectory(submodule: Submodule, _ workingDirectoryURL: NSURL) -> SignalProducer<(), CarthageError> {
	let submoduleDirectoryURL = workingDirectoryURL.URLByAppendingPathComponent(submodule.path, isDirectory: true)
	let purgeGitDirectories = NSFileManager.defaultManager().carthage_enumeratorAtURL(submoduleDirectoryURL, includingPropertiesForKeys: [ NSURLIsDirectoryKey, NSURLNameKey ], options: [], catchErrors: true)
		.flatMap(.Merge) { enumerator, URL -> SignalProducer<(), CarthageError> in
			var name: AnyObject?
			do {
				try URL.getResourceValue(&name, forKey: NSURLNameKey)
			} catch let error as NSError {
				return SignalProducer(error: CarthageError.RepositoryCheckoutFailed(workingDirectoryURL: submoduleDirectoryURL, reason: "could not enumerate name of descendant at \(URL.path!)", underlyingError: error))
			}

			if (name as? String) != ".git" {
				return .empty
			}
		
			var isDirectory: AnyObject?
			do {
				try URL.getResourceValue(&isDirectory, forKey: NSURLIsDirectoryKey)
				if isDirectory == nil {
					return SignalProducer(error: CarthageError.RepositoryCheckoutFailed(workingDirectoryURL: submoduleDirectoryURL, reason: "could not determine whether \(URL.path!) is a directory", underlyingError: nil))
				}
			} catch let error as NSError {
				return SignalProducer(error: CarthageError.RepositoryCheckoutFailed(workingDirectoryURL: submoduleDirectoryURL, reason: "could not determine whether \(URL.path!) is a directory", underlyingError: error))
			}

			if let directory = isDirectory?.boolValue where directory {
				enumerator.skipDescendants()
			}

			do {
				try NSFileManager.defaultManager().removeItemAtURL(URL)
				return .empty
			} catch let error as NSError {
				return SignalProducer(error: CarthageError.RepositoryCheckoutFailed(workingDirectoryURL: submoduleDirectoryURL, reason: "could not remove \(URL.path!)", underlyingError: error))
			}
		}

	return SignalProducer.attempt {
			do {
				try NSFileManager.defaultManager().removeItemAtURL(submoduleDirectoryURL)
			} catch let error as NSError {
				return .Failure(CarthageError.RepositoryCheckoutFailed(workingDirectoryURL: submoduleDirectoryURL, reason: "could not remove submodule checkout", underlyingError: error))
			}

			return .Success(workingDirectoryURL.URLByAppendingPathComponent(submodule.path))
		}
		.flatMap(.Concat) { submoduleDirectoryURL in cloneRepository(submodule.URL, submoduleDirectoryURL, bare: false) }
		.then(checkoutSubmodule(submodule, submoduleDirectoryURL))
		.then(purgeGitDirectories)
}

/// Recursively checks out the given submodule's revision, in its working
/// directory.
private func checkoutSubmodule(submodule: Submodule, _ submoduleWorkingDirectoryURL: NSURL) -> SignalProducer<(), CarthageError> {
	return launchGitTask([ "checkout", "--quiet", submodule.SHA ], repositoryFileURL: submoduleWorkingDirectoryURL)
		.then(launchGitTask([ "submodule", "--quiet", "update", "--init", "--recursive" ], repositoryFileURL: submoduleWorkingDirectoryURL))
		.then(.empty)
}

/// Parses each key/value entry from the given config file contents, optionally
/// stripping a known prefix/suffix off of each key.
private func parseConfigEntries(contents: String, keyPrefix: String = "", keySuffix: String = "") -> SignalProducer<(String, String), NoError> {
	let entries = contents.characters.split(allowEmptySlices: false) { $0 == "\0" }

	return SignalProducer { observer, disposable in
		for entry in entries {
			if disposable.disposed {
				break
			}

			let components = entry.split(1, allowEmptySlices: true) { $0 == "\n" }.map(String.init)
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
				observer.sendNext((key, value))
			}
		}

		observer.sendCompleted()
	}
}

/// Determines the SHA that the submodule at the given path is pinned to, in the
/// revision of the parent repository specified.
public func submoduleSHAForPath(repositoryFileURL: NSURL, _ path: String, revision: String = "HEAD") -> SignalProducer<String, CarthageError> {
	let task = [ "ls-tree", "-z", revision, path ]
	return launchGitTask(task, repositoryFileURL: repositoryFileURL)
		.attemptMap { string in
			// Example:
			// 160000 commit 083fd81ecf00124cbdaa8f86ef10377737f6325a	External/ObjectiveGit
			let components = string.characters.split(3, allowEmptySlices: false) { $0 == " " || $0 == "\t" }
			if components.count >= 3 {
				return .Success(String(components[2]))
			} else {
				return .Failure(CarthageError.ParseError(description: "expected submodule commit SHA in output of task (\(task.joinWithSeparator(" "))) but encountered: \(string)"))
			}
		}
}

/// Returns each entry of `.gitmodules` found in the given repository revision,
/// or an empty signal if none exist.
internal func gitmodulesEntriesInRepository(repositoryFileURL: NSURL, revision: String?) -> SignalProducer<(name: String, path: String, URL: GitURL), CarthageError> {
	var baseArguments = [ "config", "-z" ]
	let modulesFile = ".gitmodules"

	if let revision = revision {
		let modulesObject = "\(revision):\(modulesFile)"
		baseArguments += [ "--blob", modulesObject ]
	} else {
		// This is required to support `--no-use-submodules` checkouts.
		// See https://github.com/Carthage/Carthage/issues/1029.
		baseArguments += [ "--file", modulesFile ]
	}

	return launchGitTask(baseArguments + [ "--get-regexp", "submodule\\..*\\.path" ], repositoryFileURL: repositoryFileURL)
		.flatMapError { _ in SignalProducer<String, NoError>.empty }
		.flatMap(.Concat) { value in parseConfigEntries(value, keyPrefix: "submodule.", keySuffix: ".path") }
		.promoteErrors(CarthageError.self)
		.flatMap(.Concat) { name, path -> SignalProducer<(name: String, path: String, URL: GitURL), CarthageError> in
			return launchGitTask(baseArguments + [ "--get", "submodule.\(name).url" ], repositoryFileURL: repositoryFileURL)
				.map { URLString in (name: name, path: path, URL: GitURL(URLString)) }
		}
}

/// Returns each submodule found in the given repository revision, or an empty
/// signal if none exist.
public func submodulesInRepository(repositoryFileURL: NSURL, revision: String = "HEAD") -> SignalProducer<Submodule, CarthageError> {
	return gitmodulesEntriesInRepository(repositoryFileURL, revision: revision)
		.flatMap(.Concat) { name, path, URL in
			return submoduleSHAForPath(repositoryFileURL, path, revision: revision)
				.map { SHA in Submodule(name: name, path: path, URL: URL, SHA: SHA) }
		}
}

/// Determines whether the specified revision identifies a valid commit.
///
/// If the specified file URL does not represent a valid Git repository, `false`
/// will be sent.
public func commitExistsInRepository(repositoryFileURL: NSURL, revision: String = "HEAD") -> SignalProducer<Bool, NoError> {
	return SignalProducer { observer, disposable in
		// NSTask throws a hissy fit (a.k.a. exception) if the working directory
		// doesn't exist, so pre-emptively check for that.
		var isDirectory: ObjCBool = false
		if !NSFileManager.defaultManager().fileExistsAtPath(repositoryFileURL.path!, isDirectory: &isDirectory) || !isDirectory {
			observer.sendNext(false)
			observer.sendCompleted()
			return
		}

		launchGitTask([ "rev-parse", "\(revision)^{commit}" ], repositoryFileURL: repositoryFileURL)
			.then(SignalProducer<Bool, CarthageError>(value: true))
			.flatMapError { _ in SignalProducer<Bool, NoError>(value: false) }
			.startWithSignal { signal, signalDisposable in
				disposable.addDisposable(signalDisposable)
				signal.observe(observer)
			}
	}
}

/// Attempts to resolve the given reference into an object SHA.
public func resolveReferenceInRepository(repositoryFileURL: NSURL, _ reference: String) -> SignalProducer<String, CarthageError> {
	return launchGitTask([ "rev-parse", "\(reference)^{object}" ], repositoryFileURL: repositoryFileURL)
		.map { string in string.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet()) }
		.mapError { _ in CarthageError.RepositoryCheckoutFailed(workingDirectoryURL: repositoryFileURL, reason: "No object named \"\(reference)\" exists", underlyingError: nil) }
}

/// Attempts to determine whether the given directory represents a Git
/// repository.
public func isGitRepository(directoryURL: NSURL) -> SignalProducer<Bool, NoError> {
	if !NSFileManager.defaultManager().fileExistsAtPath(directoryURL.path!) {
		return SignalProducer(value: false)
	}

	return launchGitTask([ "rev-parse", "--git-dir", ], repositoryFileURL: directoryURL)
		.map { outputIncludingLineEndings in
			let relativeOrAbsoluteGitDirectory = outputIncludingLineEndings.stringByTrimmingCharactersInSet(.newlineCharacterSet())
			var absoluteGitDirectory: String?
			if (relativeOrAbsoluteGitDirectory as NSString).absolutePath {
				absoluteGitDirectory = relativeOrAbsoluteGitDirectory
			} else {
				absoluteGitDirectory = directoryURL.URLByAppendingPathComponent(relativeOrAbsoluteGitDirectory).path
			}
			var isDirectory: ObjCBool = false
			let directoryExists = absoluteGitDirectory.map { NSFileManager.defaultManager().fileExistsAtPath($0, isDirectory: &isDirectory) } ?? false
			return directoryExists && isDirectory
		}
		.flatMapError { _ in SignalProducer(value: false) }
}

/// Adds the given submodule to the given repository, cloning from `fetchURL` if
/// the desired revision does not exist or the submodule needs to be cloned.
public func addSubmoduleToRepository(repositoryFileURL: NSURL, _ submodule: Submodule, _ fetchURL: GitURL) -> SignalProducer<(), CarthageError> {
	let submoduleDirectoryURL = repositoryFileURL.URLByAppendingPathComponent(submodule.path, isDirectory: true)

	return isGitRepository(submoduleDirectoryURL)
		.map { isRepository in
			// Check if the submodule is initialized/updated already.
			return isRepository && NSFileManager.defaultManager().fileExistsAtPath(submoduleDirectoryURL.URLByAppendingPathComponent(".git").path!)
		}
		.promoteErrors(CarthageError.self)
		.flatMap(.Merge) { submoduleExists -> SignalProducer<(), CarthageError> in
			if submoduleExists {
				// Just check out and stage the correct revision.
				return fetchRepository(submoduleDirectoryURL, remoteURL: fetchURL, refspec: "+refs/heads/*:refs/remotes/origin/*")
					.then(launchGitTask([ "config", "--file", ".gitmodules", "submodule.\(submodule.name).url", submodule.URL.URLString ], repositoryFileURL: repositoryFileURL))
					.then(launchGitTask([ "submodule", "--quiet", "sync", "--recursive" ], repositoryFileURL: repositoryFileURL))
					.then(checkoutSubmodule(submodule, submoduleDirectoryURL))
					.then(launchGitTask([ "add", "--force", submodule.path ], repositoryFileURL: repositoryFileURL))
					.then(.empty)
			} else {
				let addSubmodule = launchGitTask([ "submodule", "--quiet", "add", "--force", "--name", submodule.name, "--", submodule.URL.URLString, submodule.path ], repositoryFileURL: repositoryFileURL)
					// A .failure to add usually means the folder was already added
					// to the index. That's okay.
					.flatMapError { _ in SignalProducer<String, CarthageError>.empty }

				// If it doesn't exist, clone and initialize a submodule from our
				// local bare repository.
				return cloneRepository(fetchURL, submoduleDirectoryURL, bare: false)
					.then(launchGitTask([ "remote", "set-url", "origin", submodule.URL.URLString ], repositoryFileURL: submoduleDirectoryURL))
					.then(checkoutSubmodule(submodule, submoduleDirectoryURL))
					.then(addSubmodule)
					.then(launchGitTask([ "submodule", "--quiet", "init", "--", submodule.path ], repositoryFileURL: repositoryFileURL))
					.then(.empty)
			}
		}
}

/// Moves an item within a Git repository, or within a simple directory if a Git
/// repository is not found.
///
/// Sends the new URL of the item after moving.
public func moveItemInPossibleRepository(repositoryFileURL: NSURL, fromPath: String, toPath: String) -> SignalProducer<NSURL, CarthageError> {
	let toURL = repositoryFileURL.URLByAppendingPathComponent(toPath)
	let parentDirectoryURL = toURL.URLByDeletingLastPathComponent!

	return SignalProducer<(), CarthageError>.attempt {
			do {
				try NSFileManager.defaultManager().createDirectoryAtURL(parentDirectoryURL, withIntermediateDirectories: true, attributes: nil)
			} catch let error as NSError {
				return .Failure(CarthageError.WriteFailed(parentDirectoryURL, error))
			}

			return .Success(())
		}
		.then(isGitRepository(repositoryFileURL)
			.promoteErrors(CarthageError.self))
		.flatMap(.Merge) { isRepository -> SignalProducer<NSURL, CarthageError> in
			if isRepository {
				return launchGitTask([ "mv", "-k", fromPath, toPath ], repositoryFileURL: repositoryFileURL)
					.then(SignalProducer(value: toURL))
			} else {
				let fromURL = repositoryFileURL.URLByAppendingPathComponent(fromPath)

				do {
					try NSFileManager.defaultManager().moveItemAtURL(fromURL, toURL: toURL)
					return SignalProducer(value: toURL)
				} catch let error as NSError {
					return SignalProducer(error: .WriteFailed(toURL, error))
				}
			}
		}
}
