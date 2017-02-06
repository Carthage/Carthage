//
//  BuildOptions.swift
//  Carthage
//
//  Created by Syo Ikeda on 5/22/16.
//  Copyright © 2016 Carthage. All rights reserved.
//

import XCDBLD

/// The build options used for building `xcodebuild` command.
public struct BuildOptions {
	/// The Xcode configuration to build.
	public var configuration: String
	/// The platforms to build for.
	public var platforms: Set<Platform>
	/// The toolchain to build with.
	public var toolchain: String?
	/// The path to the custom derived data folder.
	public var derivedDataPath: String?

	public init(configuration: String, platforms: Set<Platform> = [], toolchain: String? = nil, derivedDataPath: String? = nil) {
		self.configuration = configuration
		self.platforms = platforms
		self.toolchain = toolchain
		self.derivedDataPath = derivedDataPath
	}
}
