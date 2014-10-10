//
//  Cartfile.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit

public struct Dependency {
	public var repository: Repository
	public var version: VersionSpecifier
}

public struct Version: Comparable {
	public let major: Int
	public let minor: Int
	public let patch: Int

	init(major: Int, minor: Int, patch: Int) {
		self.major = major
		self.minor = minor
		self.patch = patch
	}

	static func fromString(specifier: String) -> Result<Version> {
		let components = split(specifier, { $0 == "." }, allowEmptySlices: false)
		if components.count < 3 {
			return failure()
		}

		let major = components[0].toInt()
		if major == nil {
			return failure()
		}

		let minor = components[1].toInt()
		let patch = components[2].toInt()

		return success(self(major: major!, minor: minor ?? 0, patch: patch ?? 0))
	}
}

public func <(lhs: Version, rhs: Version) -> Bool {
	if (lhs.major < rhs.major) {
		return true
	} else if (lhs.major > rhs.major) {
		return false
	}

	if (lhs.minor < rhs.minor) {
		return true
	} else if (lhs.minor > rhs.minor) {
		return false
	}

	if (lhs.patch < rhs.patch) {
		return true
	} else if (lhs.patch > rhs.patch) {
		return false
	}

	return false
}

public func ==(lhs: Version, rhs: Version) -> Bool {
	return lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch
}

extension Version: Printable {
	public var description: String {
		return "\(major).\(minor).\(patch)"
	}
}

public enum VersionSpecifier {
	case Exactly(Version)
}

extension VersionSpecifier: JSONDecodable {
	public static func fromJSON(JSON: AnyObject) -> Result<VersionSpecifier> {
		if let specifier = JSON as? String {
			return Version.fromString(specifier).map { .Exactly($0) }
		} else {
			return failure()
		}
	}
}
