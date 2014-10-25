//
//  Build.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-11.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import LlamaKit
import ReactiveCocoa

struct BuildOptions: OptionsType {
	let configuration: String

	static func create(configuration: String) -> BuildOptions {
		return BuildOptions(configuration: configuration)
	}

	static func parse(args: [String]) -> ColdSignal<BuildOptions> {
		return create
			<*> args <| option("configuration", "Release", "The Xcode configuration to build")
	}
}

struct BuildCommand: CommandType {
	let verb = "build"

	func run(arguments: [String]) -> ColdSignal<()> {
		return BuildOptions.parse(arguments)
			.map { options in
				let directoryURL = NSURL.fileURLWithPath(NSFileManager.defaultManager().currentDirectoryPath)!
				return buildInDirectory(directoryURL, configuration: options.configuration)
			}
			.merge(identity)
	}
}
