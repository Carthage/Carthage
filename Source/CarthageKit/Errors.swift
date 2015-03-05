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

/// Possible error codes with `CarthageErrorDomain`.
public enum CarthageErrorCode: Int {
	case InvalidArgument
	case MissingBuildSetting
	case IncompatibleRequirements
	case TaggedVersionNotFound
	case RequiredVersionNotFound
	case RepositoryCheckoutFailed
	case ReadFailed
	case WriteFailed
	case ParseError
	case InvalidArchitectures
	case MissingEnvironmentVariable
	case NoSharedSchemes
	case DuplicateDependencies

	func error(userInfo: [NSObject: AnyObject]?) -> NSError {
		return NSError(domain: CarthageErrorDomain, code: self.rawValue, userInfo: userInfo)
	}
}

/// Possible errors within `CarthageErrorDomain`.
public enum CarthageError {
	/// One or more arguments was invalid.
	case InvalidArgument(description: String)

	/// `xcodebuild` did not return a build setting that we needed.
	case MissingBuildSetting(String)

	/// Incompatible version specifiers were given for a dependency.
	case IncompatibleRequirements(ProjectIdentifier, VersionSpecifier, VersionSpecifier)

	/// No tagged versions could be found for the dependency.
	case TaggedVersionNotFound(ProjectIdentifier)

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

	// An expected environment variable wasn't found.
	case MissingEnvironmentVariable(variable: String)

	// An error occurred reading a framework's architectures.
	case InvalidArchitectures(description: String)

	/// The project is not sharing any schemes, so Carthage cannot discover
	/// them.
	case NoSharedSchemes(ProjectLocator)

	/// A cartfile contains duplicate dependencies, either in itself or across
	/// other cartfiles.
	case DuplicateDependencies([DuplicateDependency])

	/// An `NSError` object corresponding to this error code.
	public var error: NSError {
		switch (self) {
		case let .InvalidArgument(description):
			return CarthageErrorCode.InvalidArgument.error([
				NSLocalizedDescriptionKey: description
			])

		case let .MissingBuildSetting(setting):
			return CarthageErrorCode.MissingBuildSetting.error([
				NSLocalizedDescriptionKey: "xcodebuild did not return a value for build setting \(setting)"
			])

		case let .ReadFailed(fileURL):
			return CarthageErrorCode.ReadFailed.error([
				NSLocalizedDescriptionKey: "Failed to read file or folder at \(fileURL.path!)"
			])

		case let .IncompatibleRequirements(dependency, first, second):
			return CarthageErrorCode.IncompatibleRequirements.error([
				NSLocalizedDescriptionKey: "Could not pick a version for \(dependency), due to mutually incompatible requirements:\n\t\(first)\n\t\(second)"
			])

		case let .TaggedVersionNotFound(dependency):
			return CarthageErrorCode.TaggedVersionNotFound.error([
				NSLocalizedDescriptionKey: "No tagged versions found for \(dependency)"
			])

		case let .RequiredVersionNotFound(dependency, specifier):
			return CarthageErrorCode.RequiredVersionNotFound.error([
				NSLocalizedDescriptionKey: "No available version for \(dependency) satisfies the requirement: \(specifier)"
			])

		case let .RepositoryCheckoutFailed(workingDirectoryURL, reason):
			return CarthageErrorCode.RepositoryCheckoutFailed.error([
				NSLocalizedDescriptionKey: "Failed to check out repository into \(workingDirectoryURL.path!): \(reason)"
			])

		case let .WriteFailed(fileURL):
			return CarthageErrorCode.WriteFailed.error([
				NSLocalizedDescriptionKey: "Failed to create \(fileURL.path!)"
			])

		case let .ParseError(description):
			return CarthageErrorCode.ParseError.error([
				NSLocalizedDescriptionKey: "Parse error: \(description)"
			])

		case let .InvalidArchitectures(description):
			return CarthageErrorCode.InvalidArchitectures.error([
				NSLocalizedDescriptionKey: "Invalid architecture: \(description)"
			])

		case let .MissingEnvironmentVariable(variable):
			return CarthageErrorCode.MissingEnvironmentVariable.error([
				NSLocalizedDescriptionKey: "Environment variable not set: \(variable)"
			])

		case let .NoSharedSchemes(project):
			return CarthageErrorCode.NoSharedSchemes.error([
				NSLocalizedDescriptionKey: "Project \"\(project)\" has no shared schemes"
			])

		case let .DuplicateDependencies(duplicateDeps):
			let deps = duplicateDeps
				.sorted(<) // important to match expected order in test cases
				.reduce("") { (acc, dep) in
					"\(acc)\n\t\(dep)"
				}
			return CarthageErrorCode.DuplicateDependencies.error([
				NSLocalizedDescriptionKey: "The following dependencies are duplicates:\(deps)"
			])
		}
	}
}

/// A duplicate dependency, used in CarthageError.DuplicateDependencies.
public struct DuplicateDependency {
	/// The duplicate dependency as a project.
	public let project: ProjectIdentifier

	/// The locations where the dependency was found as duplicate.
	public let locations: [String]

	// The generated memberwise initialiser has internal access control and
	// cannot be used in test cases, so we reimplement it as public. We are also
	// sorting locations, which makes sure that we can match them in a
	// test case.
	public init(project: ProjectIdentifier, locations: [String]) {
		self.project = project
		self.locations = locations.sorted(<)
	}
}

extension DuplicateDependency: Printable {
	public var description: String {
		return "\(project) \(printableLocations)"
	}

	private var printableLocations: String {
		if locations.count == 0 {
			return ""
		}

		return "(found in "
			+ " and ".join(locations)
			+ ")"
	}
}

private func <(lhs: DuplicateDependency, rhs: DuplicateDependency) -> Bool {
	if lhs.description < rhs.description {
		return true
	}

	if lhs.locations.count < rhs.locations.count {
		return true
	}
	else if lhs.locations.count > rhs.locations.count {
		return false
	}

	for (index, lhsLocation) in enumerate(lhs.locations) {
		if lhsLocation < rhs.locations[index] {
			return true
		}
		else if lhsLocation > rhs.locations[index] {
			return false
		}
	}

	return false
}
