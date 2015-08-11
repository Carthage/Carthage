//
//  Build.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-11.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Box
import CarthageKit
import Commandant
import Foundation
import Result
import ReactiveCocoa
import ReactiveTask

public struct BuildCommand: CommandType {
	public let verb = "build"
	public let function = "Build the project's dependencies"

	public func run(mode: CommandMode) -> Result<(), CommandantError<CarthageError>> {
		return producerWithOptions(BuildOptions.evaluate(mode))
			|> flatMap(.Merge) { options in
				return self.buildWithOptions(options)
					|> promoteErrors
			}
			|> waitOnCommand
	}

	/// Builds a project with the given options.
	public func buildWithOptions(options: BuildOptions) -> SignalProducer<(), CarthageError> {
		return openLoggingHandle(options.verbose, "xcodebuild")
			|> flatMap(.Merge) { (stdoutHandle, temporaryURL) -> SignalProducer<(), CarthageError> in
				return openLoggingHandle(options.verbose, "git")
					|> flatMap(.Merge) { (gitFileHandle, gitTemporaryURL) -> SignalProducer<(), CarthageError> in
						let directoryURL = NSURL.fileURLWithPath(options.directoryPath, isDirectory: true)!
						
						var buildProgress = self.buildProjectInDirectoryURL(directoryURL, options: options, gitFileHandle: gitFileHandle)
							|> flatten(.Concat)
						
						let stderrHandle = NSFileHandle.fileHandleWithStandardError()
						
						// Redirect any error-looking messages from stdout, because
						// Xcode doesn't always forward them.
						if !options.verbose {
							let (stdoutProducer, stdoutSink) = SignalProducer<NSData, NoError>.buffer(0)
							let grepTask: BuildSchemeProducer = launchTask(TaskDescription(launchPath: "/usr/bin/grep", arguments: [ "--extended-regexp", "(warning|error|failed):" ], standardInput: stdoutProducer))
								|> on(next: { taskEvent in
									switch taskEvent {
									case let .StandardOutput(data):
										stderrHandle.writeData(data)
										
									default:
										break
									}
								})
								|> catch { _ in .empty }
								|> then(.empty)
								|> promoteErrors(CarthageError.self)
							
							buildProgress = buildProgress
								|> on(next: { taskEvent in
									switch taskEvent {
									case let .StandardOutput(data):
										sendNext(stdoutSink, data)
										
									default:
										break
									}
									}, terminated: {
										sendCompleted(stdoutSink)
									}, interrupted: {
										sendInterrupted(stdoutSink)
								})
							
							buildProgress = SignalProducer(values: [ grepTask, buildProgress ])
								|> flatten(.Merge)
						}
						
						let formatting = options.colorOptions.formatting
						
						return buildProgress
							|> on(started: {
								if let temporaryURL = temporaryURL {
									carthage.println(formatting.bullets + "xcodebuild output can be found in " + formatting.path(string: temporaryURL.path!))
								}
								}, next: { taskEvent in
									switch taskEvent {
									case let .StandardOutput(data):
										stdoutHandle.writeData(data)
										
									case let .StandardError(data):
										stderrHandle.writeData(data)
										
									case let .Success(box):
										let (project, scheme) = box.value
										carthage.println(formatting.bullets + "Building scheme " + formatting.quote(scheme) + " in " + formatting.projectName(string: project.description))
									}
							})
							|> then(.empty)
				}
		}
	}

	/// Builds the project in the given directory, using the given options.
	///
	/// Returns a producer of producers, representing each scheme being built.
	private func buildProjectInDirectoryURL(directoryURL: NSURL, options: BuildOptions, gitFileHandle: NSFileHandle) -> SignalProducer<BuildSchemeProducer, CarthageError> {
		let project = Project(directoryURL: directoryURL)
		let buildProducer = project.loadCombinedCartfile()
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
			|> flatMap(.Merge) { project in
				return project.migrateIfNecessary(options, gitFileHandle: gitFileHandle)
					|> on(next: carthage.println)
					|> then(SignalProducer(value: project))
			}
			|> flatMap(.Merge) { project in
				return project.buildCheckedOutDependenciesWithConfiguration(options.configuration, forPlatform: options.buildPlatform.platform)
			}

		if options.skipCurrent {
			return buildProducer
		} else {
			let currentProducers = buildInDirectory(directoryURL, withConfiguration: options.configuration, platform: options.buildPlatform.platform)
			return buildProducer |> concat(currentProducers)
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
public enum BuildPlatform {
	/// Build for all available platforms.
	case All

	/// Build only for iOS.
	case iOS

	/// Build only for OS X.
	case Mac

	/// Build only for watchOS.
	case watchOS

	/// The `Platform` corresponding to this setting.
	public var platform: Platform? {
		switch self {
		case .All:
			return nil

		case .iOS:
			return .iOS

		case .Mac:
			return .Mac

		case .watchOS:
			return .watchOS
		}
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

		case .watchOS:
			return "watchOS"
		}
	}
}

extension BuildPlatform: ArgumentType {
	public static let name = "platform"

	private static let acceptedStrings: [String: BuildPlatform] = [
		"Mac": .Mac, "macosx": .Mac,
		"iOS": .iOS, "iphoneos": .iOS, "iphonesimulator": .iOS,
		"watchOS": .watchOS, "watchsimulator": .watchOS,
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
