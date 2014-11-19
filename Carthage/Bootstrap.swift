//
//  Bootstrap.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-15.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa
import CarthageKit

public struct BootstrapCommand: CommandType {
	public let verb = "bootstrap"
	public let function = "Checks out and builds the locked dependency versions of the project"

	public func run(mode: CommandMode) -> Result<()> {
		return ColdSignal.fromResult(BootstrapOptions.evaluate(mode))
			.map { options -> ColdSignal<()> in
				let directoryURL = NSURL.fileURLWithPath(options.directoryPath, isDirectory: true)!
				let buildSignal = BuildCommand().buildWithOptions(BuildOptions(configuration: options.configuration, skipCurrent: true, directoryPath: options.directoryPath))

				return ColdSignal.fromResult(Project.loadFromDirectory(directoryURL))
					.on(next: { project in
						project.preferHTTPS = !options.useSSH
						project.projectEvents.observe(ProjectEventSink())
					})
					.map { project -> ColdSignal<()> in
						return ColdSignal.lazy {
							if NSFileManager.defaultManager().fileExistsAtPath(project.cartfileLockURL.path!) {
								return project.checkoutLockedDependencies()
							} else {
								println("*** No Cartfile.lock found, updating dependencies")
								return project.updateDependencies()
							}
						}
					}
					.merge(identity)
					.then(buildSignal)
			}
			.merge(identity)
			.wait()
	}
}

private struct BootstrapOptions: OptionsType {
	let configuration: String
	let directoryPath: String
	let useSSH: Bool

	static func create(configuration: String)(useSSH: Bool)(directoryPath: String) -> BootstrapOptions {
		return self(configuration: configuration, directoryPath: directoryPath, useSSH: useSSH)
	}

	static func evaluate(m: CommandMode) -> Result<BootstrapOptions> {
		return create
			<*> m <| Option(key: "configuration", defaultValue: "Release", usage: "the Xcode configuration to build (if --build is enabled)")
			<*> m <| Option(key: "use-ssh", defaultValue: false, usage: "whether to use SSH for GitHub repositories")
			<*> m <| Option(defaultValue: NSFileManager.defaultManager().currentDirectoryPath, usage: "the directory containing the Carthage project")
	}
}
