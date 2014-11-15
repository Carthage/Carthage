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

	/// Incompatible version specifiers were given for a dependency.
	case IncompatibleRequirements(ProjectIdentifier, VersionSpecifier, VersionSpecifier)

	/// No existent version could be found to satisfy the version specifier for
	/// a dependency.
	case RequiredVersionNotFound(ProjectIdentifier, VersionSpecifier)

	/// Failed to check out a repository.
	case RepositoryCheckoutFailed(workingDirectoryURL: NSURL, reason: String)

	/// Failed to read a file or directory at the given URL.
	case ReadFailed(NSURL)

	/// Failed to write a file or directory at the given URL.
	case WriteFailed(NSURL)

	/// An error occurred parsing a Carthage file.
	case ParseError(description: String)

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

		case let .ReadFailed(fileURL):
			return NSError(domain: CarthageErrorDomain, code: 4, userInfo: [
				NSLocalizedDescriptionKey: "Failed to read file or folder at \(fileURL.path!)"
			])

		case let .IncompatibleRequirements(dependency, first, second):
			return NSError(domain: CarthageErrorDomain, code: 5, userInfo: [
				NSLocalizedDescriptionKey: "Could not pick a version for \(dependency), due to mutually incompatible requirements:\n\t\(first)\n\t\(second)"
			])

		case let .RequiredVersionNotFound(dependency, specifier):
			return NSError(domain: CarthageErrorDomain, code: 6, userInfo: [
				NSLocalizedDescriptionKey: "No available version for \(dependency) satisfies the requirement: \(specifier)"
			])

		case let .RepositoryCheckoutFailed(workingDirectoryURL, reason):
			return NSError(domain: CarthageErrorDomain, code: 7, userInfo: [
				NSLocalizedDescriptionKey: "Failed to check out repository into \(workingDirectoryURL.path!): \(reason)"
			])

		case let .WriteFailed(fileURL):
			return NSError(domain: CarthageErrorDomain, code: 8, userInfo: [
				NSLocalizedDescriptionKey: "Failed to create \(fileURL.path!)"
			])

		case let .ParseError(description):
			return NSError(domain: CarthageErrorDomain, code: 9, userInfo: [
				NSLocalizedDescriptionKey: "Parse error: \(description)"
			])
		}
	}
}
