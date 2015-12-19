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
	public struct Options: OptionsType {
		public let frameworkName: String
		public let outputPath: String
		public let colorOptions: ColorOptions

		static func create(outputPath: String) -> ColorOptions -> String -> Options {
			return { colorOptions in { frameworkName in
				return self.init(frameworkName: frameworkName, outputPath: outputPath, colorOptions: colorOptions)
			} }
		}

		public static func evaluate(m: CommandMode) -> Result<Options, CommandantError<CarthageError>> {
			return create
				<*> m <| Option(key: "output", defaultValue: "", usage: "the path at which to create the zip file (or blank to infer it from the framework name)")
				<*> ColorOptions.evaluate(m)
				<*> m <| Argument(usage: "the name of the built framework to archive (without any extension)")
		}
	}
	
	public let verb = "archive"
	public let function = "Archives a built framework into a zip that Carthage can use"

	public func run(options: Options) -> Result<(), CarthageError> {
		let formatting = options.colorOptions.formatting

		return SignalProducer(values: Platform.supportedPlatforms)
			.map { platform -> String in
				let frameworkName = (platform.relativePath as NSString).stringByAppendingPathComponent(options.frameworkName)
				return (frameworkName as NSString).stringByAppendingPathExtension("framework")!
			}
			.filter { relativePath in NSFileManager.defaultManager().fileExistsAtPath(relativePath) }
			.flatMap(.Merge) { framework -> SignalProducer<String, CarthageError> in
				let dSYM = (framework as NSString).stringByAppendingPathExtension("dSYM")!
				let bcsymbolmapsProducer = BCSymbolMapsForFramework(NSURL(fileURLWithPath: framework))
					// generate relative paths for the bcsymbolmaps so they print nicely
					.map { url in ((framework as NSString).stringByDeletingLastPathComponent as NSString).stringByAppendingPathComponent(url.lastPathComponent!) }
				let extraFilesProducer = SignalProducer(value: dSYM)
					.concat(bcsymbolmapsProducer)
					.filter { relativePath in NSFileManager.defaultManager().fileExistsAtPath(relativePath) }
				return SignalProducer(value: framework)
					.concat(extraFilesProducer)
			}
			.on(next: { path in
				carthage.println(formatting.bullets + "Found " + formatting.path(string: path))
			})
			.collect()
			.flatMap(.Merge) { paths -> SignalProducer<(), CarthageError> in
				if paths.isEmpty {
					return SignalProducer(error: CarthageError.InvalidArgument(description: "Could not find any copies of \(options.frameworkName).framework. Make sure you're in the project’s root and that the framework has already been built using 'carthage build --no-skip-current'."))
				}

				let outputPath = (options.outputPath.isEmpty ? "\(options.frameworkName).framework.zip" : options.outputPath)
				let outputURL = NSURL(fileURLWithPath: outputPath, isDirectory: false)

				return zipIntoArchive(outputURL, paths).on(completed: {
					carthage.println(formatting.bullets + "Created " + formatting.path(string: outputPath))
				})
			}
			.waitOnCommand()
	}
}
