//
//  Cartfile.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import Result
import ReactiveCocoa
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
	public static func from(string string: String) -> Result<Cartfile, CarthageError> {
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
			case let .Success(dep):
				dependencies.append(dep)

			case let .Failure(error):
				result = .failure(error)
				stop = true
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
								locations: [ cartfileURL.carthage_path ]
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
	return Array(Set(projects1).intersect(projects2))
}

/// Represents a parsed Cartfile.resolved, which specifies which exact version was
/// checked out for each dependency.
public struct ResolvedCartfile {
	/// The dependencies listed in the Cartfile.resolved, in the order that they
	/// should be built.
	public var dependencies: [Dependency<PinnedVersion>]

	public init(dependencies: [Dependency<PinnedVersion>]) {
		self.dependencies = dependencies
	}

	/// Returns the location where Cartfile.resolved should exist within the given
	/// directory.
	public static func url(in directoryURL: URL) -> URL {
		return directoryURL.appendingPathComponent("Cartfile.resolved")
	}

	/// Attempts to parse Cartfile.resolved information from a string.
	public static func from(string string: String) -> Result<ResolvedCartfile, CarthageError> {
		var cartfile = self.init(dependencies: [])
		var result: Result<(), CarthageError> = .success(())

		let scanner = Scanner(string: string)
		scannerLoop: while !scanner.isAtEnd {
			switch Dependency<PinnedVersion>.from(scanner) {
			case let .Success(dep):
				cartfile.dependencies.append(dep)

			case let .Failure(error):
				result = .failure(error)
				break scannerLoop
			}
		}

		return result.map { _ in cartfile }
	}

	/// Returns the dependency whose project matches the given project or nil.
	internal func dependency(for project: ProjectIdentifier) -> Dependency<PinnedVersion>? {
		return dependencies.lazy
			.filter { $0.project == project }
			.first
	}
}

extension ResolvedCartfile: CustomStringConvertible {
	public var description: String {
		return dependencies.reduce("") { (string, dependency) in
			return string + "\(dependency)\n"
		}
	}
}

/// Uniquely identifies a project that can be used as a dependency.
public enum ProjectIdentifier: Comparable {
	/// A repository hosted on GitHub.com.
	case gitHub(Repository)

	/// An arbitrary Git repository.
	case git(GitURL)

	/// The unique, user-visible name for this project.
	public var name: String {
		switch self {
		case let .gitHub(repo):
			return repo.name

		case let .git(url):
			return url.name ?? url.urlString
		}
	}

	/// The path at which this project will be checked out, relative to the
	/// working directory of the main project.
	public var relativePath: String {
		return (CarthageProjectCheckoutsPath as NSString).appendingPathComponent(name)
	}
}

public func ==(lhs: ProjectIdentifier, rhs: ProjectIdentifier) -> Bool {
	switch (lhs, rhs) {
	case let (.gitHub(left), .gitHub(right)):
		return left == right

	case let (.git(left), .git(right)):
		return left == right

	default:
		return false
	}
}

public func <(lhs: ProjectIdentifier, rhs: ProjectIdentifier) -> Bool {
	return lhs.name.caseInsensitiveCompare(rhs.name) == .orderedAscending
}

extension ProjectIdentifier: Hashable {
	public var hashValue: Int {
		switch self {
		case let .gitHub(repo):
			return repo.hashValue

		case let .git(url):
			return url.hashValue
		}
	}
}

extension ProjectIdentifier: Scannable {
	/// Attempts to parse a ProjectIdentifier.
	public static func from(_ scanner: Scanner) -> Result<ProjectIdentifier, CarthageError> {
		let parser: (String) -> Result<ProjectIdentifier, CarthageError>

		if scanner.scanString("github", into: nil) {
			parser = { repoIdentifier in
				return Repository.fromIdentifier(repoIdentifier).map { self.gitHub($0) }
			}
		} else if scanner.scanString("git", into: nil) {
			parser = { urlString in
				return .success(self.git(GitURL(urlString)))
			}
		} else {
			return .failure(CarthageError.parseError(description: "unexpected dependency type in line: \(scanner.currentLine)"))
		}

		if !scanner.scanString("\"", into: nil) {
			return .failure(CarthageError.parseError(description: "expected string after dependency type in line: \(scanner.currentLine)"))
		}

		var address: NSString? = nil
		if !scanner.scanUpTo("\"", into: &address) || !scanner.scanString("\"", into: nil) {
			return .failure(CarthageError.parseError(description: "empty or unterminated string after dependency type in line: \(scanner.currentLine)"))
		}

		if let address = address {
			return parser(address as String)
		} else {
			return .failure(CarthageError.parseError(description: "empty string after dependency type in line: \(scanner.currentLine)"))
		}
	}
}

extension ProjectIdentifier: CustomStringConvertible {
	public var description: String {
		switch self {
		case let .gitHub(repo):
			let repoDescription: String
			switch repo.server {
			case .DotCom:
				repoDescription = "\(repo.owner)/\(repo.name)"

			case .Enterprise:
				repoDescription = "\(repo.URL)"
			}
			return "github \"\(repoDescription)\""

		case let .git(url):
			return "git \"\(url)\""
		}
	}
}

/// Represents a single dependency of a project.
public struct Dependency<V: VersionType>: Hashable {
	/// The project corresponding to this dependency.
	public let project: ProjectIdentifier

	/// The version(s) that are required to satisfy this dependency.
	public var version: V

	public init(project: ProjectIdentifier, version: V) {
		self.project = project
		self.version = version
	}
	
	public var hashValue: Int {
		return project.hashValue ^ version.hashValue
	}
}

public func ==<V>(lhs: Dependency<V>, rhs: Dependency<V>) -> Bool {
	return lhs.project == rhs.project && lhs.version == rhs.version
}

extension Dependency where V: Scannable {
	/// Attempts to parse a Dependency specification.
	public static func from(_ scanner: Scanner) -> Result<Dependency, CarthageError> {
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
