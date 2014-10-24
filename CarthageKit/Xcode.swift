//
//  Xcode.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-11.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa

/// Describes how to locate the actual project or workspace that Xcode should
/// build.
public enum ProjectLocator: Comparable {
	/// The `xcworkspace` at the given file URL should be built.
	case Workspace(NSURL)

	/// The `xcodeproj` at the given file URL should be built.
	case ProjectFile(NSURL)

	/// The file URL this locator refers to.
	var fileURL: NSURL {
		switch (self) {
		case let .Workspace(URL):
			assert(URL.fileURL)
			return URL

		case let .ProjectFile(URL):
			assert(URL.fileURL)
			return URL
		}
	}

	/// The arguments that should be passed to `xcodebuild` to help it locate
	/// this project.
	private var arguments: [String] {
		switch (self) {
		case let .Workspace(URL):
			return [ "-workspace", URL.path! ]

		case let .ProjectFile(URL):
			return [ "-project", URL.path! ]
		}
	}
}

public func ==(lhs: ProjectLocator, rhs: ProjectLocator) -> Bool {
	switch (lhs, rhs) {
	case let (.Workspace(left), .Workspace(right)):
		return left == right

	case let (.ProjectFile(left), .ProjectFile(right)):
		return left == right

	default:
		return false
	}
}

public func <(lhs: ProjectLocator, rhs: ProjectLocator) -> Bool {
	// Prefer workspaces over projects.
	switch (lhs, rhs) {
	case let (.Workspace, .ProjectFile):
		return true

	case let (.ProjectFile, .Workspace):
		return false

	default:
		return lexicographicalCompare(lhs.fileURL.path!, rhs.fileURL.path!)
	}
}

/// A candidate match for a project's canonical `ProjectLocator`.
private struct ProjectEnumerationMatch: Comparable {
	let locator: ProjectLocator
	let level: Int

	/// Checks whether a project exists at the given URL, returning a match if
	/// so.
	static func matchURL(URL: NSURL, fromEnumerator enumerator: NSDirectoryEnumerator) -> Result<ProjectEnumerationMatch> {
		var typeIdentifier: AnyObject?
		var error: NSError?

		if !URL.getResourceValue(&typeIdentifier, forKey: NSURLTypeIdentifierKey, error: &error) {
			if let error = error {
				return failure(error)
			} else {
				return failure()
			}
		}

		if let typeIdentifier = typeIdentifier as? String {
			if (UTTypeConformsTo(typeIdentifier, "com.apple.dt.document.workspace") != 0) {
				return success(ProjectEnumerationMatch(locator: .Workspace(URL), level: enumerator.level))
			} else if (UTTypeConformsTo(typeIdentifier, "com.apple.xcode.project") != 0) {
				return success(ProjectEnumerationMatch(locator: .ProjectFile(URL), level: enumerator.level))
			}
		}

		return failure()
	}
}

private func ==(lhs: ProjectEnumerationMatch, rhs: ProjectEnumerationMatch) -> Bool {
	return lhs.locator == rhs.locator
}

private func <(lhs: ProjectEnumerationMatch, rhs: ProjectEnumerationMatch) -> Bool {
	if lhs.level < rhs.level {
		return true
	} else if lhs.level > rhs.level {
		return false
	}

	return lhs.locator < rhs.locator
}

/// Attempts to locate a project or workspace within the given directory.
///
/// Sends all matches in preferential order.
public func locateProjectInDirectory(directoryURL: NSURL) -> ColdSignal<ProjectLocator> {
	let enumerationOptions = NSDirectoryEnumerationOptions.SkipsHiddenFiles | NSDirectoryEnumerationOptions.SkipsPackageDescendants

	return ColdSignal.lazy {
		var enumerationError: NSError?
		let enumerator = NSFileManager.defaultManager().enumeratorAtURL(directoryURL, includingPropertiesForKeys: [ NSURLTypeIdentifierKey ], options: enumerationOptions) { (URL, error) in
			enumerationError = error
			return false
		}

		if let enumerator = enumerator {
			var matches: [ProjectEnumerationMatch] = []

			while let URL = enumerator.nextObject() as? NSURL {
				if let match = ProjectEnumerationMatch.matchURL(URL, fromEnumerator: enumerator).value() {
					matches.append(match)
				}
			}

			if matches.count > 0 {
				sort(&matches)
				return ColdSignal.fromValues(matches).map { $0.locator }
			}
		}

		return .error(enumerationError ?? RACError.Empty.error)
	}
}

public func buildInDirectory(directoryURL: NSURL, configuration: String = "Release") -> ColdSignal<()> {
	precondition(directoryURL.fileURL)

	return locateProjectInDirectory(directoryURL)
		.filter { (locator: ProjectLocator) in
			switch (locator) {
			case .ProjectFile:
				return true

			default:
				return false
			}
		}
		.take(1)
		.map { (locator: ProjectLocator) -> ColdSignal<NSData> in
			let baseArguments = [ "xcodebuild" ] + locator.arguments
			let task = TaskDescription(launchPath: "/usr/bin/xcrun", workingDirectoryPath: directoryURL.path!, arguments: baseArguments + [ "-list" ])

			return launchTask(task)
		}
		.merge(identity)
		.map { (data: NSData) -> String in
			return NSString(data: data, encoding: NSStringEncoding(NSUTF8StringEncoding))!
		}
		.map { (string: String) -> ColdSignal<String> in
			return ColdSignal { subscriber in
				(string as NSString).enumerateLinesUsingBlock { (line, stop) in
					subscriber.put(.Next(Box(line as String)))

					if subscriber.disposable.disposed {
						stop.memory = true
					}
				}

				subscriber.put(.Completed)
			}
		}
		.merge(identity)
		.skipWhile { (line: String) -> Bool in line.hasSuffix("Schemes:") ? false : true }
		.skip(1)
		.takeWhile { (line: String) -> Bool in line.isEmpty ? false : true }
		.map { (line: String) -> String in line.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceCharacterSet()) }
		.map { (scheme: String) -> ColdSignal<()> in
			// TODO
			// task.arguments = baseArguments + [ "-scheme", scheme.unbox, "build" ]

			return ColdSignal<()>.empty()
		}
		.merge(identity)
}
