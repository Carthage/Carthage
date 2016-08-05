//
//  BuildOptions.swift
//  Carthage
//
//  Created by Syo Ikeda on 5/22/16.
//  Copyright © 2016 Carthage. All rights reserved.
//

/// The build options used for building `xcodebuild` command.
public struct BuildOptions {
	/// The Xcode configuration to build.
	public let configuration: String
	/// The platforms to build for.
	public let platforms: Set<Platform>
	/// The toolchain to build with.
	public let toolchain: String?
	/// The path to the custom derived data folder.
	public let derivedDataPath: String?

	public init(configuration: String, platforms: Set<Platform> = [], toolchain: String? = nil, derivedDataPath: String? = nil) {
		self.configuration = configuration
		self.platforms = platforms
		self.toolchain = toolchain
		self.derivedDataPath = derivedDataPath
	}
}
