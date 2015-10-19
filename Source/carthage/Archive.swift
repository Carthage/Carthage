//
//  Archive.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2015-02-13.
//  Copyright (c) 2015 Carthage. All rights reserved.
//

import CarthageKit
import Commandant
import Foundation
import Result
import ReactiveCocoa

public struct ArchiveCommand: CommandType {
	public let verb = "archive"
	public let function = "Archives a built framework into a zip that Carthage can use"

	public func run(mode: CommandMode) -> Result<(), CommandantError<CarthageError>> {
		return producerWithOptions(ArchiveOptions.evaluate(mode))
			|> flatMap(.Merge) { options -> SignalProducer<(), CommandError> in
				let formatting = options.colorOptions.formatting

				return SignalProducer(values: Platform.supportedPlatforms)
					|> map { platform in
						return platform.relativePath.stringByAppendingPathComponent(options.frameworkName).stringByAppendingPathExtension("framework")!
					}
					|> filter { relativePath in NSFileManager.defaultManager().fileExistsAtPath(relativePath) }
					|> flatMap(.Merge) { framework in
						let dSYM = framework.stringByAppendingPathExtension("dSYM")!
						let bcsymbolmapsProducer = BCSymbolMapsForFramework(NSURL(fileURLWithPath: framework)!)
							// generate relative paths for the bcsymbolmaps so they print nicely
							|> map { url in framework.stringByDeletingLastPathComponent.stringByAppendingPathComponent(url.lastPathComponent!) }
						let extraFilesProducer = SignalProducer(value: dSYM)
							|> concat(bcsymbolmapsProducer)
							|> filter { relativePath in NSFileManager.defaultManager().fileExistsAtPath(relativePath) }
						return SignalProducer(value: framework)
							|> concat(extraFilesProducer)
					}
					|> on(next: { path in
						carthage.println(formatting.bullets + "Found " + formatting.path(string: path))
					})
					|> collect
					|> flatMap(.Merge) { paths -> SignalProducer<(), CarthageError> in
						if paths.isEmpty {
							return SignalProducer(error: CarthageError.InvalidArgument(description: "Could not find any copies of \(options.frameworkName).framework. Make sure you're in the project’s root and that the framework has already been built using 'carthage build --no-skip-current'."))
						}

						let outputPath = (options.outputPath.isEmpty ? "\(options.frameworkName).framework.zip" : options.outputPath)
						let outputURL = NSURL(fileURLWithPath: outputPath, isDirectory: false)!

						return zipIntoArchive(outputURL, paths) |> on(completed: {
							carthage.println(formatting.bullets + "Created " + formatting.path(string: outputPath))
						})
					}
					|> promoteErrors
			}
			|> waitOnCommand
	}
}

private struct ArchiveOptions: OptionsType {
	let frameworkName: String
	let outputPath: String
	let colorOptions: ColorOptions

	static func create(outputPath: String)(colorOptions: ColorOptions)(frameworkName: String) -> ArchiveOptions {
		return self(frameworkName: frameworkName, outputPath: outputPath, colorOptions: colorOptions)
	}

	static func evaluate(m: CommandMode) -> Result<ArchiveOptions, CommandantError<CarthageError>> {
		return create
			<*> m <| Option(key: "output", defaultValue: "", usage: "the path at which to create the zip file (or blank to infer it from the framework name)")
			<*> ColorOptions.evaluate(m)
			<*> m <| Option(usage: "the name of the built framework to archive (without any extension)")
	}
}
