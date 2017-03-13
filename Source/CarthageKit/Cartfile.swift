//
//  Cartfile.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import Result
import ReactiveSwift
import Tentacle

/// The relative path to a project's checked out dependencies.
public let CarthageProjectCheckoutsPath = "Carthage/Checkouts"

/// Represents a Cartfile, which is a specification of a project's dependencies
/// and any other settings Carthage needs to build it.
public struct Cartfile {
	/// The dependencies listed in the Cartfile.
	public var dependencies: Set<Dependency<VersionSpecifier>>

	public init(dependencies: Set<Dependency<VersionSpecifier>> = []) {
		self.dependencies = dependencies
	}

	/// Returns the location where Cartfile should exist within the given
	/// directory.
	public static func url(in directoryURL: URL) -> URL {
		return directoryURL.appendingPathComponent("Cartfile")
	}

	/// Attempts to parse Cartfile information from a string.
	public static func from(string: String) -> Result<Cartfile, CarthageError> {
		var dependencies: [Dependency<VersionSpecifier>] = []
		var result: Result<(), CarthageError> = .success(())

		let commentIndicator = "#"
		string.enumerateLines { (line, stop) in
			let scanner = Scanner(string: line)
			
			if scanner.scanString(commentIndicator, into: nil) {
				// Skip the rest of the line.
				return
			}

			if scanner.isAtEnd {
				// The line was all whitespace.
				return
			}

			switch Dependency<VersionSpecifier>.from(scanner) {
			case let .success(dep):
				if case .binary = dep.project, case .gitReference = dep.version {
					result = .failure(CarthageError.parseError(description: "binary dependencies cannot have a git reference for the version specifier in line: \(scanner.currentLine)"))
					stop = true
					return
				}
				dependencies.append(dep)

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
			let dupes = buildCountedSet(dependencies.map { $0.project })
				.filter { $0.1 > 1 }
				.map { $0.0 }
				.map { DuplicateDependency(project: $0, locations: []) }
			
			if !dupes.isEmpty {
				return .failure(.duplicateDependencies(dupes))
			}
			return .success(Cartfile(dependencies: Set(dependencies)))
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
						.map { dependency in
							return DuplicateDependency(
								project: dependency.project,
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
		dependencies.formUnion(cartfile.dependencies)
	}
}

extension Cartfile: CustomStringConvertible {
	public var description: String {
		return dependencies.description
	}
}

/// Returns an array containing projects that are listed as dependencies
/// in both arguments.
public func duplicateProjectsIn(_ cartfile1: Cartfile, _ cartfile2: Cartfile) -> [ProjectIdentifier] {
	let projects1 = cartfile1.dependencies.map { $0.project }
	let projects2 = cartfile2.dependencies.map { $0.project }
	return Array(Set(projects1).intersection(Set(projects2)))
}

/// Represents a parsed Cartfile.resolved, which specifies which exact version was
/// checked out for each dependency.
public struct ResolvedCartfile {
	/// The dependencies listed in the Cartfile.resolved.
	public var dependencies: Set<Dependency<PinnedVersion>>
	
	/// The version of each project
	public var versions: [ProjectIdentifier: PinnedVersion] {
		var versions: [ProjectIdentifier: PinnedVersion] = [:]
		for dependency in dependencies {
			versions[dependency.project] = dependency.version
		}
		return versions
	}

	public init(dependencies: Set<Dependency<PinnedVersion>>) {
		self.dependencies = dependencies
	}

	/// Returns the location where Cartfile.resolved should exist within the given
	/// directory.
	public static func url(in directoryURL: URL) -> URL {
		return directoryURL.appendingPathComponent("Cartfile.resolved")
	}

	/// Attempts to parse Cartfile.resolved information from a string.
	public static func from(string: String) -> Result<ResolvedCartfile, CarthageError> {
		var cartfile = self.init(dependencies: [])
		var result: Result<(), CarthageError> = .success(())

		let scanner = Scanner(string: string)
		scannerLoop: while !scanner.isAtEnd {
			switch Dependency<PinnedVersion>.from(scanner) {
			case let .success(dep):
				cartfile.dependencies.insert(dep)

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
			.sorted { $0.project.description < $1.project.description }
			.map { $0.description + "\n" }
			.joined(separator: "")
	}
}

/// Uniquely identifies a project that can be used as a dependency.
public enum ProjectIdentifier {
	/// A repository hosted on GitHub.com.
	case gitHub(Repository)

	/// An arbitrary Git repository.
	case git(GitURL)

	/// A binary-only framework
	case binary(URL)

	/// The unique, user-visible name for this project.
	public var name: String {
		switch self {
		case let .gitHub(repo):
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
		return (CarthageProjectCheckoutsPath as NSString).appendingPathComponent(name)
	}
}

extension ProjectIdentifier: Comparable {
	public static func ==(_ lhs: ProjectIdentifier, _ rhs: ProjectIdentifier) -> Bool {
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

	public static func <(_ lhs: ProjectIdentifier, _ rhs: ProjectIdentifier) -> Bool {
		return lhs.name.caseInsensitiveCompare(rhs.name) == .orderedAscending
	}
}

extension ProjectIdentifier: Hashable {
	public var hashValue: Int {
		switch self {
		case let .gitHub(repo):
			return repo.hashValue

		case let .git(url):
			return url.hashValue

		case let .binary(url):
			return url.hashValue
		}
	}
}

extension ProjectIdentifier: Scannable {
	/// Attempts to parse a ProjectIdentifier.
	public static func from(_ scanner: Scanner) -> Result<ProjectIdentifier, ScannableError> {
		let parser: (String) -> Result<ProjectIdentifier, ScannableError>

		if scanner.scanString("github", into: nil) {
			parser = { repoIdentifier in
				return Repository.fromIdentifier(repoIdentifier).map { self.gitHub($0) }
			}
		} else if scanner.scanString("git", into: nil) {
			parser = { urlString in
				return .success(self.git(GitURL(urlString)))
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

		var address: NSString? = nil
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

extension ProjectIdentifier: CustomStringConvertible {
	public var description: String {
		switch self {
		case let .gitHub(repo):
			let repoDescription: String
			switch repo.server {
			case .dotCom:
				repoDescription = "\(repo.owner)/\(repo.name)"

			case .enterprise:
				repoDescription = "\(repo.url)"
			}
			return "github \"\(repoDescription)\""

		case let .git(url):
			return "git \"\(url)\""

		case let .binary(url):
			return "binary \"\(url.absoluteString)\""
		}
	}
}

extension ProjectIdentifier {

	/// Returns the URL that the project's remote repository exists at.
	func gitURL(preferHTTPS: Bool) -> GitURL? {
		switch self {
		case let .gitHub(repository):
			if preferHTTPS {
				return repository.httpsURL
			} else {
				return repository.sshURL
			}

		case let .git(url):
			return url
		case .binary:
			return nil
		}
	}
	
}

/// Represents a single dependency of a project.
public struct Dependency<V: VersionType> {
	/// The project corresponding to this dependency.
	public let project: ProjectIdentifier

	/// The version(s) that are required to satisfy this dependency.
	public var version: V

	public init(project: ProjectIdentifier, version: V) {
		self.project = project
		self.version = version
	}
}

extension Dependency: Hashable {
	public static func ==<V>(_ lhs: Dependency<V>, _ rhs: Dependency<V>) -> Bool {
		return lhs.project == rhs.project && lhs.version == rhs.version
	}

	public var hashValue: Int {
		return project.hashValue ^ version.hashValue
	}
}

extension Dependency where V: Scannable {
	/// Attempts to parse a Dependency specification.
	public static func from(_ scanner: Scanner) -> Result<Dependency, ScannableError> {
		return ProjectIdentifier.from(scanner).flatMap { identifier in
			return V.from(scanner).map { specifier in self.init(project: identifier, version: specifier) }
		}
	}
}

extension Dependency: CustomStringConvertible {
	public var description: String {
		return "\(project) \(version)"
	}
}
