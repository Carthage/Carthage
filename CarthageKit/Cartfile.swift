//
//  Cartfile.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa

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
				result = failure()
				stop.memory = true
			}
		}

		return result.map { _ in cartfile }
	}
}

extension Cartfile: Printable {
	public var description: String {
		return "\(dependencies)"
	}
}

/// Represents a parsed Cartfile.lock, which specifies which exact version was
/// checked out for each dependency.
public struct CartfileLock {
	public var dependencies: [Dependency<PinnedVersion>]

	/// Returns the location where Cartfile.lock should exist within the given
	/// directory.
	public static func URLInDirectory(directoryURL: NSURL) -> NSURL {
		return directoryURL.URLByAppendingPathComponent("Cartfile.lock")
	}

	/// Attempts to parse Cartfile.lock information from a string.
	public static func fromString(string: String) -> Result<CartfileLock> {
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

extension CartfileLock: Printable {
	public var description: String {
		return "\(dependencies)"
	}
}

/// Uniquely identifies a project that can be used as a dependency.
public enum ProjectIdentifier: Equatable {
	/// A repository hosted on GitHub.com.
	case GitHub(Repository)

	/// The unique, user-visible name for this project.
	public var name: String {
		switch (self) {
		case let .GitHub(repo):
			return repo.name
		}
	}

	/// The path at which this project will be checked out, relative to the
	/// working directory of the main project.
	public var relativePath: String {
		return name
	}
}

public func ==(lhs: ProjectIdentifier, rhs: ProjectIdentifier) -> Bool {
	switch (lhs, rhs) {
	case let (.GitHub(left), .GitHub(right)):
		return left == right
	}
}

extension ProjectIdentifier: Hashable {
	public var hashValue: Int {
		switch (self) {
		case let .GitHub(repo):
			return repo.hashValue
		}
	}
}

extension ProjectIdentifier: Scannable {
	/// Attempts to parse a ProjectIdentifier.
	public static func fromScanner(scanner: NSScanner) -> Result<ProjectIdentifier> {
		if !scanner.scanString("github", intoString: nil) {
			return failure()
		}

		if !scanner.scanString("\"", intoString: nil) {
			return failure()
		}

		var repoNWO: NSString? = nil
		if !scanner.scanUpToString("\"", intoString: &repoNWO) || !scanner.scanString("\"", intoString: nil) {
			return failure()
		}

		if let repoNWO = repoNWO {
			return Repository.fromNWO(repoNWO).map { self.GitHub($0) }
		} else {
			return failure()
		}
	}
}

extension ProjectIdentifier: Printable {
	public var description: String {
		switch (self) {
		case let .GitHub(repo):
			return "github \"\(repo)\""
		}
	}
}

/// Represents a single dependency of a project.
public struct Dependency<V: VersionType>: Equatable {
	/// The unique identifier for this dependency.
	public let identifier: ProjectIdentifier

	/// The version(s) that are required to satisfy this dependency.
	public var version: V

	public init(identifier: ProjectIdentifier, version: V) {
		self.identifier = identifier
		self.version = version
	}

	/// Maps over the `version` in the receiver.
	public func map<W: VersionType>(f: V -> W) -> Dependency<W> {
		return Dependency<W>(identifier: identifier, version: f(version))
	}
}

public func ==<V>(lhs: Dependency<V>, rhs: Dependency<V>) -> Bool {
	return lhs.identifier == rhs.identifier && lhs.version == rhs.version
}

extension Dependency: Scannable {
	/// Attempts to parse a Dependency specification.
	public static func fromScanner(scanner: NSScanner) -> Result<Dependency> {
		return ProjectIdentifier.fromScanner(scanner).flatMap { identifier in
			return V.fromScanner(scanner).map { specifier in self(identifier: identifier, version: specifier) }
		}
	}
}

extension Dependency: Printable {
	public var description: String {
		return "\(identifier) @ \(version)"
	}
}
