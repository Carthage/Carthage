//
//  Update.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-12.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa
import CarthageKit

public struct UpdateCommand: CommandType {
	public let verb = "update"
	public let function = "Clone, check out, and build the dependencies in the project's Cartfile"

	public func run(mode: CommandMode) -> Result<()> {
		return ColdSignal.fromResult(UpdateOptions.evaluate(mode))
			.map { options -> ColdSignal<()> in
				let directoryURL = NSURL.fileURLWithPath(options.directoryPath, isDirectory: true)!

				var buildSignal: ColdSignal<()> = .empty()
				if options.buildAfterUpdate {
					buildSignal = BuildCommand().buildWithOptions(BuildOptions(configuration: options.configuration, skipCurrent: true, directoryPath: options.directoryPath))
				}

				return ColdSignal.fromResult(Project.loadFromDirectory(directoryURL))
					.map { $0.updateDependencies() }
					.merge(identity)
					.then(buildSignal)
			}
			.merge(identity)
			.wait()
	}
}

private struct UpdateOptions: OptionsType {
	let buildAfterUpdate: Bool
	let configuration: String
	let directoryPath: String

	static func create(configuration: String)(buildAfterUpdate: Bool)(directoryPath: String) -> UpdateOptions {
		return self(buildAfterUpdate: buildAfterUpdate, configuration: configuration, directoryPath: directoryPath)
	}

	static func evaluate(m: CommandMode) -> Result<UpdateOptions> {
		return create
			<*> m <| Option(key: "configuration", defaultValue: "Release", usage: "the Xcode configuration to build (if --build is enabled)")
			<*> m <| Option(key: "build", defaultValue: true, usage: "whether to build dependencies after updating")
			<*> m <| Option(defaultValue: NSFileManager.defaultManager().currentDirectoryPath, usage: "the directory containing the Carthage project")
	}
}
