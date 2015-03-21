//
//  Build.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-11.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Commandant
import Foundation
import LlamaKit
import ReactiveCocoa

public struct BuildCommand: CommandType {
	public let verb = "build"
	public let function = "Build the project's dependencies"

	public func run(mode: CommandMode) -> Result<(), CommandantError<CarthageError>> {
		return producerWithOptions(BuildOptions.evaluate(mode))
			|> joinMap(.Merge) { options in
				return self.buildWithOptions(options)
					|> promoteErrors
			}
			|> waitOnCommand
	}

	/// Builds a project with the given options.
	public func buildWithOptions(options: BuildOptions) -> SignalProducer<(), CarthageError> {
		return self.createLoggingSink(options)
			|> joinMap(.Merge) { (stdoutSink, temporaryURL) -> SignalProducer<(), CarthageError> in
				let directoryURL = NSURL.fileURLWithPath(options.directoryPath, isDirectory: true)!

				let (stdoutSignal, schemeSignals) = self.buildProjectInDirectoryURL(directoryURL, options: options)
				stdoutSignal.observe(stdoutSink)

				let formatting = options.colorOptions.formatting

				return schemeSignals
					|> join(.Concat)
					|> on(started: {
						if let temporaryURL = temporaryURL {
							carthage.println(formatting.bullets + "xcodebuild output can be found in " + formatting.path(string: temporaryURL.path!))
						}
					}, next: { (project, scheme) in
						carthage.println(formatting.bullets + "Building scheme " + formatting.quote(scheme) + " in " + formatting.projectName(string: project.description))
					})
					|> then(.empty)
			}
	}

	/// Builds the project in the given directory, using the given options.
	///
	/// Returns a hot signal of `stdout` from `xcodebuild`, and a cold signal of
	/// cold signals representing each scheme being built.
	private func buildProjectInDirectoryURL(directoryURL: NSURL, options: BuildOptions) -> (Signal<NSData, NoError>, SignalProducer<BuildSchemeProducer, CarthageError>) {
		let (stdoutSignal, stdoutSink) = Signal<NSData, NoError>.pipe()
		let project = Project(directoryURL: directoryURL)

		var buildProducer = project.loadCombinedCartfile()
			|> map { _ in project }
			|> catch { error in
				if options.skipCurrent {
					return SignalProducer(error: error)
				} else {
					// Ignore Cartfile loading failures. Assume the user just
					// wants to build the enclosing project.
					return .empty
				}
			}
			|> joinMap(.Merge) { project in
				return project.migrateIfNecessary(options.colorOptions)
					|> on(next: carthage.println)
					|> then(SignalProducer(value: project))
			}
			|> joinMap(.Merge) { (project: Project) -> SignalProducer<BuildSchemeProducer, CarthageError> in
				let (dependenciesOutput, dependencies) = project.buildCheckedOutDependenciesWithConfiguration(options.configuration, forPlatform: options.buildPlatform.platform)
				dependenciesOutput.observe(stdoutSink)

				return dependencies
			}

		if !options.skipCurrent {
			let (currentOutput, currentProducers) = buildInDirectory(directoryURL, withConfiguration: options.configuration, platform: options.buildPlatform.platform)
			currentOutput.observe(stdoutSink)

			buildProducer = buildProducer |> concat(currentProducers)
		}

		return (stdoutSignal, buildProducer)
	}

	/// Creates a sink for logging, returning the sink and the URL to any
	/// temporary file on disk.
	private func createLoggingSink(options: BuildOptions) -> SignalProducer<(FileSink<NSData>, NSURL?), CarthageError> {
		if options.verbose {
			let out: (FileSink<NSData>, NSURL?) = (FileSink.standardOutputSink(), nil)
			return SignalProducer(value: out)
		} else {
			return FileSink.openTemporaryFile()
				|> map { sink, URL in (sink, .Some(URL)) }
				|> mapError { error in
					let temporaryDirectoryURL = NSURL.fileURLWithPath(NSTemporaryDirectory(), isDirectory: true)!
					return .WriteFailed(temporaryDirectoryURL, error)
				}
		}
	}
}

public struct BuildOptions: OptionsType {
	public let configuration: String
	public let buildPlatform: BuildPlatform
	public let skipCurrent: Bool
	public let colorOptions: ColorOptions
	public let verbose: Bool
	public let directoryPath: String

	public static func create(configuration: String)(buildPlatform: BuildPlatform)(skipCurrent: Bool)(colorOptions: ColorOptions)(verbose: Bool)(directoryPath: String) -> BuildOptions {
		return self(configuration: configuration, buildPlatform: buildPlatform, skipCurrent: skipCurrent, colorOptions: colorOptions, verbose: verbose, directoryPath: directoryPath)
	}

	public static func evaluate(m: CommandMode) -> Result<BuildOptions, CommandantError<CarthageError>> {
		return create
			<*> m <| Option(key: "configuration", defaultValue: "Release", usage: "the Xcode configuration to build")
			<*> m <| Option(key: "platform", defaultValue: .All, usage: "the platform to build for (one of ‘all’, ‘Mac’, or ‘iOS’)")
			<*> m <| Option(key: "skip-current", defaultValue: true, usage: "don't skip building the Carthage project (in addition to its dependencies)")
			<*> ColorOptions.evaluate(m)
			<*> m <| Option(key: "verbose", defaultValue: false, usage: "print xcodebuild output inline")
			<*> m <| Option(defaultValue: NSFileManager.defaultManager().currentDirectoryPath, usage: "the directory containing the Carthage project")
	}
}

/// Represents the user’s chosen platform to build for.
public enum BuildPlatform: Equatable {
	/// Build for all available platforms.
	case All

	/// Build only for iOS.
	case iOS

	/// Build only for OS X.
	case Mac

	/// The `Platform` corresponding to this setting.
	public var platform: Platform? {
		switch self {
		case .All:
			return nil

		case .iOS:
			return .iOS

		case .Mac:
			return .Mac
		}
	}
}

public func == (lhs: BuildPlatform, rhs: BuildPlatform) -> Bool {
	switch (lhs, rhs) {
	case (.All, .All):
		return true

	case (.iOS, .iOS):
		return true

	case (.Mac, .Mac):
		return true

	default:
		return false
	}
}

extension BuildPlatform: Printable {
	public var description: String {
		switch self {
		case .All:
			return "all"

		case .iOS:
			return "iOS"

		case .Mac:
			return "Mac"
		}
	}
}

extension BuildPlatform: ArgumentType {
	public static let name = "platform"

	private static let acceptedStrings: [String: BuildPlatform] = [
		"Mac": .Mac, "macosx": .Mac,
		"iOS": .iOS, "iphoneos": .iOS, "iphonesimulator": .iOS,
		"all": .All
	]

	public static func fromString(string: String) -> BuildPlatform? {
		for (key, platform) in acceptedStrings {
			if string.caseInsensitiveCompare(key) == NSComparisonResult.OrderedSame {
				return platform
			}
		}
		
		return nil
	}
}
