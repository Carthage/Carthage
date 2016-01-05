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

/// The relative path to a project's checked out dependencies.
public let CarthageProjectCheckoutsPath = "Carthage/Checkouts"

/// Represents a Cartfile, which is a specification of a project's dependencies
/// and any other settings Carthage needs to build it.
public struct Cartfile {
	/// The dependencies listed in the Cartfile.
	public var dependencies: [Dependency<VersionSpecifier>]

	public init(dependencies: [Dependency<VersionSpecifier>] = []) {
		self.dependencies = dependencies
	}

	/// Returns the location where Cartfile should exist within the given
	/// directory.
	public static func URLInDirectory(directoryURL: NSURL) -> NSURL {
		return directoryURL.URLByAppendingPathComponent("Cartfile")
	}

	/// Attempts to parse Cartfile information from a string.
	public static func fromString(string: String) -> Result<Cartfile, CarthageError> {
		var cartfile = self.init()
		var result: Result<(), CarthageError> = .Success(())

		let commentIndicator = "#"
		string.enumerateLines { (line, stop) in
			let scanner = NSScanner(string: line)
			
			if scanner.scanString(commentIndicator, intoString: nil) {
				// Skip the rest of the line.
				return
			}

			if scanner.atEnd {
				// The line was all whitespace.
				return
			}

			switch Dependency<VersionSpecifier>.fromScanner(scanner) {
			case let .Success(dep):
				cartfile.dependencies.append(dep)

			case let .Failure(error):
				result = .Failure(error)
				stop = true
			}

			if scanner.scanString(commentIndicator, intoString: nil) {
				// Skip the rest of the line.
				return
			}

			if !scanner.atEnd {
				result = .Failure(CarthageError.ParseError(description: "unexpected trailing characters in line: \(line)"))
				stop = true
			}
		}

		return result.map { _ in cartfile }
	}

	/// Attempts to parse a Cartfile from a file at a given URL.
	public static func fromFile(cartfileURL: NSURL) -> Result<Cartfile, CarthageError> {
		do {
			let cartfileContents = try NSString(contentsOfURL: cartfileURL, encoding: NSUTF8StringEncoding)
			return Cartfile.fromString(cartfileContents as String)
		} catch let error as NSError {
			return .Failure(CarthageError.ReadFailed(cartfileURL, error))
		}
	}

	/// Appends the contents of another Cartfile to that of the receiver.
	public mutating func appendCartfile(cartfile: Cartfile) {
		dependencies += cartfile.dependencies
	}
}

extension Cartfile: CustomStringConvertible {
	public var description: String {
		return dependencies.description
	}
}

// Duplicate dependencies
extension Cartfile {
	/// Returns an array containing projects that are listed as duplicate
	/// dependencies.
	public func duplicateProjects() -> [ProjectIdentifier] {
		return self.dependencyCountedSet.filter { $0.1 > 1 }
			.map { $0.0 }
	}

	/// Returns the dependencies in a cartfile as a counted set containing the
	/// corresponding projects, represented as a dictionary.
	private var dependencyCountedSet: [ProjectIdentifier: Int] {
		return buildCountedSet(self.dependencies.map { $0.project })
	}
}

/// Returns an array containing projects that are listed as dependencies
/// in both arguments.
public func duplicateProjectsInCartfiles(cartfile1: Cartfile, _ cartfile2: Cartfile) -> [ProjectIdentifier] {
	let projectSet1 = cartfile1.dependencyCountedSet

	return cartfile2.dependencies
		.map { $0.project }
		.filter { projectSet1[$0] != nil }
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
	public static func URLInDirectory(directoryURL: NSURL) -> NSURL {
		return directoryURL.URLByAppendingPathComponent("Cartfile.resolved")
	}

	/// Attempts to parse Cartfile.resolved information from a string.
	public static func fromString(string: String) -> Result<ResolvedCartfile, CarthageError> {
		var cartfile = self.init(dependencies: [])
		var result: Result<(), CarthageError> = .Success(())

		let scanner = NSScanner(string: string)
		scannerLoop: while !scanner.atEnd {
			switch Dependency<PinnedVersion>.fromScanner(scanner) {
			case let .Success(dep):
				cartfile.dependencies.append(dep)

			case let .Failure(error):
				result = .Failure(error)
				break scannerLoop
			}
		}

		return result.map { _ in cartfile }
	}

	/// Returns the dependency whose project matches the given project or nil.
	internal func dependencyForProject(project: ProjectIdentifier) -> Dependency<PinnedVersion>? {
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
public enum ProjectIdentifier: Equatable {
	/// A repository hosted on GitHub.com.
	case GitHub(GitHubRepository)

	/// An arbitrary Git repository.
	case Git(GitURL)

	/// The unique, user-visible name for this project.
	public var name: String {
		switch self {
		case let .GitHub(repo):
			return repo.name

		case let .Git(URL):
			return URL.name ?? URL.URLString
		}
	}

	/// The path at which this project will be checked out, relative to the
	/// working directory of the main project.
	public var relativePath: String {
		return (CarthageProjectCheckoutsPath as NSString).stringByAppendingPathComponent(name)
	}
}

public func ==(lhs: ProjectIdentifier, rhs: ProjectIdentifier) -> Bool {
	switch (lhs, rhs) {
	case let (.GitHub(left), .GitHub(right)):
		return left == right

	case let (.Git(left), .Git(right)):
		return left == right

	default:
		return false
	}
}

extension ProjectIdentifier: Hashable {
	public var hashValue: Int {
		switch self {
		case let .GitHub(repo):
			return repo.hashValue

		case let .Git(URL):
			return URL.hashValue
		}
	}
}

extension ProjectIdentifier: Scannable {
	/// Attempts to parse a ProjectIdentifier.
	public static func fromScanner(scanner: NSScanner) -> Result<ProjectIdentifier, CarthageError> {
		let parser: (String -> Result<ProjectIdentifier, CarthageError>)

		if scanner.scanString("github", intoString: nil) {
			parser = { repoIdentifier in
				return GitHubRepository.fromIdentifier(repoIdentifier).map { self.GitHub($0) }
			}
		} else if scanner.scanString("git", intoString: nil) {
			parser = { URLString in
				return .Success(self.Git(GitURL(URLString)))
			}
		} else {
			return .Failure(CarthageError.ParseError(description: "unexpected dependency type in line: \(scanner.currentLine)"))
		}

		if !scanner.scanString("\"", intoString: nil) {
			return .Failure(CarthageError.ParseError(description: "expected string after dependency type in line: \(scanner.currentLine)"))
		}

		var address: NSString? = nil
		if !scanner.scanUpToString("\"", intoString: &address) || !scanner.scanString("\"", intoString: nil) {
			return .Failure(CarthageError.ParseError(description: "empty or unterminated string after dependency type in line: \(scanner.currentLine)"))
		}

		if let address = address {
			return parser(address as String)
		} else {
			return .Failure(CarthageError.ParseError(description: "empty string after dependency type in line: \(scanner.currentLine)"))
		}
	}
}

extension ProjectIdentifier: CustomStringConvertible {
	public var description: String {
		switch self {
		case let .GitHub(repo):
			return "github \"\(repo)\""

		case let .Git(URL):
			return "git \"\(URL)\""
		}
	}
}

/// Represents a single dependency of a project.
public struct Dependency<V: VersionType>: Equatable {
	/// The project corresponding to this dependency.
	public let project: ProjectIdentifier

	/// The version(s) that are required to satisfy this dependency.
	public var version: V

	public init(project: ProjectIdentifier, version: V) {
		self.project = project
		self.version = version
	}
}

public func ==<V>(lhs: Dependency<V>, rhs: Dependency<V>) -> Bool {
	return lhs.project == rhs.project && lhs.version == rhs.version
}

extension Dependency where V: Scannable {
	/// Attempts to parse a Dependency specification.
	public static func fromScanner(scanner: NSScanner) -> Result<Dependency, CarthageError> {
		return ProjectIdentifier.fromScanner(scanner).flatMap { identifier in
			return V.fromScanner(scanner).map { specifier in self.init(project: identifier, version: specifier) }
		}
	}
}

extension Dependency: CustomStringConvertible {
	public var description: String {
		return "\(project) \(version)"
	}
}
