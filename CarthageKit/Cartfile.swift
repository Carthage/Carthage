//
//  Cartfile.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation

public struct Dependency {
	public var repository: Repository
	public var version: VersionSpecifier
}

public struct Version: Comparable {
	public let major: Int
	public let minor: Int
	public let patch: Int
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
