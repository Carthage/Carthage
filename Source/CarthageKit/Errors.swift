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
import Tentacle

/// Possible errors that can originate from Carthage.
public enum CarthageError: ErrorType, Equatable {
	public typealias VersionRequirement = (specifier: VersionSpecifier, fromProject: ProjectIdentifier?)

	/// One or more arguments was invalid.
	case InvalidArgument(description: String)

	/// `xcodebuild` did not return a build setting that we needed.
	case MissingBuildSetting(String)

	/// Incompatible version specifiers were given for a dependency.
	case IncompatibleRequirements(ProjectIdentifier, VersionRequirement, VersionRequirement)

	/// No tagged versions could be found for the dependency.
	case TaggedVersionNotFound(ProjectIdentifier)

	/// No existent version could be found to satisfy the version specifier for
	/// a dependency.
	case RequiredVersionNotFound(ProjectIdentifier, VersionSpecifier)
	
	/// No entry could be found in Cartfile for a dependency with this name.
	case UnknownDependencies([String])

	/// No entry could be found in Cartfile.resolved for a dependency with this name.
	case UnresolvedDependencies([String])

	/// Failed to check out a repository.
	case RepositoryCheckoutFailed(workingDirectoryURL: NSURL, reason: String, underlyingError: NSError?)

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

	// An error occurred reading a dSYM or framework's UUIDs.
	case InvalidUUIDs(description: String)

	/// The project is not sharing any framework schemes, so Carthage cannot
	/// discover them.
	case NoSharedFrameworkSchemes(ProjectIdentifier, Set<Platform>)

	/// The project is not sharing any schemes, so Carthage cannot discover
	/// them.
	case NoSharedSchemes(ProjectLocator, Repository?)

	/// Timeout whilst running `xcodebuild`
	case XcodebuildTimeout(ProjectLocator)

	/// A cartfile contains duplicate dependencies, either in itself or across
	/// other cartfiles.
	case DuplicateDependencies([DuplicateDependency])

	// There was a cycle between dependencies in the associated graph.
	case DependencyCycle([ProjectIdentifier: Set<ProjectIdentifier>])
	
	/// A request to the GitHub API failed.
	case GitHubAPIRequestFailed(Client.Error)
	
	case GitHubAPITimeout

	/// An error occurred while shelling out.
	case TaskError(ReactiveTask.TaskError)

	// A carthage error for a generic NSError
	case GenericError(NSError)
}

private func == (lhs: CarthageError.VersionRequirement, rhs: CarthageError.VersionRequirement) -> Bool {
	return lhs.specifier == rhs.specifier && lhs.fromProject == rhs.fromProject
}

public func == (lhs: CarthageError, rhs: CarthageError) -> Bool {
	switch (lhs, rhs) {
	case let (.InvalidArgument(left), .InvalidArgument(right)):
		return left == right
	
	case let (.MissingBuildSetting(left), .MissingBuildSetting(right)):
		return left == right
	
	case let (.IncompatibleRequirements(left, la, lb), .IncompatibleRequirements(right, ra, rb)):
		let specifiersEqual = (la == ra && lb == rb) || (la == rb && rb == la)
		return left == right && specifiersEqual
	
	case let (.TaggedVersionNotFound(left), .TaggedVersionNotFound(right)):
		return left == right

	case let (.RequiredVersionNotFound(left, leftVersion), .RequiredVersionNotFound(right, rightVersion)):
		return left == right && leftVersion == rightVersion
	
	case let (.RepositoryCheckoutFailed(la, lb, lc), .RepositoryCheckoutFailed(ra, rb, rc)):
		return la == ra && lb == rb && lc == rc
	
	case let (.ReadFailed(la, lb), .ReadFailed(ra, rb)):
		return la == ra && lb == rb
	
	case let (.WriteFailed(la, lb), .WriteFailed(ra, rb)):
		return la == ra && lb == rb
	
	case let (.ParseError(left), .ParseError(right)):
		return left == right
	
	case let (.MissingEnvironmentVariable(left), .MissingEnvironmentVariable(right)):
		return left == right
	
	case let (.InvalidArchitectures(left), .InvalidArchitectures(right)):
		return left == right

	case let (.NoSharedFrameworkSchemes(la, lb), .NoSharedFrameworkSchemes(ra, rb)):
		return la == ra && lb == rb

	case let (.NoSharedSchemes(la, lb), .NoSharedSchemes(ra, rb)):
		return la == ra && lb == rb
	
	case let (.DuplicateDependencies(left), .DuplicateDependencies(right)):
		return left.sort() == right.sort()
	
	case let (.GitHubAPIRequestFailed(left), .GitHubAPIRequestFailed(right)):
		return left == right
		
	case (.GitHubAPITimeout, .GitHubAPITimeout):
		return true
	
	case let (.TaskError(left), .TaskError(right)):
		return left == right
	
	default:
		return false
	}
}

extension CarthageError: CustomStringConvertible {
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
			let requirement: VersionRequirement -> String = { specifier, fromProject in
				return "\(specifier)" + (fromProject.map { " (\($0))" } ?? "")
			}
			return "Could not pick a version for \(dependency), due to mutually incompatible requirements:\n\t\(requirement(first))\n\t\(requirement(second))"

		case let .TaggedVersionNotFound(dependency):
			return "No tagged versions found for \(dependency)"

		case let .RequiredVersionNotFound(dependency, specifier):
			return "No available version for \(dependency) satisfies the requirement: \(specifier)"

		case let .RepositoryCheckoutFailed(workingDirectoryURL, reason, underlyingError):
			var description = "Failed to check out repository into \(workingDirectoryURL.path!): \(reason)"

			if let underlyingError = underlyingError {
				description += " (\(underlyingError))"
			}

			return description

		case let .ParseError(description):
			return "Parse error: \(description)"

		case let .InvalidArchitectures(description):
			return "Invalid architecture: \(description)"

		case let .InvalidUUIDs(description):
			return "Invalid architecture UUIDs: \(description)"

		case let .MissingEnvironmentVariable(variable):
			return "Environment variable not set: \(variable)"

		case let .NoSharedFrameworkSchemes(projectIdentifier, platforms):
			var description = "Dependency \"\(projectIdentifier.name)\" has no shared framework schemes"
			if !platforms.isEmpty {
				let platformsString = platforms.map { $0.description }.joinWithSeparator(", ")
				description += " for any of the platforms: \(platformsString)"
			}

			switch projectIdentifier {
			case let .GitHub(repository):
				description += "\n\nIf you believe this to be an error, please file an issue with the maintainers at \(repository.newIssueURL.absoluteString)"

			case .Git:
				break
			case .HTTP:
				break
			}

			return description

		case let .NoSharedSchemes(project, repository):
			var description = "Project \"\(project)\" has no shared schemes"
			if let repository = repository {
				description += "\n\nIf you believe this to be an error, please file an issue with the maintainers at \(repository.newIssueURL.absoluteString)"
			}

			return description

		case let .XcodebuildTimeout(project):
			return "xcodebuild timed out while trying to read \(project) 😭"
			
		case let .DuplicateDependencies(duplicateDeps):
			let deps = duplicateDeps.sort() // important to match expected order in test cases
				.reduce("") { (acc, dep) in
					"\(acc)\n\t\(dep)"
				}

			return "The following dependencies are duplicates:\(deps)"

		case let .DependencyCycle(graph):
			let prettyGraph = graph
				.map { (project, dependencies) in
					let prettyDependencies = dependencies
						.map { $0.name }
						.joinWithSeparator(", ")

					return "\(project.name): \(prettyDependencies)"
				}
				.joinWithSeparator("\n")

			return "The dependency graph contained a cycle:\n\(prettyGraph)"

		case let .GitHubAPIRequestFailed(message):
			return "GitHub API request failed: \(message)"
			
		case .GitHubAPITimeout:
			return "GitHub API timed out"
			
		case let .UnknownDependencies(names):
			return "No entry found for \(names.count > 1 ? "dependencies" : "dependency") \(names.joinWithSeparator(", ")) in Cartfile."

		case let .UnresolvedDependencies(names):
			return "No entry found for \(names.count > 1 ? "dependencies" : "dependency") \(names.joinWithSeparator(", ")) in Cartfile.resolved – please run `carthage update` if the dependency is contained in the project's Cartfile."

		case let .TaskError(taskError):
			return taskError.description

		case let .GenericError(error):
			return error.localizedDescription
		}
	}
}

/// A duplicate dependency, used in CarthageError.DuplicateDependencies.
public struct DuplicateDependency: Comparable {
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
		self.locations = locations.sort(<)
	}
}

extension DuplicateDependency: CustomStringConvertible {
	public var description: String {
		return "\(project) \(printableLocations)"
	}

	private var printableLocations: String {
		if locations.count == 0 {
			return ""
		}

		return "(found in "
			+ locations.joinWithSeparator(" and ")
			+ ")"
	}
}

public func == (lhs: DuplicateDependency, rhs: DuplicateDependency) -> Bool {
	return lhs.project == rhs.project && lhs.locations == rhs.locations
}

public func < (lhs: DuplicateDependency, rhs: DuplicateDependency) -> Bool {
	if lhs.description < rhs.description {
		return true
	}

	if lhs.locations.count < rhs.locations.count {
		return true
	}
	else if lhs.locations.count > rhs.locations.count {
		return false
	}

	for (lhsLocation, rhsLocation) in zip(lhs.locations, rhs.locations) {
		if lhsLocation < rhsLocation {
			return true
		}
		else if lhsLocation > rhsLocation {
			return false
		}
	}

	return false
}
