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

public struct Version {
	public let major: Int
	public let minor: Int
	public let patch: Int
}

public enum VersionSpecifier {
	case Exactly(Version)
}
