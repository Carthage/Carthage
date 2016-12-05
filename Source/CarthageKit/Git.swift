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
	public let urlString: String

	/// A normalized URL string, without protocol, authentication, or port
	/// information. This is mostly useful for comparison, and not for any
	/// actual Git operations.
	private var normalizedURLString: String {
		let parsedURL: NSURL? = NSURL(string: urlString)

		if let parsedURL = parsedURL, host = parsedURL.host {
			// Normal, valid URL.
			let path = stripGitSuffix(parsedURL.path ?? "")
			return "\(host)\(path)"
		} else if urlString.hasPrefix("/") {
			// Local path.
			return stripGitSuffix(urlString)
		} else {
			// scp syntax.
			var strippedURLString = urlString

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
		let components = urlString.characters.split(allowEmptySlices: false) { $0 == "/" }

		return components
			.last
			.map(String.init)
			.map(stripGitSuffix)
	}

	public init(_ urlString: String) {
		self.urlString = urlString
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
		return urlString
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
	public var url: GitURL

	/// The SHA checked out in the submodule.
	public var sha: String

	public init(name: String, path: String, url: GitURL, sha: String) {
		self.name = name
		self.path = path
		self.url = url
		self.sha = sha
	}
}

public func ==(lhs: Submodule, rhs: Submodule) -> Bool {
	return lhs.name == rhs.name && lhs.path == rhs.path && lhs.url == rhs.url && lhs.sha == rhs.sha
}

extension Submodule: Hashable {
	public var hashValue: Int {
		return name.hashValue
	}
}

extension Submodule: CustomStringConvertible {
	public var description: String {
		return "\(name) @ \(sha)"
	}
}

/// Struct to encapsulate global fetch interval cache
public struct FetchCache {
	/// Amount of time before a git repository is fetched again. Defaults to 1 minute
	public static var fetchCacheInterval: NSTimeInterval = 60.0

	private static var lastFetchTimes: [GitURL : NSTimeInterval] = [:]

	internal static func clearFetchTimes() {
		lastFetchTimes.removeAll()
	}

	internal static func needsFetch(forURL url: GitURL) -> Bool {
		guard let lastFetch = lastFetchTimes[url] else {
			return true
		}

		let difference = Date().timeIntervalSince1970 - lastFetch

		return !(0...fetchCacheInterval).contains(difference)
	}

	private static func updateLastFetchTime(forURL url: GitURL?) {
		if let url = url {
			lastFetchTimes[url] = Date().timeIntervalSince1970
		}
	}
}

/// Shells out to `git` with the given arguments, optionally in the directory
/// of an existing repository.
public func launchGitTask(arguments: [String], repositoryFileURL: NSURL? = nil, standardInput: SignalProducer<Data, NoError>? = nil, environment: [String: String]? = nil) -> SignalProducer<String, CarthageError> {
	// See https://github.com/Carthage/Carthage/issues/219.
	var updatedEnvironment = environment ?? ProcessInfo.processInfo.environment 
	updatedEnvironment["GIT_TERMINAL_PROMPT"] = "0"

	let taskDescription = Task("/usr/bin/env", arguments: [ "git" ] + arguments, workingDirectoryPath: repositoryFileURL?.path, environment: updatedEnvironment)

	return taskDescription.launch(standardInput: standardInput)
		.ignoreTaskData()
		.mapError(CarthageError.taskError)
		.map { data in
			return NSString(data: data, encoding: NSUTF8StringEncoding)! as String
		}
}

/// Checks if the git version satisfies the given required version.
public func ensureGitVersion(requiredVersion: String = CarthageRequiredGitVersion) -> SignalProducer<Bool, CarthageError> {
	return launchGitTask([ "--version" ])
		.map { input -> Bool in
			let scanner = Scanner(string: input)
			guard scanner.scanString("git version ", into: nil) else {
				return false
			}

			var version: NSString?
			if scanner.scanUpTo("", into: &version), let version = version {
				return version.compare(requiredVersion, options: [ .NumericSearch ]) != .orderedAscending
			} else {
				return false
			}
		}
}

/// Returns a signal that completes when cloning completes successfully.
public func cloneRepository(cloneURL: GitURL, _ destinationURL: NSURL, isBare: Bool = true) -> SignalProducer<String, CarthageError> {
	precondition(destinationURL.fileURL)

	var arguments = [ "clone" ]
	if isBare {
		arguments.append("--bare")
	}

	return launchGitTask(arguments + [ "--quiet", cloneURL.urlString, destinationURL.path! ])
		.on(completed: { FetchCache.updateLastFetchTime(forURL: cloneURL) })
}

/// Returns a signal that completes when the fetch completes successfully.
public func fetchRepository(repositoryFileURL: NSURL, remoteURL: GitURL? = nil, refspec: String? = nil) -> SignalProducer<String, CarthageError> {
	precondition(repositoryFileURL.fileURL)

	var arguments = [ "fetch", "--prune", "--quiet" ]
	if let remoteURL = remoteURL {
		arguments.append(remoteURL.urlString)
	}

	// Specify an explict refspec that fetches tags for pruning.
	// See https://github.com/Carthage/Carthage/issues/1027 and `man git-fetch`.
	arguments.append("refs/tags/*:refs/tags/*")

	if let refspec = refspec {
		arguments.append(refspec)
	}

	return launchGitTask(arguments, repositoryFileURL: repositoryFileURL)
		.on(completed: { FetchCache.updateLastFetchTime(forURL: remoteURL) })
}

/// Sends each tag found in the given Git repository.
public func listTags(repositoryFileURL: NSURL) -> SignalProducer<String, CarthageError> {
	return launchGitTask([ "tag", "--column=never" ], repositoryFileURL: repositoryFileURL)
		.flatMap(.concat) { (allTags: String) -> SignalProducer<String, CarthageError> in
			return SignalProducer { observer, disposable in
				allTags.enumerateSubstringsInRange(allTags.characters.indices, options: [ .ByLines, .Reverse ]) { line, substringRange, enclosingRange, stop in
					if disposable.isDisposed {
						stop = true
					}

					if let line = line {
						observer.send(value: line)
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
public func checkoutRepositoryToDirectory(repositoryFileURL: NSURL, _ workingDirectoryURL: NSURL, revision: String = "HEAD", shouldCloneSubmodule: (Submodule) -> Bool = { _ in true }) -> SignalProducer<(), CarthageError> {
	return SignalProducer.attempt { () -> Result<[String: String], CarthageError> in
			do {
				try FileManager.`default`.createDirectory(at: workingDirectoryURL, withIntermediateDirectories: true)
			} catch let error as NSError {
				return .failure(CarthageError.repositoryCheckoutFailed(workingDirectoryURL: workingDirectoryURL, reason: "Could not create working directory", underlyingError: error))
			}

			var environment = ProcessInfo.processInfo.environment
			environment["GIT_WORK_TREE"] = workingDirectoryURL.path!
			return .success(environment)
		}
		.flatMap(.concat) { environment in launchGitTask([ "checkout", "--quiet", "--force", revision ], repositoryFileURL: repositoryFileURL, environment: environment) }
		.then(cloneSubmodulesForRepository(repositoryFileURL, workingDirectoryURL, revision: revision, shouldCloneSubmodule: shouldCloneSubmodule))
}

/// Clones matching submodules for the given repository at the specified
/// revision, into the given working directory.
public func cloneSubmodulesForRepository(repositoryFileURL: NSURL, _ workingDirectoryURL: NSURL, revision: String = "HEAD", shouldCloneSubmodule: (Submodule) -> Bool = { _ in true }) -> SignalProducer<(), CarthageError> {
	return submodulesInRepository(repositoryFileURL, revision: revision)
		.flatMap(.concat) { submodule -> SignalProducer<(), CarthageError> in
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
	let submoduleDirectoryURL = workingDirectoryURL.appendingPathComponent(submodule.path, isDirectory: true)
	let purgeGitDirectories = FileManager.`default`.carthage_enumerator(at: submoduleDirectoryURL, includingPropertiesForKeys: [ NSURLIsDirectoryKey, NSURLNameKey ], catchErrors: true)
		.flatMap(.merge) { enumerator, url -> SignalProducer<(), CarthageError> in
			var name: AnyObject?
			do {
				try url.getResourceValue(&name, forKey: NSURLNameKey)
			} catch let error as NSError {
				return SignalProducer(error: CarthageError.repositoryCheckoutFailed(workingDirectoryURL: submoduleDirectoryURL, reason: "could not enumerate name of descendant at \(url.path!)", underlyingError: error))
			}

			if (name as? String) != ".git" {
				return .empty
			}
		
			var isDirectory: AnyObject?
			do {
				try url.getResourceValue(&isDirectory, forKey: NSURLIsDirectoryKey)
				if isDirectory == nil {
					return SignalProducer(error: CarthageError.repositoryCheckoutFailed(workingDirectoryURL: submoduleDirectoryURL, reason: "could not determine whether \(url.path!) is a directory", underlyingError: nil))
				}
			} catch let error as NSError {
				return SignalProducer(error: CarthageError.repositoryCheckoutFailed(workingDirectoryURL: submoduleDirectoryURL, reason: "could not determine whether \(url.path!) is a directory", underlyingError: error))
			}

			if let directory = isDirectory?.boolValue where directory {
				enumerator.skipDescendants()
			}

			do {
				try FileManager.`default`.removeItem(at: url)
				return .empty
			} catch let error as NSError {
				return SignalProducer(error: CarthageError.repositoryCheckoutFailed(workingDirectoryURL: submoduleDirectoryURL, reason: "could not remove \(url.path!)", underlyingError: error))
			}
		}

	return SignalProducer.attempt { () -> Result<NSURL, CarthageError> in
			do {
				try FileManager.`default`.removeItem(at: submoduleDirectoryURL)
			} catch let error as NSError {
				return .failure(CarthageError.repositoryCheckoutFailed(workingDirectoryURL: submoduleDirectoryURL, reason: "could not remove submodule checkout", underlyingError: error))
			}

			return .success(workingDirectoryURL.appendingPathComponent(submodule.path))
		}
		.flatMap(.concat) { submoduleDirectoryURL in cloneRepository(submodule.url, submoduleDirectoryURL, isBare: false) }
		.then(checkoutSubmodule(submodule, submoduleDirectoryURL))
		.then(purgeGitDirectories)
}

/// Recursively checks out the given submodule's revision, in its working
/// directory.
private func checkoutSubmodule(submodule: Submodule, _ submoduleWorkingDirectoryURL: NSURL) -> SignalProducer<(), CarthageError> {
	return launchGitTask([ "checkout", "--quiet", submodule.sha ], repositoryFileURL: submoduleWorkingDirectoryURL)
		.then(launchGitTask([ "submodule", "--quiet", "update", "--init", "--recursive" ], repositoryFileURL: submoduleWorkingDirectoryURL))
		.then(.empty)
}

/// Parses each key/value entry from the given config file contents, optionally
/// stripping a known prefix/suffix off of each key.
private func parseConfigEntries(contents: String, keyPrefix: String = "", keySuffix: String = "") -> SignalProducer<(String, String), NoError> {
	let entries = contents.characters.split(allowEmptySlices: false) { $0 == "\0" }

	return SignalProducer { observer, disposable in
		for entry in entries {
			if disposable.isDisposed {
				break
			}

			let components = entry.split(1, allowEmptySlices: true) { $0 == "\n" }.map(String.init)
			if components.count != 2 {
				continue
			}

			let value = components[1]
			let scanner = Scanner(string: components[0])

			if !scanner.scanString(keyPrefix, into: nil) {
				continue
			}

			var key: NSString?
			if !scanner.scanUpTo(keySuffix, into: &key) {
				continue
			}

			if let key = key as? String {
				observer.send(value: (key, value))
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
				return .success(String(components[2]))
			} else {
				return .failure(CarthageError.parseError(description: "expected submodule commit SHA in output of task (\(task.joinWithSeparator(" "))) but encountered: \(string)"))
			}
		}
}

/// Returns each entry of `.gitmodules` found in the given repository revision,
/// or an empty signal if none exist.
internal func gitmodulesEntriesInRepository(repositoryFileURL: NSURL, revision: String?) -> SignalProducer<(name: String, path: String, url: GitURL), CarthageError> {
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
		.flatMap(.concat) { value in parseConfigEntries(value, keyPrefix: "submodule.", keySuffix: ".path") }
		.flatMap(.concat) { name, path -> SignalProducer<(name: String, path: String, url: GitURL), CarthageError> in
			return launchGitTask(baseArguments + [ "--get", "submodule.\(name).url" ], repositoryFileURL: repositoryFileURL)
				.map { urlString in (name: name, path: path, url: GitURL(urlString)) }
		}
}

/// Returns the root directory of the given repository
///
/// If in bare repository, return the passed repo path as the root
/// else, return the path given by "git rev-parse --show-toplevel"
public func gitRootDirectoryForRepository(repositoryFileURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	return launchGitTask([ "rev-parse", "--is-bare-repository" ], repositoryFileURL: repositoryFileURL)
		.map { $0.stringByTrimmingCharactersInSet(.newlines) }
		.flatMap(.concat) { isBareRepository -> SignalProducer<NSURL, CarthageError> in
			if isBareRepository == "true" {
				return SignalProducer(value: repositoryFileURL)
			} else {
				return launchGitTask([ "rev-parse", "--show-toplevel" ], repositoryFileURL: repositoryFileURL)
					.map { $0.stringByTrimmingCharactersInSet(.newlines) }
					.map(NSURL.init)
			}
		}
}

/// Returns each submodule found in the given repository revision, or an empty
/// signal if none exist.
public func submodulesInRepository(repositoryFileURL: NSURL, revision: String = "HEAD") -> SignalProducer<Submodule, CarthageError> {
	return gitmodulesEntriesInRepository(repositoryFileURL, revision: revision)
		.flatMap(.concat) { name, path, url in
			return gitRootDirectoryForRepository(repositoryFileURL)
				.flatMap(.concat) { actualRepoURL in
					return submoduleSHAForPath(actualRepoURL, path, revision: revision)
						.map { sha in Submodule(name: name, path: path, url: url, sha: sha) }
			}
		}
}

/// Determines whether a branch exists for the given pattern in the given
/// repository.
///
/// If the specified file URL does not represent a valid Git repository, `false`
/// will be sent.
internal func branchExistsInRepository(repositoryFileURL: NSURL, pattern: String) -> SignalProducer<Bool, NoError> {
	return ensureDirectoryExistsAtURL(repositoryFileURL)
		.succeeded()
		.flatMap(.concat) { exists -> SignalProducer<Bool, NoError> in
			if !exists { return .init(value: false) }
			return SignalProducer.zip(
					launchGitTask([ "show-ref", pattern ], repositoryFileURL: repositoryFileURL).succeeded(),
					launchGitTask([ "show-ref", "--tags", pattern ], repositoryFileURL: repositoryFileURL).succeeded()
				)
				.map { branch, tag in
					return branch && !tag
				}
		}
}

/// Determines whether the specified revision identifies a valid commit.
///
/// If the specified file URL does not represent a valid Git repository, `false`
/// will be sent.
public func commitExistsInRepository(repositoryFileURL: NSURL, revision: String = "HEAD") -> SignalProducer<Bool, NoError> {
	return ensureDirectoryExistsAtURL(repositoryFileURL)
		.then(launchGitTask([ "rev-parse", "\(revision)^{commit}" ], repositoryFileURL: repositoryFileURL))
		.then(.init(value: true))
		.flatMapError { _ in .init(value: false) }
}

/// NSTask throws a hissy fit (a.k.a. exception) if the working directory
/// doesn't exist, so pre-emptively check for that.
private func ensureDirectoryExistsAtURL(fileURL: NSURL) -> SignalProducer<(), CarthageError> {
	return SignalProducer { observer, disposable in
		var isDirectory: ObjCBool = false
		if FileManager.`default`.fileExists(atPath: fileURL.path!, isDirectory: &isDirectory) && isDirectory {
			observer.sendCompleted()
		} else {
			observer.send(error: .readFailed(fileURL, nil))
		}
	}
}

/// Attempts to resolve the given reference into an object SHA.
public func resolveReferenceInRepository(repositoryFileURL: NSURL, _ reference: String) -> SignalProducer<String, CarthageError> {
	return ensureDirectoryExistsAtURL(repositoryFileURL)
		.then(launchGitTask([ "rev-parse", "\(reference)^{object}" ], repositoryFileURL: repositoryFileURL))
		.map { string in string.stringByTrimmingCharactersInSet(.whitespacesAndNewlines) }
		.mapError { error in CarthageError.repositoryCheckoutFailed(workingDirectoryURL: repositoryFileURL, reason: "No object named \"\(reference)\" exists", underlyingError: error as NSError) }
}

/// Attempts to resolve the given tag into an object SHA.
internal func resolveTagInRepository(repositoryFileURL: NSURL, _ tag: String) -> SignalProducer<String, CarthageError> {
	return launchGitTask([ "show-ref", "--tags", "--hash", tag ], repositoryFileURL: repositoryFileURL)
		.map { string in string.stringByTrimmingCharactersInSet(.whitespacesAndNewlines) }
		.mapError { error in CarthageError.repositoryCheckoutFailed(workingDirectoryURL: repositoryFileURL, reason: "No tag named \"\(tag)\" exists", underlyingError: error as NSError) }
}

/// Attempts to determine whether the given directory represents a Git
/// repository.
public func isGitRepository(directoryURL: NSURL) -> SignalProducer<Bool, NoError> {
	return ensureDirectoryExistsAtURL(directoryURL)
		.then(launchGitTask([ "rev-parse", "--git-dir", ], repositoryFileURL: directoryURL))
		.map { outputIncludingLineEndings in
			let relativeOrAbsoluteGitDirectory = outputIncludingLineEndings.stringByTrimmingCharactersInSet(.newlines)
			var absoluteGitDirectory: String?
			if (relativeOrAbsoluteGitDirectory as NSString).absolutePath {
				absoluteGitDirectory = relativeOrAbsoluteGitDirectory
			} else {
				absoluteGitDirectory = directoryURL.appendingPathComponent(relativeOrAbsoluteGitDirectory).path
			}
			var isDirectory: ObjCBool = false
			let directoryExists = absoluteGitDirectory.map { FileManager.`default`.fileExists(atPath: $0, isDirectory: &isDirectory) } ?? false
			return directoryExists && isDirectory
		}
		.flatMapError { _ in SignalProducer(value: false) }
}

/// Adds the given submodule to the given repository, cloning from `fetchURL` if
/// the desired revision does not exist or the submodule needs to be cloned.
public func addSubmoduleToRepository(repositoryFileURL: NSURL, _ submodule: Submodule, _ fetchURL: GitURL) -> SignalProducer<(), CarthageError> {
	let submoduleDirectoryURL = repositoryFileURL.appendingPathComponent(submodule.path, isDirectory: true)

	return isGitRepository(submoduleDirectoryURL)
		.map { isRepository in
			// Check if the submodule is initialized/updated already.
			return isRepository && FileManager.`default`.fileExists(atPath: submoduleDirectoryURL.appendingPathComponent(".git").path!)
		}
		.flatMap(.merge) { submoduleExists -> SignalProducer<(), CarthageError> in
			if submoduleExists {
				// Just check out and stage the correct revision.
				return fetchRepository(submoduleDirectoryURL, remoteURL: fetchURL, refspec: "+refs/heads/*:refs/remotes/origin/*")
					.then(launchGitTask([ "config", "--file", ".gitmodules", "submodule.\(submodule.name).url", submodule.url.urlString ], repositoryFileURL: repositoryFileURL))
					.then(launchGitTask([ "submodule", "--quiet", "sync", "--recursive" ], repositoryFileURL: repositoryFileURL))
					.then(checkoutSubmodule(submodule, submoduleDirectoryURL))
					.then(launchGitTask([ "add", "--force", submodule.path ], repositoryFileURL: repositoryFileURL))
					.then(.empty)
			} else {
				let addSubmodule = launchGitTask([ "submodule", "--quiet", "add", "--force", "--name", submodule.name, "--", submodule.url.urlString, submodule.path ], repositoryFileURL: repositoryFileURL)
					// A .failure to add usually means the folder was already added
					// to the index. That's okay.
					.flatMapError { _ in SignalProducer<String, CarthageError>.empty }

				// If it doesn't exist, clone and initialize a submodule from our
				// local bare repository.
				return cloneRepository(fetchURL, submoduleDirectoryURL, isBare: false)
					.then(launchGitTask([ "remote", "set-url", "origin", submodule.url.urlString ], repositoryFileURL: submoduleDirectoryURL))
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
	let toURL = repositoryFileURL.appendingPathComponent(toPath)
	let parentDirectoryURL = toURL.URLByDeletingLastPathComponent!

	return SignalProducer<(), CarthageError>.attempt {
			do {
				try FileManager.`default`.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)
			} catch let error as NSError {
				return .failure(CarthageError.writeFailed(parentDirectoryURL, error))
			}

			return .success(())
		}
		.then(isGitRepository(repositoryFileURL)
			.promoteErrors(CarthageError.self))
		.flatMap(.merge) { isRepository -> SignalProducer<NSURL, CarthageError> in
			if isRepository {
				return launchGitTask([ "mv", "-k", fromPath, toPath ], repositoryFileURL: repositoryFileURL)
					.then(SignalProducer(value: toURL))
			} else {
				let fromURL = repositoryFileURL.appendingPathComponent(fromPath)

				do {
					try FileManager.`default`.moveItem(at: fromURL, to: toURL)
					return SignalProducer(value: toURL)
				} catch let error as NSError {
					return SignalProducer(error: .writeFailed(toURL, error))
				}
			}
		}
}
