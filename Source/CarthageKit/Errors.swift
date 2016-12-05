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
	case invalidArgument(description: String)

	/// `xcodebuild` did not return a build setting that we needed.
	case missingBuildSetting(String)

	/// Incompatible version specifiers were given for a dependency.
	case incompatibleRequirements(ProjectIdentifier, VersionRequirement, VersionRequirement)

	/// No tagged versions could be found for the dependency.
	case taggedVersionNotFound(ProjectIdentifier)

	/// No existent version could be found to satisfy the version specifier for
	/// a dependency.
	case requiredVersionNotFound(ProjectIdentifier, VersionSpecifier)
	
	/// No entry could be found in Cartfile for a dependency with this name.
	case unknownDependencies([String])

	/// No entry could be found in Cartfile.resolved for a dependency with this name.
	case unresolvedDependencies([String])

	/// Failed to check out a repository.
	case repositoryCheckoutFailed(workingDirectoryURL: NSURL, reason: String, underlyingError: NSError?)

	/// Failed to read a file or directory at the given URL.
	case readFailed(NSURL, NSError?)

	/// Failed to write a file or directory at the given URL.
	case writeFailed(NSURL, NSError?)

	/// An error occurred parsing a Carthage file.
	case parseError(description: String)

	// An expected environment variable wasn't found.
	case missingEnvironmentVariable(variable: String)

	// An error occurred reading a framework's architectures.
	case invalidArchitectures(description: String)

	// An error occurred reading a dSYM or framework's UUIDs.
	case invalidUUIDs(description: String)

	/// The project is not sharing any framework schemes, so Carthage cannot
	/// discover them.
	case noSharedFrameworkSchemes(ProjectIdentifier, Set<Platform>)

	/// The project is not sharing any schemes, so Carthage cannot discover
	/// them.
	case noSharedSchemes(ProjectLocator, Repository?)

	/// Timeout whilst running `xcodebuild`
	case xcodebuildTimeout(ProjectLocator)

	/// A cartfile contains duplicate dependencies, either in itself or across
	/// other cartfiles.
	case duplicateDependencies([DuplicateDependency])

	// There was a cycle between dependencies in the associated graph.
	case dependencyCycle([ProjectIdentifier: Set<ProjectIdentifier>])
	
	/// A request to the GitHub API failed.
	case gitHubAPIRequestFailed(Client.Error)
	
	case gitHubAPITimeout

	/// An error occurred while shelling out.
	case taskError(TaskError)
}

private func == (lhs: CarthageError.VersionRequirement, rhs: CarthageError.VersionRequirement) -> Bool {
	return lhs.specifier == rhs.specifier && lhs.fromProject == rhs.fromProject
}

public func == (lhs: CarthageError, rhs: CarthageError) -> Bool {
	switch (lhs, rhs) {
	case let (.invalidArgument(left), .invalidArgument(right)):
		return left == right
	
	case let (.missingBuildSetting(left), .missingBuildSetting(right)):
		return left == right
	
	case let (.incompatibleRequirements(left, la, lb), .incompatibleRequirements(right, ra, rb)):
		let specifiersEqual = (la == ra && lb == rb) || (la == rb && rb == la)
		return left == right && specifiersEqual
	
	case let (.taggedVersionNotFound(left), .taggedVersionNotFound(right)):
		return left == right

	case let (.requiredVersionNotFound(left, leftVersion), .requiredVersionNotFound(right, rightVersion)):
		return left == right && leftVersion == rightVersion
	
	case let (.repositoryCheckoutFailed(la, lb, lc), .repositoryCheckoutFailed(ra, rb, rc)):
		return la == ra && lb == rb && lc == rc
	
	case let (.readFailed(la, lb), .readFailed(ra, rb)):
		return la == ra && lb == rb
	
	case let (.writeFailed(la, lb), .writeFailed(ra, rb)):
		return la == ra && lb == rb
	
	case let (.parseError(left), .parseError(right)):
		return left == right
	
	case let (.missingEnvironmentVariable(left), .missingEnvironmentVariable(right)):
		return left == right
	
	case let (.invalidArchitectures(left), .invalidArchitectures(right)):
		return left == right

	case let (.noSharedFrameworkSchemes(la, lb), .noSharedFrameworkSchemes(ra, rb)):
		return la == ra && lb == rb

	case let (.noSharedSchemes(la, lb), .noSharedSchemes(ra, rb)):
		return la == ra && lb == rb
	
	case let (.duplicateDependencies(left), .duplicateDependencies(right)):
		return left.sort() == right.sort()
	
	case let (.gitHubAPIRequestFailed(left), .gitHubAPIRequestFailed(right)):
		return left == right
		
	case (.gitHubAPITimeout, .gitHubAPITimeout):
		return true
	
	case let (.taskError(left), .taskError(right)):
		return left == right
	
	default:
		return false
	}
}

extension CarthageError: CustomStringConvertible {
	public var description: String {
		switch self {
		case let .invalidArgument(description):
			return description

		case let .missingBuildSetting(setting):
			return "xcodebuild did not return a value for build setting \(setting)"

		case let .readFailed(fileURL, underlyingError):
			var description = "Failed to read file or folder at \(fileURL.path!)"

			if let underlyingError = underlyingError {
				description += ": \(underlyingError)"
			}

			return description

		case let .writeFailed(fileURL, underlyingError):
			var description = "Failed to write to \(fileURL.path!)"

			if let underlyingError = underlyingError {
				description += ": \(underlyingError)"
			}

			return description

		case let .incompatibleRequirements(dependency, first, second):
			let requirement: (VersionRequirement) -> String = { specifier, fromProject in
				return "\(specifier)" + (fromProject.map { " (\($0))" } ?? "")
			}
			return "Could not pick a version for \(dependency), due to mutually incompatible requirements:\n\t\(requirement(first))\n\t\(requirement(second))"

		case let .taggedVersionNotFound(dependency):
			return "No tagged versions found for \(dependency)"

		case let .requiredVersionNotFound(dependency, specifier):
			return "No available version for \(dependency) satisfies the requirement: \(specifier)"

		case let .repositoryCheckoutFailed(workingDirectoryURL, reason, underlyingError):
			var description = "Failed to check out repository into \(workingDirectoryURL.path!): \(reason)"

			if let underlyingError = underlyingError {
				description += " (\(underlyingError))"
			}

			return description

		case let .parseError(description):
			return "Parse error: \(description)"

		case let .invalidArchitectures(description):
			return "Invalid architecture: \(description)"

		case let .invalidUUIDs(description):
			return "Invalid architecture UUIDs: \(description)"

		case let .missingEnvironmentVariable(variable):
			return "Environment variable not set: \(variable)"

		case let .noSharedFrameworkSchemes(projectIdentifier, platforms):
			var description = "Dependency \"\(projectIdentifier.name)\" has no shared framework schemes"
			if !platforms.isEmpty {
				let platformsString = platforms.map { $0.description }.joinWithSeparator(", ")
				description += " for any of the platforms: \(platformsString)"
			}

			switch projectIdentifier {
			case let .gitHub(repository):
				description += "\n\nIf you believe this to be an error, please file an issue with the maintainers at \(repository.newIssueURL.absoluteString)"

			case .git:
				break
			}

			return description

		case let .noSharedSchemes(project, repository):
			var description = "Project \"\(project)\" has no shared schemes"
			if let repository = repository {
				description += "\n\nIf you believe this to be an error, please file an issue with the maintainers at \(repository.newIssueURL.absoluteString)"
			}

			return description

		case let .xcodebuildTimeout(project):
			return "xcodebuild timed out while trying to read \(project) 😭"
			
		case let .duplicateDependencies(duplicateDeps):
			let deps = duplicateDeps.sort() // important to match expected order in test cases
				.reduce("") { (acc, dep) in
					"\(acc)\n\t\(dep)"
				}

			return "The following dependencies are duplicates:\(deps)"

		case let .dependencyCycle(graph):
			let prettyGraph = graph
				.map { (project, dependencies) in
					let prettyDependencies = dependencies
						.map { $0.name }
						.joinWithSeparator(", ")

					return "\(project.name): \(prettyDependencies)"
				}
				.joinWithSeparator("\n")

			return "The dependency graph contained a cycle:\n\(prettyGraph)"

		case let .gitHubAPIRequestFailed(message):
			return "GitHub API request failed: \(message)"
			
		case .gitHubAPITimeout:
			return "GitHub API timed out"
			
		case let .unknownDependencies(names):
			return "No entry found for \(names.count > 1 ? "dependencies" : "dependency") \(names.joinWithSeparator(", ")) in Cartfile."

		case let .unresolvedDependencies(names):
			return "No entry found for \(names.count > 1 ? "dependencies" : "dependency") \(names.joinWithSeparator(", ")) in Cartfile.resolved – please run `carthage update` if the dependency is contained in the project's Cartfile."

		case let .taskError(taskError):
			return taskError.description
		}
	}
}

/// A duplicate dependency, used in CarthageError.duplicateDependencies.
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
