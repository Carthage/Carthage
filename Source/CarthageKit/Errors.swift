//
//  Errors.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-24.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import ReactiveCocoa
import ReactiveTask

/// Possible errors that can originate from Carthage.
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
	case ReadFailed(NSURL, NSError?)

	/// Failed to write a file or directory at the given URL.
	case WriteFailed(NSURL, NSError?)

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
	
	/// An error occurred while shelling out.
	case TaskError(ReactiveTaskError)
}

extension CarthageError: Printable {
	public var description: String {
		switch self {
		case let .InvalidArgument(description):
			return description

		case let .MissingBuildSetting(setting):
			return "xcodebuild did not return a value for build setting \(setting)"

		case let .ReadFailed(fileURL, underlyingError):
			var description = "Failed to read file or folder at \(fileURL.path!)"

			if let underlyingError = underlyingError {
				description += ": \(underlyingError)"
			}

			return description

		case let .WriteFailed(fileURL, underlyingError):
			var description = "Failed to write to \(fileURL.path!)"

			if let underlyingError = underlyingError {
				description += ": \(underlyingError)"
			}

			return description

		case let .IncompatibleRequirements(dependency, first, second):
			return "Could not pick a version for \(dependency), due to mutually incompatible requirements:\n\t\(first)\n\t\(second)"

		case let .TaggedVersionNotFound(dependency):
			return "No tagged versions found for \(dependency)"

		case let .RequiredVersionNotFound(dependency, specifier):
			return "No available version for \(dependency) satisfies the requirement: \(specifier)"

		case let .RepositoryCheckoutFailed(workingDirectoryURL, reason):
			return "Failed to check out repository into \(workingDirectoryURL.path!): \(reason)"

		case let .ParseError(description):
			return "Parse error: \(description)"

		case let .InvalidArchitectures(description):
			return "Invalid architecture: \(description)"

		case let .MissingEnvironmentVariable(variable):
			return "Environment variable not set: \(variable)"

		case let .NoSharedSchemes(project):
			return "Project \"\(project)\" has no shared schemes"

		case let .DuplicateDependencies(duplicateDeps):
			let deps = duplicateDeps
				.sorted(<) // important to match expected order in test cases
				.reduce("") { (acc, dep) in
					"\(acc)\n\t\(dep)"
				}

			return "The following dependencies are duplicates:\(deps)"

		case let .TaskError(taskError):
			return taskError.description
		}
	}
}

extension CarthageError: ErrorType {
	public var nsError: NSError {
		let defaultError: () -> NSError = {
			return NSError(domain: "org.carthage.CarthageKit", code: 0, userInfo: [
				NSLocalizedDescriptionKey: self.description
			])
		}

		switch self {
		case let .TaskError(taskError):
			return taskError.nsError

		case let .ReadFailed(_, underlyingError):
			return underlyingError ?? defaultError()

		case let .WriteFailed(_, underlyingError):
			return underlyingError ?? defaultError()

		default:
			return defaultError()
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

	for (lhsLocation, rhsLocation) in Zip2(lhs.locations, rhs.locations) {
		if lhsLocation < rhsLocation {
			return true
		}
		else if lhsLocation > rhsLocation {
			return false
		}
	}

	return false
}
