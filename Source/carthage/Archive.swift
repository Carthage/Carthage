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
		public let outputPath: String?
		public let directoryPath: String
		public let colorOptions: ColorOptions
		public let frameworkNames: [String]

		static func create(outputPath: String?) -> String -> ColorOptions -> [String] -> Options {
			return { directoryPath in { colorOptions in { frameworkNames in
				return self.init(outputPath: outputPath, directoryPath: directoryPath, colorOptions: colorOptions, frameworkNames: frameworkNames)
			} } }
		}

		public static func evaluate(m: CommandMode) -> Result<Options, CommandantError<CarthageError>> {
			return create
				<*> m <| Option(key: "output", defaultValue: nil, usage: "the path at which to create the zip file (or blank to infer it from the first one of the framework names)")
				<*> m <| Option(key: "project-directory", defaultValue: NSFileManager.defaultManager().currentDirectoryPath, usage: "the directory containing the Carthage project")
				<*> ColorOptions.evaluate(m)
				<*> m <| Argument(defaultValue: [], usage: "the names of the built frameworks to archive without any extension (or blank to pick up the frameworks in the current project built by `--no-skip-current`)")
		}
	}
	
	public let verb = "archive"
	public let function = "Archives built frameworks into a zip that Carthage can use"

	public func run(options: Options) -> Result<(), CarthageError> {
		let formatting = options.colorOptions.formatting

		let frameworks: SignalProducer<[String], CarthageError>
		if !options.frameworkNames.isEmpty {
			frameworks = .init(value: options.frameworkNames.map {
				return ($0 as NSString).stringByAppendingPathExtension("framework")!
			})
		} else {
			let directoryURL = NSURL.fileURLWithPath(options.directoryPath, isDirectory: true)
			frameworks = buildableSchemesInDirectory(directoryURL, withConfiguration: "Release", forPlatforms: [])
				.collect()
				.flatMap(.Merge) { projects in
					return schemesInProjects(projects)
						.flatMap(.Merge) { (schemes: [(String, ProjectLocator)]) -> SignalProducer<(String, ProjectLocator), CarthageError> in
							if !schemes.isEmpty {
								return .init(values: schemes)
							} else {
								return .init(error: .NoSharedFrameworkSchemes(.Git(GitURL(directoryURL.path!)), []))
							}
						}
				}
				.flatMap(.Merge) { scheme, project -> SignalProducer<BuildSettings, CarthageError> in
					let buildArguments = BuildArguments(project: project, scheme: scheme, configuration: "Release")
					return BuildSettings.loadWithArguments(buildArguments)
				}
				.flatMap(.Concat) { settings -> SignalProducer<String, CarthageError> in
					if let wrapperName = settings.wrapperName.value where settings.productType.value == .Framework {
						return .init(value: wrapperName)
					} else {
						return .empty
					}
				}
				.collect()
				.map { Array(Set($0)).sort() }
		}

		return frameworks.flatMap(.Merge) { frameworks -> SignalProducer<(), CarthageError> in
			return SignalProducer(values: Platform.supportedPlatforms)
				.flatMap(.Merge) { platform -> SignalProducer<String, CarthageError> in
					return SignalProducer(values: frameworks).map { framework in
						return (platform.relativePath as NSString).stringByAppendingPathComponent(framework)
					}
				}
				.map { relativePath -> (relativePath: String, absolutePath: String) in
					let absolutePath = (options.directoryPath as NSString).stringByAppendingPathComponent(relativePath)
					return (relativePath, absolutePath)
				}
				.filter { filePath in NSFileManager.defaultManager().fileExistsAtPath(filePath.absolutePath) }
				.flatMap(.Merge) { framework -> SignalProducer<String, CarthageError> in
					let dSYM = (framework.relativePath as NSString).stringByAppendingPathExtension("dSYM")!
					let bcsymbolmapsProducer = BCSymbolMapsForFramework(NSURL(fileURLWithPath: framework.absolutePath))
						// generate relative paths for the bcsymbolmaps so they print nicely
						.map { url in ((framework.relativePath as NSString).stringByDeletingLastPathComponent as NSString).stringByAppendingPathComponent(url.lastPathComponent!) }
					let extraFilesProducer = SignalProducer(value: dSYM)
						.concat(bcsymbolmapsProducer)
						.filter { relativePath in NSFileManager.defaultManager().fileExistsAtPath(framework.absolutePath) }
					return SignalProducer(value: framework.relativePath)
						.concat(extraFilesProducer)
				}
				.on(next: { path in
					carthage.println(formatting.bullets + "Found " + formatting.path(string: path))
				})
				.collect()
				.flatMap(.Merge) { paths -> SignalProducer<(), CarthageError> in
					
					let foundFrameworks = paths
						.lazy
						.map { ($0 as NSString).lastPathComponent }
						.filter { $0.hasSuffix(".framework") }
					
					if Set(foundFrameworks) != Set(frameworks) {
						let error = CarthageError.InvalidArgument(description: "Could not find any copies of \(frameworks.joinWithSeparator(", ")). Make sure you're in the project's root and that the frameworks have already been built using 'carthage build --no-skip-current'.")
						return SignalProducer(error: error)
					}

					let outputPath = outputPathWithOptions(options, frameworks: frameworks)
					let outputURL = NSURL(fileURLWithPath: outputPath, isDirectory: false)

					if let directory = outputURL.URLByDeletingLastPathComponent {
						_ = try? NSFileManager.defaultManager().createDirectoryAtURL(directory, withIntermediateDirectories: true, attributes: nil)
					}
					
					return zipIntoArchive(outputURL, workingDirectory: options.directoryPath, inputPaths: paths).on(completed: {
						carthage.println(formatting.bullets + "Created " + formatting.path(string: outputPath))
					})
				}
		}
		.waitOnCommand()
	}
}

/// Returns an appropriate output file path for the resulting zip file using
/// the given option and frameworks.
private func outputPathWithOptions(options: ArchiveCommand.Options, frameworks: [String]) -> String {
	let defaultOutputPath = "\(frameworks.first!).zip"

	return options.outputPath.map { path -> String in
		if path.hasSuffix("/") {
			// The given path should be a directory.
			return path + defaultOutputPath
		}

		var isDirectory: ObjCBool = false
		if NSFileManager.defaultManager().fileExistsAtPath(path, isDirectory: &isDirectory) && isDirectory {
			// If the given path is an existing directory, output a zip file
			// into that directory.
			return (path as NSString).stringByAppendingPathComponent(defaultOutputPath)
		} else {
			// Use the given path as the final output.
			return path
		}
	} ?? defaultOutputPath
}
