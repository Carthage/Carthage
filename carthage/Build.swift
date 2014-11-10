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

public struct BuildCommand: CommandType {
	public let verb = "build"
	public let function = "Build the project in the current directory"

	public func run(mode: CommandMode) -> Result<()> {
		return ColdSignal.fromResult(BuildOptions.evaluate(mode))
			.map { options -> ColdSignal<()> in
				let directoryURL = NSURL.fileURLWithPath(NSFileManager.defaultManager().currentDirectoryPath)!
				return buildInDirectory(directoryURL, withConfiguration: options.configuration, onlyScheme: options.scheme)
					.then(.empty())
			}
			.merge(identity)
			.wait()
	}
}

private struct BuildOptions: OptionsType {
	let configuration: String
	let scheme: String?

	static func create(configuration: String)(scheme: String) -> BuildOptions {
		return self(configuration: configuration, scheme: (scheme.isEmpty ? nil : scheme))
	}

	static func evaluate(m: CommandMode) -> Result<BuildOptions> {
		return create
			<*> m <| Option(key: "configuration", defaultValue: "Release", usage: "the Xcode configuration to build")
			<*> m <| Option(key: "scheme", defaultValue: "", usage: "a scheme to build (if not specified, all schemes will be built)")
	}
}
