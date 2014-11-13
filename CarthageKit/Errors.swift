//
//  Errors.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-24.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation

/// The domain for all errors originating within Carthage.
public let CarthageErrorDomain: NSString = "org.carthage.Carthage"

/// Possible error codes within `CarthageErrorDomain`.
public enum CarthageError {
	/// In a user info dictionary, associated with the exit code from a child
	/// process.
	static let exitCodeKey = "CarthageErrorExitCode"

	/// A launched task failed with an erroneous exit code.
	case ShellTaskFailed(exitCode: Int)

	/// One or more arguments was invalid.
	case InvalidArgument(description: String)

	/// `xcodebuild` did not return a build setting that we needed.
	case MissingBuildSetting(String)

	/// No Cartfile present in the project.
	case NoCartfile

	/// The Git repository has already been cloned to the specified location.
	case RepositoryAlreadyCloned(location: NSURL)

	/// Unable to clone a Git repository because a file with the same name
	/// exists.
	case RepositoryCloneFailed(location: NSURL)

	/// Incompatible version specifiers were given for a dependency.
	case IncompatibleRequirements(ProjectIdentifier, VersionSpecifier, VersionSpecifier)

	/// No existent version could be found to satisfy the version specifier for
	/// a dependency.
	case RequiredVersionNotFound(ProjectIdentifier, VersionSpecifier)

	/// An `NSError` object corresponding to this error code.
	public var error: NSError {
		switch (self) {
		case let .ShellTaskFailed(code):
			return NSError(domain: CarthageErrorDomain, code: 1, userInfo: [
				NSLocalizedDescriptionKey: "A shell task failed with exit code \(code)",
				CarthageError.exitCodeKey: code
			])

		case let .InvalidArgument(description):
			return NSError(domain: CarthageErrorDomain, code: 2, userInfo: [
				NSLocalizedDescriptionKey: description
			])

		case let .MissingBuildSetting(setting):
			return NSError(domain: CarthageErrorDomain, code: 3, userInfo: [
				NSLocalizedDescriptionKey: "xcodebuild did not return a value for build setting \(setting)"
			])

		case let .NoCartfile:
			return NSError(domain: CarthageErrorDomain, code: 4, userInfo: [
				NSLocalizedDescriptionKey: "No Cartfile found."
			])

		case let .RepositoryAlreadyCloned(location):
			return NSError(domain: CarthageErrorDomain, code: 5, userInfo: [
				NSLocalizedDescriptionKey: "The Git repository already exists at: \(location)"
			])

		case let .RepositoryCloneFailed(location):
			return NSError(domain: CarthageErrorDomain, code: 6, userInfo: [
				NSLocalizedDescriptionKey: "Unable to clone Git repository because a file already exists at: \(location)"
			])

		case let .IncompatibleRequirements(dependency, first, second):
			return NSError(domain: CarthageErrorDomain, code: 7, userInfo: [
				NSLocalizedDescriptionKey: "Could not pick a version for \(dependency), due to mutually incompatible requirements:\n\t\(first)\n\t\(second)"
			])

		case let .RequiredVersionNotFound(dependency, specifier):
			return NSError(domain: CarthageErrorDomain, code: 8, userInfo: [
				NSLocalizedDescriptionKey: "No available version for \(dependency) satisfies the requirement: \(specifier)"
			])
		}
	}
}
