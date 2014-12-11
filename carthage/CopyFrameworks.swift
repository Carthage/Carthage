//
//  CopyFrameworks.swift
//  Carthage
//
//  Created by Robert Böhnke on 10/12/14.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Commandant
import Foundation
import LlamaKit
import ReactiveCocoa

public struct CopyFrameworksCommand: CommandType {
	public let verb = "copy-frameworks"
	public let function = "Copies the frameworks, striping symbols as necesssary."

	public func run(mode: CommandMode) -> Result<()> {
		return ColdSignal.fromResult(CopyFrameworksOptions.evaluate(mode))
			.map { options -> ColdSignal<()> in
				let from = NSURL.fileURLWithPath(options.sourcePath, isDirectory: true)!
				let frameworkName = from.lastPathComponent!

				let frameworksFolder = NSURL.fileURLWithPath(options.targetPath, isDirectory: true)!
				let frameworkLocation = frameworksFolder.URLByAppendingPathComponent(frameworkName, isDirectory: true)

				println("from: \(from)")
				println("frameworkName: \(frameworkName)")
				println("frameworksFolder: \(frameworksFolder)")
				println("frameworkLocation: \(frameworkLocation)")

				return copyFramework(from, frameworkLocation)
					// TODO: Check if these are actually in there and
					.concat(stripArchitecture(frameworkLocation, "x86_64"))
					.concat(stripArchitecture(frameworkLocation, "i386"))
					.concat(codesign(frameworkLocation, options.identity))
			}
			.merge(identity)
			.wait()
	}
}

public struct CopyFrameworksOptions: OptionsType {
	public let directoryPath: String
	public let identity: String
	public let sourcePath: String
	public let targetPath: String

	public static func create(sourcePath: String)(targetPath: String)(identity: String)(directoryPath: String) -> CopyFrameworksOptions {
		return self(directoryPath: directoryPath, identity: identity, sourcePath: sourcePath, targetPath: targetPath)
	}

	public static func evaluate(m: CommandMode) -> Result<CopyFrameworksOptions> {
		return create
			<*> m <| Option(key: "source-path", usage: "The source for to copy the framework from")
			<*> m <| Option(key: "target-path", usage: "The target for to copy the framework to")
			<*> m <| Option(key: "identity", usage: "The code-signing identity to use")
			<*> m <| Option(defaultValue: NSFileManager.defaultManager().currentDirectoryPath, usage: "the directory containing the Carthage project")
	}
}
