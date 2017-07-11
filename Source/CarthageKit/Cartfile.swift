import Foundation
import Result
import ReactiveSwift
import Tentacle

/// The relative path to a project's checked out dependencies.
public let carthageProjectCheckoutsPath = "Carthage/Checkouts"

/// Represents a Cartfile, which is a specification of a project's dependencies
/// and any other settings Carthage needs to build it.
public struct Cartfile {
	/// The dependencies listed in the Cartfile.
	public var dependencies: [Dependency: VersionSpecifier]

	public init(dependencies: [Dependency: VersionSpecifier] = [:]) {
		self.dependencies = dependencies
	}

	/// Returns the location where Cartfile should exist within the given
	/// directory.
	public static func url(in directoryURL: URL) -> URL {
		return directoryURL.appendingPathComponent("Cartfile")
	}

	/// Attempts to parse Cartfile information from a string.
	public static func from(string: String) -> Result<Cartfile, CarthageError> {
		var dependencies: [Dependency: VersionSpecifier] = [:]
		var duplicates: [Dependency] = []
		var result: Result<(), CarthageError> = .success(())

		let commentIndicator = "#"
		string.enumerateLines { line, stop in
			let scanner = Scanner(string: line)

			if scanner.scanString(commentIndicator, into: nil) {
				// Skip the rest of the line.
				return
			}

			if scanner.isAtEnd {
				// The line was all whitespace.
				return
			}

			switch Dependency.from(scanner).fanout(VersionSpecifier.from(scanner)) {
			case let .success((dependency, version)):
				if case .binary = dependency, case .gitReference = version {
					result = .failure(
						CarthageError.parseError(
							description: "binary dependencies cannot have a git reference for the version specifier in line: \(scanner.currentLine)"
						)
					)
					stop = true
					return
				}

				if dependencies[dependency] == nil {
					dependencies[dependency] = version
				} else {
					duplicates.append(dependency)
				}

			case let .failure(error):
				result = .failure(CarthageError(scannableError: error))
				stop = true
				return
			}

			if scanner.scanString(commentIndicator, into: nil) {
				// Skip the rest of the line.
				return
			}

			if !scanner.isAtEnd {
				result = .failure(CarthageError.parseError(description: "unexpected trailing characters in line: \(line)"))
				stop = true
			}
		}

		return result.flatMap { _ in
			if !duplicates.isEmpty {
				return .failure(.duplicateDependencies(duplicates.map { DuplicateDependency(dependency: $0, locations: []) }))
			}
			return .success(Cartfile(dependencies: dependencies))
		}
	}

	/// Attempts to parse a Cartfile from a file at a given URL.
	public static func from(file cartfileURL: URL) -> Result<Cartfile, CarthageError> {
		do {
			let cartfileContents = try String(contentsOf: cartfileURL, encoding: .utf8)
			return Cartfile
				.from(string: cartfileContents)
				.mapError { error in
					guard case let .duplicateDependencies(dupes) = error else {
						return error
					}

					let dependencies = dupes
						.map { dupe in
							return DuplicateDependency(
								dependency: dupe.dependency,
								locations: [ cartfileURL.path ]
							)
						}
					return .duplicateDependencies(dependencies)
				}
		} catch let error as NSError {
			return .failure(CarthageError.readFailed(cartfileURL, error))
		}
	}

	/// Appends the contents of another Cartfile to that of the receiver.
	public mutating func append(_ cartfile: Cartfile) {
		for (dependency, version) in cartfile.dependencies {
			dependencies[dependency] = version
		}
	}
}

/// Returns an array containing dependencies that are listed in both arguments.
public func duplicateDependenciesIn(_ cartfile1: Cartfile, _ cartfile2: Cartfile) -> [Dependency] {
	let projects1 = cartfile1.dependencies.keys
	let projects2 = cartfile2.dependencies.keys
	return Array(Set(projects1).intersection(Set(projects2)))
}

/// Represents a parsed Cartfile.resolved, which specifies which exact version was
/// checked out for each dependency.
public struct ResolvedCartfile {
	/// The dependencies listed in the Cartfile.resolved.
	public var dependencies: [Dependency: PinnedVersion]

	public init(dependencies: [Dependency: PinnedVersion]) {
		self.dependencies = dependencies
	}

	/// Returns the location where Cartfile.resolved should exist within the given
	/// directory.
	public static func url(in directoryURL: URL) -> URL {
		return directoryURL.appendingPathComponent("Cartfile.resolved")
	}

	/// Attempts to parse Cartfile.resolved information from a string.
	public static func from(string: String) -> Result<ResolvedCartfile, CarthageError> {
		var cartfile = self.init(dependencies: [:])
		var result: Result<(), CarthageError> = .success(())

		let scanner = Scanner(string: string)
		scannerLoop: while !scanner.isAtEnd {
			switch Dependency.from(scanner).fanout(PinnedVersion.from(scanner)) {
			case let .success((dep, version)):
				cartfile.dependencies[dep] = version

			case let .failure(error):
				result = .failure(CarthageError(scannableError: error))
				break scannerLoop
			}
		}

		return result.map { _ in cartfile }
	}
}

extension ResolvedCartfile: CustomStringConvertible {
	public var description: String {
		return dependencies
			.sorted { $0.key.description < $1.key.description }
			.map { "\($0.key) \($0.value)\n" }
			.joined(separator: "")
	}
}

/// Uniquely identifies a project that can be used as a dependency.
public enum Dependency {
	/// A repository hosted on GitHub.com or GitHub Enterprise.
	case gitHub(Server, Repository)

	/// An arbitrary Git repository.
	case git(GitURL)

	/// A binary-only framework
	case binary(URL)

	/// The unique, user-visible name for this project.
	public var name: String {
		switch self {
		case let .gitHub(_, repo):
			return repo.name

		case let .git(url):
			return url.name ?? url.urlString

		case let .binary(url):
			return url.lastPathComponent.stripping(suffix: ".json")
		}
	}

	/// The path at which this project will be checked out, relative to the
	/// working directory of the main project.
	public var relativePath: String {
		return (carthageProjectCheckoutsPath as NSString).appendingPathComponent(name)
	}
}

extension Dependency {
	fileprivate init(gitURL: GitURL) {
		let githubHostIdentifier = "github.com"
		let urlString = gitURL.urlString

		if urlString.contains(githubHostIdentifier) {
			let gitbubHostScanner = Scanner(string: urlString)

			gitbubHostScanner.scanUpTo(githubHostIdentifier, into:nil)
			gitbubHostScanner.scanString(githubHostIdentifier, into: nil)

			// find an SCP or URL path separator
			let separatorFound = (gitbubHostScanner.scanString("/", into: nil) || gitbubHostScanner.scanString(":", into: nil)) && !gitbubHostScanner.isAtEnd

			let startOfOwnerAndNameSubstring = gitbubHostScanner.scanLocation

			if separatorFound && startOfOwnerAndNameSubstring <= urlString.utf16.count {
				let ownerAndNameSubstring = urlString[urlString.index(urlString.startIndex, offsetBy: startOfOwnerAndNameSubstring)..<urlString.endIndex]

				switch Repository.fromIdentifier(ownerAndNameSubstring as String) {
				case .success(let server, let repository):
					self = Dependency.gitHub(server, repository)

				default:
					self = Dependency.git(gitURL)
				}

				return
			}
		}

		self = Dependency.git(gitURL)
	}
}

extension Dependency: Comparable {
	public static func == (_ lhs: Dependency, _ rhs: Dependency) -> Bool {
		switch (lhs, rhs) {
		case let (.gitHub(left), .gitHub(right)):
			return left == right

		case let (.git(left), .git(right)):
			return left == right

		case let (.binary(left), .binary(right)):
			return left == right

		default:
			return false
		}
	}

	public static func < (_ lhs: Dependency, _ rhs: Dependency) -> Bool {
		return lhs.name.caseInsensitiveCompare(rhs.name) == .orderedAscending
	}
}

extension Dependency: Hashable {
	public var hashValue: Int {
		switch self {
		case let .gitHub(server, repo):
			return server.hashValue ^ repo.hashValue

		case let .git(url):
			return url.hashValue

		case let .binary(url):
			return url.hashValue
		}
	}
}

extension Dependency: Scannable {
	/// Attempts to parse a Dependency.
	public static func from(_ scanner: Scanner) -> Result<Dependency, ScannableError> {
		let parser: (String) -> Result<Dependency, ScannableError>

		if scanner.scanString("github", into: nil) {
			parser = { repoIdentifier in
				return Repository.fromIdentifier(repoIdentifier).map { self.gitHub($0, $1) }
			}
		} else if scanner.scanString("git", into: nil) {
			parser = { urlString in

				return .success(Dependency(gitURL: GitURL(urlString)))
			}
		} else if scanner.scanString("binary", into: nil) {
			parser = { urlString in
				if let url = URL(string: urlString) {
					if url.scheme == "https" {
						return .success(self.binary(url))
					} else {
						return .failure(ScannableError(message: "non-https URL found for dependency type `binary`", currentLine: scanner.currentLine))
					}
				} else {
					return .failure(ScannableError(message: "invalid URL found for dependency type `binary`", currentLine: scanner.currentLine))
				}
			}
		} else {
			return .failure(ScannableError(message: "unexpected dependency type", currentLine: scanner.currentLine))
		}

		if !scanner.scanString("\"", into: nil) {
			return .failure(ScannableError(message: "expected string after dependency type", currentLine: scanner.currentLine))
		}

		var address: NSString?
		if !scanner.scanUpTo("\"", into: &address) || !scanner.scanString("\"", into: nil) {
			return .failure(ScannableError(message: "empty or unterminated string after dependency type", currentLine: scanner.currentLine))
		}

		if let address = address {
			return parser(address as String)
		} else {
			return .failure(ScannableError(message: "empty string after dependency type", currentLine: scanner.currentLine))
		}
	}
}

extension Dependency: CustomStringConvertible {
	public var description: String {
		switch self {
		case let .gitHub(server, repo):
			let repoDescription: String
			switch server {
			case .dotCom:
				repoDescription = "\(repo.owner)/\(repo.name)"

			case .enterprise:
				repoDescription = "\(server.url(for: repo))"
			}
			return "github \"\(repoDescription)\""

		case let .git(url):
			return "git \"\(url)\""

		case let .binary(url):
			return "binary \"\(url.absoluteString)\""
		}
	}
}

extension Dependency {
	/// Returns the URL that the dependency's remote repository exists at.
	func gitURL(preferHTTPS: Bool) -> GitURL? {
		switch self {
		case let .gitHub(server, repository):
			if preferHTTPS {
				return server.httpsURL(for: repository)
			} else {
				return server.sshURL(for: repository)
			}

		case let .git(url):
			return url

		case .binary:
			return nil
		}
	}
}
