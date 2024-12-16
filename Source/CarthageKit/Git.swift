import Foundation
import Result
import ReactiveSwift
import ReactiveTask

/// The git version Carthage requires at least.
public let carthageRequiredGitVersion = "2.3.0"

/// Strips any trailing .git in the given name, if one exists.
public func strippingGitSuffix(_ string: String) -> String {
	return string.stripping(suffix: ".git")
}

/// Struct to encapsulate global fetch interval cache
public struct FetchCache {
	/// Amount of time before a git repository is fetched again. Defaults to 1 minute
	public static var fetchCacheInterval: TimeInterval = 60.0

	private static var lastFetchTimes: [GitURL: TimeInterval] = [:]

	private static let lock = NSLock()

	internal static func clearFetchTimes() {
		lock.lock()
		defer { lock.unlock() }

		lastFetchTimes.removeAll()
	}

	internal static func needsFetch(forURL url: GitURL) -> Bool {
		lock.lock()
		defer { lock.unlock() }

		guard let lastFetch = lastFetchTimes[url] else {
			return true
		}

		let difference = Date().timeIntervalSince1970 - lastFetch

		return !(0...fetchCacheInterval).contains(difference)
	}

	fileprivate static func updateLastFetchTime(forURL url: GitURL?) {
		lock.lock()
		defer { lock.unlock() }

		if let url = url {
			lastFetchTimes[url] = Date().timeIntervalSince1970
		}
	}
}

/// Shells out to `git` with the given arguments, optionally in the directory
/// of an existing repository.
public func launchGitTask(
	_ arguments: [String],
	repositoryFileURL: URL? = nil,
	standardInput: SignalProducer<Data, NoError>? = nil,
	environment: [String: String]? = nil
) -> SignalProducer<String, CarthageError> {
	// See https://github.com/Carthage/Carthage/issues/219.
	var updatedEnvironment = environment ?? ProcessInfo.processInfo.environment
	// Error rather than prompt for credentials
	updatedEnvironment["GIT_TERMINAL_PROMPT"] = "0"
	// Error rather than prompt to resolve ssh errors (such as missing known_hosts entry)
	updatedEnvironment["GIT_SSH_COMMAND"] = "ssh -oBatchMode=yes"

	let taskDescription = Task("/usr/bin/env", arguments: [ "git" ] + arguments, workingDirectoryPath: repositoryFileURL?.path, environment: updatedEnvironment)

	return taskDescription.launch(standardInput: standardInput)
		.ignoreTaskData()
		.mapError(CarthageError.taskError)
		.map { data in
			return String(data: data, encoding: .utf8)!
		}
}

/// Checks if the git version satisfies the given required version.
public func ensureGitVersion(_ requiredVersion: String = carthageRequiredGitVersion) -> SignalProducer<Bool, CarthageError> {
	return launchGitTask([ "--version" ])
		.map { input -> Bool in
			let scanner = Scanner(string: input)
			guard scanner.scanString("git version ", into: nil) else {
				return false
			}

			var version: NSString?
			if scanner.scanUpTo("", into: &version), let version = version {
				return version.compare(requiredVersion, options: [ .numeric ]) != .orderedAscending
			} else {
				return false
			}
		}
}

/// Returns a signal that completes when cloning completes successfully.
public func cloneRepository(_ cloneURL: GitURL, _ destinationURL: URL, isBare: Bool = true) -> SignalProducer<String, CarthageError> {
	precondition(destinationURL.isFileURL)

	var arguments = [ "clone" ]
	if isBare {
		arguments.append("--bare")
	}

	return launchGitTask(arguments + [ "--quiet", cloneURL.urlString, destinationURL.path ])
		.on(completed: {
			FetchCache.updateLastFetchTime(forURL: cloneURL)
		})
}

/// Returns a signal that completes when the fetch completes successfully.
public func fetchRepository(_ repositoryFileURL: URL, remoteURL: GitURL? = nil, refspec: String? = nil) -> SignalProducer<String, CarthageError> {
	precondition(repositoryFileURL.isFileURL)

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
		.on(completed: {
			FetchCache.updateLastFetchTime(forURL: remoteURL)
		})
}

/// Sends each tag found in the given Git repository.
public func listTags(_ repositoryFileURL: URL) -> SignalProducer<String, CarthageError> {
	return launchGitTask([ "tag", "--column=never" ], repositoryFileURL: repositoryFileURL)
		.flatMap(.concat) { (allTags: String) -> SignalProducer<String, CarthageError> in
			return SignalProducer { observer, lifetime in
				let range = allTags.startIndex...
				allTags.enumerateSubstrings(in: range, options: [ .byLines, .reverse ]) { line, _, _, stop in
					if lifetime.hasEnded {
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
public func contentsOfFileInRepository(_ repositoryFileURL: URL, _ path: String, revision: String = "HEAD") -> SignalProducer<String, CarthageError> {
	let showObject = "\(revision):\(path)"
	return launchGitTask([ "show", showObject ], repositoryFileURL: repositoryFileURL)
}

/// Checks out the working tree of the given (ideally bare) repository, at the
/// specified revision, to the given folder. If the folder does not exist, it
/// will be created.
///
/// Submodules of the working tree must be handled separately.
public func checkoutRepositoryToDirectory(
	_ repositoryFileURL: URL,
	_ workingDirectoryURL: URL,
	force: Bool,
	revision: String = "HEAD"
) -> SignalProducer<(), CarthageError> {
	return SignalProducer { () -> Result<[String: String], CarthageError> in
			var environment = ProcessInfo.processInfo.environment
			environment["GIT_WORK_TREE"] = workingDirectoryURL.path
			return .success(environment)
	}
	.attempt { _ in
		Result(catching: { try FileManager.default.createDirectory(at: workingDirectoryURL, withIntermediateDirectories: true) })
			.mapError {
				CarthageError.repositoryCheckoutFailed(
					workingDirectoryURL: workingDirectoryURL,
					reason: "Could not create working directory",
					underlyingError: $0
				)
			}
	}
	.flatMap(.concat) { (environment: [String: String]) -> SignalProducer<String, CarthageError> in
		var arguments = [ "checkout", "--quiet" ]
		if force {
			arguments.append("--force")
		}
		arguments.append(revision)

		return launchGitTask(arguments, repositoryFileURL: repositoryFileURL, environment: environment)
	}
	.then(SignalProducer<(), CarthageError>.empty)
}

/// Parses each key/value entry from the given config file contents, optionally
/// stripping a known prefix/suffix off of each key.
private func parseConfigEntries(_ contents: String, keyPrefix: String = "", keySuffix: String = "") -> SignalProducer<(String, String), NoError> {
	let entries = contents.split(omittingEmptySubsequences: true) { $0 == "\0" }

	return SignalProducer { observer, lifetime in
		for entry in entries {
			if lifetime.hasEnded {
				break
			}

			let components = entry.split(maxSplits: 1, omittingEmptySubsequences: false) { $0 == "\n" }.map(String.init)
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

			if let key = key as String? {
				observer.send(value: (key, value))
			}
		}

		observer.sendCompleted()
	}
}

/// Lists the contents of a git tree object at a given path relative to the repository root.
/// It can be used in a bare repository.
///
/// - note: Previously, `path` was recursed through — now, just iterated.
internal func list(treeish: String, atPath path: String, inRepository repositoryURL: URL) -> SignalProducer<String, CarthageError> {
	// git ls-tree treats "dir/" and "dir" differently. We make sure the path has an ending slash here.
	// Thankfully, multiple successive slashes are considered to be the same as one slash.
	let directoryPath = path.appending("/")
	return launchGitTask(
			// `ls-tree`, because `ls-files` returns no output (for all instances I’ve seen) on bare repos.
			// flag “-z” enables output separated by the nul character (`\0`).
			[ "ls-tree", "-z", "--full-name", "--name-only", treeish, directoryPath ],
			repositoryFileURL: repositoryURL
		)
		.flatMap(.merge) { (output: String) -> SignalProducer<String, CarthageError> in
			return SignalProducer(output.lazy.split(separator: "\0").map(String.init))
		}
}

/// Determines the SHA that the submodule at the given path is pinned to, in the
/// revision of the parent repository specified.
public func submoduleSHAForPath(_ repositoryFileURL: URL, _ path: String, revision: String = "HEAD") -> SignalProducer<String, CarthageError> {
	let task = [ "ls-tree", "-z", revision, path ]
	return launchGitTask(task, repositoryFileURL: repositoryFileURL)
		.attemptMap { string -> Result<String, CarthageError> in
			// Example:
			// 160000 commit 083fd81ecf00124cbdaa8f86ef10377737f6325a	External/ObjectiveGit
			let components = string
				.split(maxSplits: 3, omittingEmptySubsequences: true) { (char: Character) in
					char == " " || char == "\t"
				}
			if components.count >= 3 {
				return .success(String(components[2]))
			} else {
				return .failure(
					CarthageError.parseError(
						description: "expected submodule commit SHA in output of task (\(task.joined(separator: " "))) but encountered: \(string)"
					)
				)
			}
		}
}

/// Returns each entry of `.gitmodules` found in the given repository revision,
/// or an empty signal if none exist.
internal func gitmodulesEntriesInRepository(
	_ repositoryFileURL: URL,
	revision: String?
) -> SignalProducer<(name: String, path: String, url: GitURL), CarthageError> { // swiftlint:disable:this large_tuple
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
				.map { $0.stripping(suffix: "\0") }
				.map { urlString in (name: name, path: path, url: GitURL(urlString)) }
		}
}

/// Returns the root directory of the given repository
///
/// If in bare repository, return the passed repo path as the root
/// else, return the path given by "git rev-parse --show-toplevel"
public func gitRootDirectoryForRepository(_ repositoryFileURL: URL) -> SignalProducer<URL, CarthageError> {
	return launchGitTask([ "rev-parse", "--is-bare-repository" ], repositoryFileURL: repositoryFileURL)
		.map { $0.trimmingCharacters(in: .newlines) }
		.flatMap(.concat) { isBareRepository -> SignalProducer<URL, CarthageError> in
			if isBareRepository == "true" {
				return SignalProducer(value: repositoryFileURL)
			} else {
				return launchGitTask([ "rev-parse", "--show-toplevel" ], repositoryFileURL: repositoryFileURL)
					.attemptMap { output in
						let trimmedPath = output.trimmingCharacters(in: .newlines)
						guard FileManager.default.isReadableFile(atPath: trimmedPath) else {
							// can’t return `.readFailed` because we might crash when initializing the URL to give it.
							return .failure(.internalError(description: "Unreadable file path output from git: " + output.debugDescription))
						}
						return .success(URL(fileURLWithPath: trimmedPath))
					}
			}
		}
}

/// Returns each submodule found in the given repository revision, or an empty
/// signal if none exist.
public func submodulesInRepository(_ repositoryFileURL: URL, revision: String = "HEAD") -> SignalProducer<Submodule, CarthageError> {
	return isGitRepository(repositoryFileURL)
		.flatMap(.concat) { isRepository -> SignalProducer<URL, CarthageError> in
			if isRepository {
				return gitRootDirectoryForRepository(repositoryFileURL)
			} else {
				return .empty
			}
		}
		.flatMap(.concat) { actualRepoURL in
			return gitmodulesEntriesInRepository(repositoryFileURL, revision: revision)
				.flatMap(.concat) { name, path, url in
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
internal func branchExistsInRepository(_ repositoryFileURL: URL, pattern: String) -> SignalProducer<Bool, NoError> {
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
public func commitExistsInRepository(_ repositoryFileURL: URL, revision: String = "HEAD") -> SignalProducer<Bool, NoError> {
	return ensureDirectoryExistsAtURL(repositoryFileURL)
		.then(launchGitTask([ "rev-parse", "\(revision)^{commit}" ], repositoryFileURL: repositoryFileURL))
		.then(SignalProducer<Bool, NoError>(value: true))
		.flatMapError { _ in .init(value: false) }
}

/// NSTask throws a hissy fit (a.k.a. exception) if the working directory
/// doesn't exist, so pre-emptively check for that.
private func ensureDirectoryExistsAtURL(_ fileURL: URL) -> SignalProducer<(), CarthageError> {
	return SignalProducer { observer, _ in
		var isDirectory: ObjCBool = false
		if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) && isDirectory.boolValue {
			observer.sendCompleted()
		} else {
			observer.send(error: .readFailed(fileURL, nil))
		}
	}
}

/// Attempts to resolve the given reference into an object SHA.
public func resolveReferenceInRepository(_ repositoryFileURL: URL, _ reference: String) -> SignalProducer<String, CarthageError> {
	return ensureDirectoryExistsAtURL(repositoryFileURL)
		.then(launchGitTask([ "rev-parse", "\(reference)^{object}" ], repositoryFileURL: repositoryFileURL))
		.map { string in string.trimmingCharacters(in: .whitespacesAndNewlines) }
		.mapError { error in
			return CarthageError.repositoryCheckoutFailed(
				workingDirectoryURL: repositoryFileURL,
				reason: "No object named \"\(reference)\" exists",
				underlyingError: error as NSError
			)
		}
}

/// Attempts to resolve the given tag into an object SHA.
internal func resolveTagInRepository(_ repositoryFileURL: URL, _ tag: String) -> SignalProducer<String, CarthageError> {
	return launchGitTask([ "show-ref", "--tags", "--hash", tag ], repositoryFileURL: repositoryFileURL)
		.map { string in string.trimmingCharacters(in: .whitespacesAndNewlines) }
		.mapError { error in
			return CarthageError.repositoryCheckoutFailed(
				workingDirectoryURL: repositoryFileURL,
				reason: "No tag named \"\(tag)\" exists",
				underlyingError: error as NSError
			)
		}
}

/// Attempts to determine whether the given directory represents a Git
/// repository.
public func isGitRepository(_ directoryURL: URL) -> SignalProducer<Bool, NoError> {
	return ensureDirectoryExistsAtURL(directoryURL)
		.then(launchGitTask([ "rev-parse", "--git-dir" ], repositoryFileURL: directoryURL))
		.map { outputIncludingLineEndings in
			let relativeOrAbsoluteGitDirectory = outputIncludingLineEndings.trimmingCharacters(in: .newlines)
			var absoluteGitDirectory: String?
			if (relativeOrAbsoluteGitDirectory as NSString).isAbsolutePath {
				absoluteGitDirectory = relativeOrAbsoluteGitDirectory
			} else {
				absoluteGitDirectory = directoryURL.appendingPathComponent(relativeOrAbsoluteGitDirectory).path
			}
			var isDirectory: ObjCBool = false
			let directoryExists = absoluteGitDirectory.map { FileManager.default.fileExists(atPath: $0, isDirectory: &isDirectory) } ?? false
			return directoryExists && isDirectory.boolValue
		}
		.flatMapError { _ in SignalProducer(value: false) }
}
