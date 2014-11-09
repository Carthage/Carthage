//
//  Cartfile.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit

/// Represents a Cartfile, which is a specification of a project's dependencies
/// and any other settings Carthage needs to build it.
public struct Cartfile {
	/// The dependencies listed in the Cartfile.
	public var dependencies: [Dependency<VersionSpecifier>]

	/// Attempts to parse Cartfile information from a string.
	public static func fromString(string: String) -> Result<Cartfile> {
		var cartfile = self(dependencies: [])
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

/// Represents a single dependency of a project.
public struct Dependency<V: VersionType>: Equatable {
	/// The GitHub repository in which this dependency lives.
	public var repository: Repository

	/// The version(s) that are required to satisfy this dependency.
	public var version: V
}

public func ==<V>(lhs: Dependency<V>, rhs: Dependency<V>) -> Bool {
	return lhs.repository == rhs.repository && lhs.version == rhs.version
}

extension Dependency: Scannable {
	/// Attempts to parse a Dependency specification.
	public static func fromScanner(scanner: NSScanner) -> Result<Dependency> {
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
			return Repository.fromNWO(repoNWO).flatMap { repo in
				return V.fromScanner(scanner).map { specifier in self(repository: repo, version: specifier) }
			}
		} else {
			return failure()
		}
	}
}

extension Dependency: Printable {
	public var description: String {
		return "\(repository) @ \(version)"
	}
}
