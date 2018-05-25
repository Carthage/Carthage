import Foundation
import ReactiveSwift
import ReactiveTask
import Tentacle
import XCDBLD

/// Possible errors that can originate from Carthage.
public enum CarthageError: Error {
	public typealias VersionRequirement = (specifier: VersionSpecifier, fromDependency: Dependency?)

	/// One or more arguments was invalid.
	case invalidArgument(description: String)

	/// `xcodebuild` did not return a build setting that we needed.
	case missingBuildSetting(String)

	/// Incompatible version specifiers were given for a dependency.
	case incompatibleRequirements(Dependency, VersionRequirement, VersionRequirement)

	/// No tagged versions could be found for the dependency.
	case taggedVersionNotFound(Dependency)

	/// No existent version could be found to satisfy the version specifier for
	/// a dependency.
	case requiredVersionNotFound(Dependency, VersionSpecifier)

	/// No valid versions could be found, given the list of dependencies to update
	case unsatisfiableDependencyList([String])

	/// No entry could be found in Cartfile for a dependency with this name.
	case unknownDependencies([String])

	/// No entry could be found in Cartfile.resolved for a dependency with this name.
	case unresolvedDependencies([String])

	/// Conflicting dependencies, e.g. dependencies with the same name for which no definite resolution can be made.
	case incompatibleDependencies([Dependency])

	/// Failed to check out a repository.
	case repositoryCheckoutFailed(workingDirectoryURL: URL, reason: String, underlyingError: NSError?)

	/// Failed to read a file or directory at the given URL.
	case readFailed(URL, NSError?)

	/// Failed to write a file or directory at the given URL.
	case writeFailed(URL, NSError?)

	/// An error occurred parsing a Carthage file or task result
	case parseError(description: String)

	/// An error occurred parsing the binary-only framework definition file
	case invalidBinaryJSON(URL, BinaryJSONError)

	/// An expected environment variable wasn't found.
	case missingEnvironmentVariable(variable: String)

	/// An error occurred reading a framework's architectures.
	case invalidArchitectures(description: String)

	/// An error occurred reading a dSYM or framework's UUIDs.
	case invalidUUIDs(description: String)

	/// The project is not sharing any framework schemes, so Carthage cannot
	/// discover them.
	case noSharedFrameworkSchemes(Dependency, Set<Platform>)

	/// The project is not sharing any schemes, so Carthage cannot discover
	/// them.
	case noSharedSchemes(ProjectLocator, (Server, Repository)?)

	/// Timeout whilst running `xcodebuild`
	case xcodebuildTimeout(ProjectLocator)

	/// A cartfile contains duplicate dependencies, either in itself or across
	/// other cartfiles.
	case duplicateDependencies([DuplicateDependency])

	/// There was a cycle between dependencies in the associated graph.
	case dependencyCycle([Dependency: Set<Dependency>])

	/// A request to the GitHub API failed.
	case gitHubAPIRequestFailed(Client.Error)

	case gitHubAPITimeout

	case buildFailed(TaskError, log: URL?)

	/// An error occurred while shelling out.
	case taskError(TaskError)

	/// An internal error occurred
	case internalError(description: String)
}

extension CarthageError {
	public init(scannableError: ScannableError) {
		self = .parseError(description: "\(scannableError)")
	}
}

private func == (_ lhs: CarthageError.VersionRequirement, _ rhs: CarthageError.VersionRequirement) -> Bool {
	return lhs.specifier == rhs.specifier && lhs.fromDependency == rhs.fromDependency
}

extension CarthageError: Equatable {
	public static func == (_ lhs: CarthageError, _ rhs: CarthageError) -> Bool { // swiftlint:disable:this cyclomatic_complexity function_body_length
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

		case let (.unsatisfiableDependencyList(left), .unsatisfiableDependencyList(right)):
			return left == right

		case let (.repositoryCheckoutFailed(la, lb, lc), .repositoryCheckoutFailed(ra, rb, rc)):
			return la == ra && lb == rb && lc == rc

		case let (.readFailed(la, lb), .readFailed(ra, rb)):
			return la == ra && lb == rb

		case let (.writeFailed(la, lb), .writeFailed(ra, rb)):
			return la == ra && lb == rb

		case let (.parseError(left), .parseError(right)):
			return left == right

		case let (.invalidBinaryJSON(leftUrl, leftError), .invalidBinaryJSON(rightUrl, rightError)):
			return leftUrl == rightUrl && leftError == rightError

		case let (.missingEnvironmentVariable(left), .missingEnvironmentVariable(right)):
			return left == right

		case let (.invalidArchitectures(left), .invalidArchitectures(right)):
			return left == right

		case let (.noSharedFrameworkSchemes(la, lb), .noSharedFrameworkSchemes(ra, rb)):
			return la == ra && lb == rb

		case let (.noSharedSchemes(la, lb), .noSharedSchemes(ra, rb)):
			guard la == ra else { return false }

			switch (lb, rb) {
			case (nil, nil):
				return true

			case let ((lb1, lb2)?, (rb1, rb2)?):
				return lb1 == rb1 && lb2 == rb2

			default:
				return false
			}

		case let (.duplicateDependencies(left), .duplicateDependencies(right)):
			return left.sorted() == right.sorted()

		case let (.gitHubAPIRequestFailed(left), .gitHubAPIRequestFailed(right)):
			return left == right

		case (.gitHubAPITimeout, .gitHubAPITimeout):
			return true

		case let (.buildFailed(la, lb), .buildFailed(ra, rb)):
			return la == ra && lb == rb

		case let (.taskError(left), .taskError(right)):
			return left == right

		case let (.internalError(left), .internalError(right)):
			return left == right

		default:
			return false
		}
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
			var description = "Failed to read file or folder at \(fileURL.path)"

			if let underlyingError = underlyingError {
				description += ": \(underlyingError)"
			}

			return description

		case let .writeFailed(fileURL, underlyingError):
			var description = "Failed to write to \(fileURL.path)"

			if let underlyingError = underlyingError {
				description += ": \(underlyingError)"
			}

			return description

		case let .incompatibleRequirements(dependency, first, second):
			let requirement: (VersionRequirement) -> String = { arg in
				let (specifier, fromDependency) = arg
				return "\(specifier)" + (fromDependency.map { " (\($0))" } ?? "")
			}
			return "Could not pick a version for \(dependency), due to mutually incompatible requirements:\n\t\(requirement(first))\n\t\(requirement(second))"

		case let .taggedVersionNotFound(dependency):
			return "No tagged versions found for \(dependency)"

		case let .requiredVersionNotFound(dependency, specifier):
			return "No available version for \(dependency) satisfies the requirement: \(specifier)"

		case let .unsatisfiableDependencyList(subsetList):
			let subsetString = subsetList.map { "\t" + $0 }.joined(separator: "\n")
			return "No valid versions could be found that restrict updates to:\n\(subsetString)"

		case let .repositoryCheckoutFailed(workingDirectoryURL, reason, underlyingError):
			var description = "Failed to check out repository into \(workingDirectoryURL.path): \(reason)"

			if let underlyingError = underlyingError {
				description += " (\(underlyingError))"
			}

			return description

		case let .parseError(description):
			return "Parse error: \(description)"

		case let .invalidBinaryJSON(url, error):
			return "Unable to parse binary-only framework JSON at \(url) due to error: \(error)"

		case let .invalidArchitectures(description):
			return "Invalid architecture: \(description)"

		case let .invalidUUIDs(description):
			return "Invalid architecture UUIDs: \(description)"

		case let .missingEnvironmentVariable(variable):
			return "Environment variable not set: \(variable)"

		case let .noSharedFrameworkSchemes(dependency, platforms):
			var description = "Dependency \"\(dependency.name)\" has no shared framework schemes"
			if !platforms.isEmpty {
				let platformsString = platforms.map { $0.rawValue }.joined(separator: ", ")
				description += " for any of the platforms: \(platformsString)"
			}

			switch dependency {
			case let .gitHub(server, repository):
				description += "\n\nIf you believe this to be an error, please file an issue with the maintainers at \(server.newIssueURL(for: repository).absoluteString)"

			case .git, .binary:
				break
			}

			return description

		case let .noSharedSchemes(project, serverAndRepository):
			var description = "Project \"\(project)\" has no shared schemes"
			if let (server, repository) = serverAndRepository {
				description += "\n\nIf you believe this to be an error, please file an issue with the maintainers at \(server.newIssueURL(for: repository).absoluteString)"
			}

			return description

		case let .xcodebuildTimeout(project):
			return "xcodebuild timed out while trying to read \(project) 😭"

		case let .duplicateDependencies(duplicateDeps):
			let deps = duplicateDeps
				.sorted() // important to match expected order in test cases
				.map { "\n\t" + $0.description }
				.joined(separator: "")

			return "The following dependencies are duplicates:\(deps)"

		case let .dependencyCycle(graph):
			let prettyGraph = graph
				.map { project, dependencies in
					let prettyDependencies = dependencies
						.map { $0.name }
						.joined(separator: ", ")

					return "\(project.name): \(prettyDependencies)"
				}
				.joined(separator: "\n")

			return "The dependency graph contained a cycle:\n\(prettyGraph)"

		case let .gitHubAPIRequestFailed(message):
			return "GitHub API request failed: \(message)"

		case .gitHubAPITimeout:
			return "GitHub API timed out"

		case let .unknownDependencies(names):
			return "No entry found for \(names.count > 1 ? "dependencies" : "dependency") \(names.joined(separator: ", ")) in Cartfile."

		case let .unresolvedDependencies(names):
			return "No entry found for \(names.count > 1 ? "dependencies" : "dependency") \(names.joined(separator: ", ")) in Cartfile.resolved – "
				+ "please run `carthage update` if the dependency is contained in the project's Cartfile."

		case let .incompatibleDependencies(dependencies):
			return "No definite resolution could be made for incompatible dependencies [\(dependencies.map { $0.description }.joined(separator: ", "))"
				+ "] - add a definition for exactly one of these dependencies in the project's Cartfile to resolve this."

		case let .buildFailed(taskError, log):
			var message = "Build Failed\n"
			if case let .shellTaskFailed(task, exitCode, _) = taskError {
				message += "\tTask failed with exit code \(exitCode):\n"
				message += "\t\(task)\n"
			} else {
				message += "\t" + taskError.description + "\n"
			}

			message += "\nThis usually indicates that project itself failed to compile."
			if let log = log {
				message += " Please check the xcodebuild log for more details: \(log.path)"
			}

			return message

		case let .taskError(taskError):
			return taskError.description

		case let .internalError(description):
			return description
		}
	}
}
