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
		let components = split(URLString, { $0 == "/" }, allowEmptySlices: false)

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
public func launchGitTask(arguments: [String], repositoryFileURL: NSURL? = nil, standardOutput: SinkOf<NSData>? = nil, standardError: SinkOf<NSData>? = nil, environment: [String: String]? = nil) -> ColdSignal<String> {
	let taskDescription = TaskDescription(launchPath: "/usr/bin/git", arguments: arguments, workingDirectoryPath: repositoryFileURL?.path, environment: environment)

	return launchTask(taskDescription, standardOutput: standardOutput, standardError: standardError)
		.map { NSString(data: $0, encoding: NSUTF8StringEncoding) as String }
}

/// Returns a signal that completes when cloning completes successfully.
public func cloneRepository(cloneURL: GitURL, destinationURL: NSURL, bare: Bool = true) -> ColdSignal<String> {
	precondition(destinationURL.fileURL)

	var arguments = [ "clone" ]
	if bare {
		arguments.append("--bare")
	}

	return launchGitTask(arguments + [ "--quiet", cloneURL.URLString, destinationURL.path! ])
}

/// Returns a signal that completes when the fetch completes successfully.
public func fetchRepository(repositoryFileURL: NSURL, remoteURL: GitURL? = nil, refspec: String? = nil) -> ColdSignal<String> {
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
public func listTags(repositoryFileURL: NSURL) -> ColdSignal<String> {
	return launchGitTask([ "tag" ], repositoryFileURL: repositoryFileURL)
		.map { (allTags: String) -> ColdSignal<String> in
			return ColdSignal { (sink, disposable) in
				let string = allTags as NSString

				string.enumerateSubstringsInRange(NSMakeRange(0, string.length), options: NSStringEnumerationOptions.ByLines | NSStringEnumerationOptions.Reverse) { (line, substringRange, enclosingRange, stop) in
					if disposable.disposed {
						stop.memory = true
					}

					sink.put(.Next(Box(line as String)))
				}

				sink.put(.Completed)
			}
		}
		.merge(identity)
}

/// Returns the text contents of the path at the given revision, or an error if
/// the path could not be loaded.
public func contentsOfFileInRepository(repositoryFileURL: NSURL, path: String, revision: String = "HEAD") -> ColdSignal<String> {
	let showObject = "\(revision):\(path)"
	return launchGitTask([ "show", showObject ], repositoryFileURL: repositoryFileURL, standardError: SinkOf<NSData> { _ in () })
}

/// Checks out the working tree of the given (ideally bare) repository, at the
/// specified revision, to the given folder. If the folder does not exist, it
/// will be created.
public func checkoutRepositoryToDirectory(repositoryFileURL: NSURL, workingDirectoryURL: NSURL, revision: String = "HEAD", shouldCloneSubmodule: Submodule -> Bool = { _ in true }) -> ColdSignal<()> {
	return ColdSignal.lazy {
		var error: NSError?
		if !NSFileManager.defaultManager().createDirectoryAtURL(workingDirectoryURL, withIntermediateDirectories: true, attributes: nil, error: &error) {
			return .error(error ?? CarthageError.RepositoryCheckoutFailed(workingDirectoryURL: workingDirectoryURL, reason: "Could not create working directory").error)
		}

		var environment = NSProcessInfo.processInfo().environment as [String: String]
		environment["GIT_WORK_TREE"] = workingDirectoryURL.path!

		return launchGitTask([ "checkout", "--quiet", "--force", revision ], repositoryFileURL: repositoryFileURL, environment: environment)
			.then(cloneSubmodulesForRepository(repositoryFileURL, workingDirectoryURL, revision: revision, shouldCloneSubmodule: shouldCloneSubmodule))
	}
}

/// Clones matching submodules for the given repository at the specified
/// revision, into the given working directory.
public func cloneSubmodulesForRepository(repositoryFileURL: NSURL, workingDirectoryURL: NSURL, revision: String = "HEAD", shouldCloneSubmodule: Submodule -> Bool = { _ in true }) -> ColdSignal<()> {
	return submodulesInRepository(repositoryFileURL, revision: revision)
		.map { submodule -> ColdSignal<()> in
			if shouldCloneSubmodule(submodule) {
				return cloneSubmoduleInWorkingDirectory(submodule, workingDirectoryURL)
			} else {
				return .empty()
			}
		}
		.concat(identity)
		.then(.empty())
}

/// Clones the given submodule into the working directory of its parent
/// repository, but without any Git metadata.
public func cloneSubmoduleInWorkingDirectory(submodule: Submodule, workingDirectoryURL: NSURL) -> ColdSignal<()> {
	let submoduleDirectoryURL = workingDirectoryURL.URLByAppendingPathComponent(submodule.path, isDirectory: true)
	let purgeGitDirectories = ColdSignal<()> { (sink, disposable) in
		let enumerator = NSFileManager.defaultManager().enumeratorAtURL(submoduleDirectoryURL, includingPropertiesForKeys: [ NSURLIsDirectoryKey!, NSURLNameKey! ], options: nil, errorHandler: nil)!

		while !disposable.disposed {
			let URL: NSURL! = enumerator.nextObject() as? NSURL
			if URL == nil {
				break
			}

			var name: AnyObject?
			var error: NSError?
			if !URL.getResourceValue(&name, forKey: NSURLNameKey, error: &error) {
				sink.put(.Error(error ?? CarthageError.RepositoryCheckoutFailed(workingDirectoryURL: submoduleDirectoryURL, reason: "could not enumerate name of descendant at \(URL.path!)").error))
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
				sink.put(.Error(error ?? CarthageError.RepositoryCheckoutFailed(workingDirectoryURL: submoduleDirectoryURL, reason: "could not determine whether \(URL.path!) is a directory").error))
				return
			}

			if let directory = isDirectory?.boolValue {
				if directory {
					enumerator.skipDescendants()
				}
			}

			if !NSFileManager.defaultManager().removeItemAtURL(URL, error: &error) {
				sink.put(.Error(error ?? CarthageError.RepositoryCheckoutFailed(workingDirectoryURL: submoduleDirectoryURL, reason: "could not remove \(URL.path!)").error))
				return
			}
		}

		sink.put(.Completed)
	}

	return ColdSignal<String>.lazy {
			var error: NSError?
			if !NSFileManager.defaultManager().removeItemAtURL(submoduleDirectoryURL, error: &error) {
				return .error(error ?? CarthageError.RepositoryCheckoutFailed(workingDirectoryURL: submoduleDirectoryURL, reason: "could not remove submodule checkout").error)
			}

			return cloneRepository(submodule.URL, workingDirectoryURL.URLByAppendingPathComponent(submodule.path), bare: false)
		}
		.then(checkoutSubmodule(submodule, submoduleDirectoryURL))
		.then(purgeGitDirectories)
}

/// Recursively checks out the given submodule's revision, in its working
/// directory.
private func checkoutSubmodule(submodule: Submodule, submoduleWorkingDirectoryURL: NSURL) -> ColdSignal<()> {
	return launchGitTask([ "checkout", "--quiet", submodule.SHA ], repositoryFileURL: submoduleWorkingDirectoryURL)
		.then(launchGitTask([ "submodule", "--quiet", "update", "--init", "--recursive" ], repositoryFileURL: submoduleWorkingDirectoryURL))
		.then(.empty())
}

/// Parses each key/value entry from the given config file contents, optionally
/// stripping a known prefix/suffix off of each key.
private func parseConfigEntries(contents: String, keyPrefix: String = "", keySuffix: String = "") -> ColdSignal<(String, String)> {
	let entries = split(contents, { $0 == "\0" }, allowEmptySlices: false)

	return ColdSignal { (sink, disposable) in
		for entry in entries {
			if disposable.disposed {
				break
			}

			let components = split(entry, { $0 == "\n" }, maxSplit: 1, allowEmptySlices: true)
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
				sink.put(.Next(Box((key, value))))
			}
		}

		sink.put(.Completed)
	}
}

/// Determines the SHA that the submodule at the given path is pinned to, in the
/// revision of the parent repository specified.
public func submoduleSHAForPath(repositoryFileURL: NSURL, path: String, revision: String = "HEAD") -> ColdSignal<String> {
	return launchGitTask([ "ls-tree", "-z", revision, path ], repositoryFileURL: repositoryFileURL)
		.tryMap { string -> Result<String> in
			// Example:
			// 160000 commit 083fd81ecf00124cbdaa8f86ef10377737f6325a	External/ObjectiveGit
			let components = split(string, { $0 == " " || $0 == "\t" }, maxSplit: 3, allowEmptySlices: false)
			if components.count >= 3 {
				return success(components[2])
			} else {
				return failure(CarthageError.ParseError(description: "expected submodule commit SHA in ls-tree output: \(string)").error)
			}
		}
}

/// Returns each submodule found in the given repository revision, or an empty
/// signal if none exist.
public func submodulesInRepository(repositoryFileURL: NSURL, revision: String = "HEAD") -> ColdSignal<Submodule> {
	let modulesObject = "\(revision):.gitmodules"
	let baseArguments = [ "config", "--blob", modulesObject, "-z" ]

	return launchGitTask(baseArguments + [ "--get-regexp", "submodule\\..*\\.path" ], repositoryFileURL: repositoryFileURL, standardError: SinkOf<NSData> { _ in () })
		.catch { _ in .empty() }
		.map { parseConfigEntries($0, keyPrefix: "submodule.", keySuffix: ".path") }
		.merge(identity)
		.map { (name, path) -> ColdSignal<Submodule> in
			return launchGitTask(baseArguments + [ "--get", "submodule.\(name).url" ], repositoryFileURL: repositoryFileURL)
				.map { GitURL($0) }
				// TODO: This should be a zip.
				.combineLatestWith(submoduleSHAForPath(repositoryFileURL, path, revision: revision))
				.map { (URL, SHA) in
					return Submodule(name: name, path: path, URL: URL, SHA: SHA)
				}
		}
		.merge(identity)
}

/// Determines whether the specified revision identifies a valid commit.
///
/// If the specified file URL does not represent a valid Git repository, `false`
/// will be sent.
public func commitExistsInRepository(repositoryFileURL: NSURL, revision: String = "HEAD") -> ColdSignal<Bool> {
	return ColdSignal.lazy {
		// NSTask throws a hissy fit (a.k.a. exception) if the working directory
		// doesn't exist, so pre-emptively check for that.
		var isDirectory: ObjCBool = false
		if !NSFileManager.defaultManager().fileExistsAtPath(repositoryFileURL.path!, isDirectory: &isDirectory) || !isDirectory {
			return .single(false)
		}

		return launchGitTask([ "rev-parse", "\(revision)^{commit}" ], repositoryFileURL: repositoryFileURL, standardOutput: SinkOf<NSData> { _ in () }, standardError: SinkOf<NSData> { _ in () })
			.then(.single(true))
			.catch { _ in .single(false) }
	}
}

/// Attempts to resolve the given reference into an object SHA.
public func resolveReferenceInRepository(repositoryFileURL: NSURL, reference: String) -> ColdSignal<String> {
	return launchGitTask([ "rev-parse", "\(reference)^{object}" ], repositoryFileURL: repositoryFileURL, standardError: SinkOf<NSData> { _ in () })
		.map { string in
			return string.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
		}
		.catch { _ in .error(CarthageError.RepositoryCheckoutFailed(workingDirectoryURL: repositoryFileURL, reason: "No object named \"\(reference)\" exists").error) }
}

/// Adds the given submodule to the given repository, cloning from `fetchURL` if
/// the desired revision does not exist or the submodule needs to be cloned.
public func addSubmoduleToRepository(repositoryFileURL: NSURL, submodule: Submodule, fetchURL: GitURL) -> ColdSignal<()> {
	let submoduleDirectoryURL = repositoryFileURL.URLByAppendingPathComponent(submodule.path, isDirectory: true)

	return ColdSignal.lazy {
		let submoduleGitPath = submoduleDirectoryURL.URLByAppendingPathComponent(".git").path!
		if NSFileManager.defaultManager().fileExistsAtPath(submoduleGitPath) {
			// If the submodule repository already exists, just check out and
			// stage the correct revision.
			return fetchRepository(submoduleDirectoryURL, remoteURL: fetchURL)
				.then(launchGitTask([ "config", "--file", ".gitmodules", "submodule.\(submodule.name).url", submodule.URL.URLString ], repositoryFileURL: repositoryFileURL))
				.then(launchGitTask([ "submodule", "--quiet", "sync" ], repositoryFileURL: repositoryFileURL))
				.then(checkoutSubmodule(submodule, submoduleDirectoryURL))
				.then(launchGitTask([ "add", "--force", submodule.path ], repositoryFileURL: repositoryFileURL))
				.then(.empty())
		} else {
			let addSubmodule = launchGitTask([ "submodule", "--quiet", "add", "--force", "--name", submodule.name, "--", submodule.URL.URLString, submodule.path ], repositoryFileURL: repositoryFileURL)
				// A failure to add usually means the folder was already added
				// to the index. That's okay.
				.catch { _ in .empty() }

			// If it doesn't exist, clone and initialize a submodule from our
			// local bare repository.
			return cloneRepository(fetchURL, submoduleDirectoryURL, bare: false)
				.then(launchGitTask([ "remote", "set-url", "origin", submodule.URL.URLString ], repositoryFileURL: submoduleDirectoryURL))
				.then(checkoutSubmodule(submodule, submoduleDirectoryURL))
				.then(addSubmodule)
				.then(launchGitTask([ "submodule", "--quiet", "init", "--", submodule.path ], repositoryFileURL: repositoryFileURL))
				.then(.empty())
		}
	}
}
