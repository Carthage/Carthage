//
//  Cartfile.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import OGDL
import ReactiveCocoa

/// The relative path to a project's checked out dependencies.
public let CarthageProjectCheckoutsPath = "Carthage/Checkouts"

/// Represents anything that can be parsed from an OGDL node (and its
/// descendants).
internal protocol NodeParseable {
	/// Attempts to parse an instance of the receiver from the given node.
	///
	/// Upon success, returns the parsed value, and the first descendant node
	/// that was not touched.
	class func fromNode(node: Node) -> Result<(Self, Node?)>
}

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
	public static func fromString(string: String) -> Result<Cartfile> {
		var cartfile = self()
		var result = success(())

		let commentIndicator = "#"
		(string as NSString).enumerateLinesUsingBlock { (line, stop) in
			let scanner = NSScanner(string: line)
			if scanner.scanString(commentIndicator, intoString: nil) {
				// Skip the rest of the line.
				return
			}

			if scanner.atEnd {
				// The line was all whitespace.
				return
			}

			switch (Dependency<VersionSpecifier>.fromScanner(scanner)) {
			case let .Success(dep):
				cartfile.dependencies.append(dep.unbox)

			case let .Failure(error):
				result = failure(error)
				stop.memory = true
			}

			if scanner.scanString(commentIndicator, intoString: nil) {
				// Skip the rest of the line.
				return
			}

			if !scanner.atEnd {
				result = failure(CarthageError.ParseError(description: "unexpected trailing characters in line: \(line)").error)
				stop.memory = true
			}
		}

		return result.map { _ in cartfile }
	}

	/// Attempts to parse a Cartfile from a file at a given URL.
	public static func fromFile(cartfileURL: NSURL) -> Result<Cartfile> {
		var error: NSError?
		if let cartfileContents = NSString(contentsOfURL: cartfileURL, encoding: NSUTF8StringEncoding, error: &error) {
			return Cartfile.fromString(cartfileContents)
		} else {
			return failure(error ?? CarthageError.ReadFailed(cartfileURL).error)
		}
	}

	/// Appends the contents of another Cartfile to that of the receiver.
	public mutating func appendCartfile(cartfile: Cartfile) {
		dependencies += cartfile.dependencies
	}
}

extension Cartfile: Printable {
	public var description: String {
		return "\(dependencies)"
	}
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
	public static func fromString(string: String) -> Result<ResolvedCartfile> {
		var cartfile = self(dependencies: [])
		var result = success(())

		let scanner = NSScanner(string: string)
		scannerLoop: while !scanner.atEnd {
			switch (Dependency<PinnedVersion>.fromScanner(scanner)) {
			case let .Success(dep):
				cartfile.dependencies.append(dep.unbox)

			case let .Failure(error):
				result = failure(error)
				break scannerLoop
			}
		}

		return result.map { _ in cartfile }
	}
}

extension ResolvedCartfile: Printable {
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
		switch (self) {
		case let .GitHub(repo):
			return repo.name

		case let .Git(URL):
			return URL.name ?? URL.URLString
		}
	}

	/// The path at which this project will be checked out, relative to the
	/// working directory of the main project.
	public var relativePath: String {
		return CarthageProjectCheckoutsPath.stringByAppendingPathComponent(name)
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
		switch (self) {
		case let .GitHub(repo):
			return repo.hashValue

		case let .Git(URL):
			return URL.hashValue
		}
	}
}

extension ProjectIdentifier: Scannable {
	/// Attempts to parse a ProjectIdentifier.
	public static func fromScanner(scanner: NSScanner) -> Result<ProjectIdentifier> {
		var parser: (String -> Result<ProjectIdentifier>)!

		if scanner.scanString("github", intoString: nil) {
			parser = { repoNWO in
				return GitHubRepository.fromNWO(repoNWO).map { self.GitHub($0) }
			}
		} else if scanner.scanString("git", intoString: nil) {
			parser = { URLString in
				return success(self.Git(GitURL(URLString)))
			}
		} else {
			return failure(CarthageError.ParseError(description: "unexpected dependency type in line: \(scanner.currentLine)").error)
		}

		if !scanner.scanString("\"", intoString: nil) {
			return failure(CarthageError.ParseError(description: "expected string after dependency type in line: \(scanner.currentLine)").error)
		}

		var address: NSString? = nil
		if !scanner.scanUpToString("\"", intoString: &address) || !scanner.scanString("\"", intoString: nil) {
			return failure(CarthageError.ParseError(description: "empty or unterminated string after dependency type in line: \(scanner.currentLine)").error)
		}

		if let address = address {
			return parser(address)
		} else {
			return failure(CarthageError.ParseError(description: "empty string after dependency type in line: \(scanner.currentLine)").error)
		}
	}
}

extension GitHubRepository: NodeParseable {
	internal static func fromNode(node: Node) -> Result<(GitHubRepository, Node?)> {
		return fromNWO(node.value).map { repo in (repo, node.children.first) }
	}
}

extension GitURL: NodeParseable {
	internal static func fromNode(node: Node) -> Result<(GitURL, Node?)> {
		return success(self(node.value), node.children.first)
	}
}

extension ProjectIdentifier: NodeParseable {
	internal static func fromNode(node: Node) -> Result<(ProjectIdentifier, Node?)> {
		let addressResult: Result<Node> = {
			if let addressNode = node.children.first {
				return success(addressNode)
			} else {
				return failure(CarthageError.ParseError(description: "expected string after dependency type in \(node)").error)
			}
		}()

		switch node.value {
		case "github":
			return addressResult
				.flatMap { addressNode in GitHubRepository.fromNode(addressNode) }
				.map { repo, remainder in (self.GitHub(repo), remainder) }

		case "git":
			return addressResult
				.flatMap { addressNode in GitURL.fromNode(addressNode) }
				.map { repo, remainder in (self.Git(repo), remainder) }

		default:
			return failure(CarthageError.ParseError(description: "unexpected dependency type in \(node)").error)
		}
	}
}

extension ProjectIdentifier: Printable {
	public var description: String {
		switch (self) {
		case let .GitHub(repo):
			return "github \"\(repo)\""

		case let .Git(URL):
			return "git \"\(URL)\""
		}
	}
}

/// Represents a single dependency of a project.
public struct Dependency<V: Equatable>: Equatable {
	/// The project corresponding to this dependency.
	public let project: ProjectIdentifier

	/// The version(s) that are required to satisfy this dependency.
	public var version: V

	public init(project: ProjectIdentifier, version: V) {
		self.project = project
		self.version = version
	}

	/// Maps over the `version` in the receiver.
	public func map<W>(f: V -> W) -> Dependency<W> {
		return Dependency<W>(project: project, version: f(version))
	}
}

public func == <V>(lhs: Dependency<V>, rhs: Dependency<V>) -> Bool {
	return lhs.project == rhs.project && lhs.version == rhs.version
}

extension Dependency: Scannable {
	/// Attempts to parse a Dependency specification.
	public static func fromScanner(scanner: NSScanner) -> Result<Dependency> {
		return ProjectIdentifier.fromScanner(scanner).flatMap { identifier in
			return V.fromScanner(scanner).map { specifier in self(project: identifier, version: specifier) }
		}
	}
}

extension Dependency: Printable {
	public var description: String {
		return "\(project) \(version)"
	}
}
