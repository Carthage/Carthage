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
		public let outputPath: String
		public let directoryPath: String
		public let colorOptions: ColorOptions
		public let frameworkNames: [String]

		static func create(outputPath: String) -> String -> ColorOptions -> [String] -> Options {
			return { directoryPath in { colorOptions in { frameworkNames in
				return self.init(outputPath: outputPath, directoryPath: directoryPath, colorOptions: colorOptions, frameworkNames: frameworkNames)
			} } }
		}

		public static func evaluate(m: CommandMode) -> Result<Options, CommandantError<CarthageError>> {
			return create
				<*> m <| Option(key: "output", defaultValue: "", usage: "the path at which to create the zip file (or blank to infer it from the first one of the framework names)")
				<*> m <| Option(key: "project-directory", defaultValue: NSFileManager.defaultManager().currentDirectoryPath, usage: "the directory containing the Carthage project")
				<*> ColorOptions.evaluate(m)
				<*> m <| Argument(defaultValue: [], usage: "the names of the built frameworks to archive without any extension (or blank to pick up the frameworks in the current project built by `--no-skip-current`)")
		}
	}
	
	public let verb = "archive"
	public let function = "Archives built frameworks into a zip that Carthage can use"

	public func run(options: Options) -> Result<(), CarthageError> {
		let formatting = options.colorOptions.formatting

		let frameworks: [String]
		if !options.frameworkNames.isEmpty {
			frameworks = options.frameworkNames.map {
				return ($0 as NSString).stringByAppendingPathExtension("framework")!
			}
		} else {
			let directoryURL = NSURL.fileURLWithPath(options.directoryPath, isDirectory: true)
			frameworks = locateProjectsInDirectory(directoryURL)
				.flatMap(.Concat) { project in
					return schemesInProject(project)
						.flatMapError { error in
							if case .NoSharedSchemes = error {
								return .empty
							} else {
								return .init(error: error)
							}
						}
						.flatMap(.Merge) { scheme -> SignalProducer<BuildSettings, CarthageError> in
							let buildArguments = BuildArguments(project: project, scheme: scheme, configuration: "Release")
							return BuildSettings.loadWithArguments(buildArguments)
						}
						.flatMap(.Concat) { settings -> SignalProducer<String, CarthageError> in
							if let wrapperName = settings.wrapperName.value {
								return .init(value: wrapperName)
							} else {
								return .empty
							}
						}
				}
				.skipRepeats()
				.collect()
				.map { $0.sort() }
				.first()?.value ?? []
		}

		return SignalProducer(values: Platform.supportedPlatforms)
			.flatMap(.Merge) { platform -> SignalProducer<String, CarthageError> in
				return SignalProducer(values: frameworks).map { framework in
					return (platform.relativePath as NSString).stringByAppendingPathComponent(framework)
				}
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
					let error = CarthageError.InvalidArgument(description: "Could not find any copies of \(frameworks.joinWithSeparator(", ")). Make sure you're in the project’s root and that the frameworks have already been built using 'carthage build --no-skip-current'.")
					return SignalProducer(error: error)
				}

				let outputPath = (options.outputPath.isEmpty ? "\(frameworks.first!).zip" : options.outputPath)
				let outputURL = NSURL(fileURLWithPath: outputPath, isDirectory: false)

				return zipIntoArchive(outputURL, paths).on(completed: {
					carthage.println(formatting.bullets + "Created " + formatting.path(string: outputPath))
				})
			}
			.waitOnCommand()
	}
}
