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
import Result
import ReactiveCocoa
import ReactiveTask

public struct BuildCommand: CommandType {
	public struct Options: OptionsType {
		public let configuration: String
		public let buildPlatform: BuildPlatform
		public let skipCurrent: Bool
		public let colorOptions: ColorOptions
		public let verbose: Bool
		public let directoryPath: String
		public let dependenciesToBuild: [String]?

		public static func create(configuration: String) -> BuildPlatform -> Bool -> ColorOptions -> Bool -> String -> [String] -> Options {
			return { buildPlatform in { skipCurrent in { colorOptions in { verbose in { directoryPath in { dependenciesToBuild in
				let dependenciesToBuild: [String]? = dependenciesToBuild.isEmpty ? nil : dependenciesToBuild
				return self.init(configuration: configuration, buildPlatform: buildPlatform, skipCurrent: skipCurrent, colorOptions: colorOptions, verbose: verbose, directoryPath: directoryPath, dependenciesToBuild: dependenciesToBuild)
			} } } } } }
		}

		public static func evaluate(m: CommandMode) -> Result<Options, CommandantError<CarthageError>> {
			return create
				<*> m <| Option(key: "configuration", defaultValue: "Release", usage: "the Xcode configuration to build")
				<*> m <| Option(key: "platform", defaultValue: .All, usage: "the platforms to build for (one of ‘all’, ‘Mac’, ‘iOS’, ‘watchOS’, 'tvOS', or comma-separated values of the formers except for ‘all’)")
				<*> m <| Option(key: "skip-current", defaultValue: true, usage: "don't skip building the Carthage project (in addition to its dependencies)")
				<*> ColorOptions.evaluate(m)
				<*> m <| Option(key: "verbose", defaultValue: false, usage: "print xcodebuild output inline")
				<*> m <| Option(key: "project-directory", defaultValue: NSFileManager.defaultManager().currentDirectoryPath, usage: "the directory containing the Carthage project")
				<*> m <| Argument(defaultValue: [], usage: "the dependency names to build")
		}
	}
	
	public let verb = "build"
	public let function = "Build the project's dependencies"

	public func run(options: Options) -> Result<(), CarthageError> {
		return self.buildWithOptions(options)
			.waitOnCommand()
	}

	/// Builds a project with the given options.
	public func buildWithOptions(options: Options) -> SignalProducer<(), CarthageError> {
		return self.openLoggingHandle(options)
			.flatMap(.Merge) { (stdoutHandle, temporaryURL) -> SignalProducer<(), CarthageError> in
				let directoryURL = NSURL.fileURLWithPath(options.directoryPath, isDirectory: true)

				var buildProgress = self.buildProjectInDirectoryURL(directoryURL, options: options)
					.flatten(.Concat)

				let stderrHandle = NSFileHandle.fileHandleWithStandardError()

				// Redirect any error-looking messages from stdout, because
				// Xcode doesn't always forward them.
				if !options.verbose {
					let (stdoutProducer, stdoutObserver) = SignalProducer<NSData, NoError>.buffer(0)
					let grepTask: BuildSchemeProducer = launchTask(Task("/usr/bin/grep", arguments: [ "--extended-regexp", "(warning|error|failed):" ]), standardInput: stdoutProducer)
						.on(next: { taskEvent in
							switch taskEvent {
							case let .StandardOutput(data):
								stderrHandle.writeData(data)

							default:
								break
							}
						})
						.flatMapError { _ in .empty }
						.then(SignalProducer<TaskEvent<(ProjectLocator, String)>, NoError>.empty)
						.promoteErrors(CarthageError.self)

					buildProgress = buildProgress
						.on(next: { taskEvent in
							switch taskEvent {
							case let .StandardOutput(data):
								stdoutObserver.sendNext(data)

							default:
								break
							}
						}, terminated: {
							stdoutObserver.sendCompleted()
						}, interrupted: {
							stdoutObserver.sendInterrupted()
						})

					buildProgress = SignalProducer(values: [ grepTask, buildProgress ])
						.flatten(.Merge)
				}

				let formatting = options.colorOptions.formatting

				return buildProgress
					.on(started: {
						if let path = temporaryURL?.path {
							carthage.println(formatting.bullets + "xcodebuild output can be found in " + formatting.path(string: path))
						}
					}, next: { taskEvent in
						switch taskEvent {
						case let .Launch(task):
							stdoutHandle.writeData(task.description.dataUsingEncoding(NSUTF8StringEncoding)!)

						case let .StandardOutput(data):
							stdoutHandle.writeData(data)

						case let .StandardError(data):
							stderrHandle.writeData(data)

						case let .Success(project, scheme):
							carthage.println(formatting.bullets + "Building scheme " + formatting.quote(scheme) + " in " + formatting.projectName(string: project.description))
						}
					})
					.then(.empty)
			}
	}

	/// Builds the project in the given directory, using the given options.
	///
	/// Returns a producer of producers, representing each scheme being built.
	private func buildProjectInDirectoryURL(directoryURL: NSURL, options: Options) -> SignalProducer<BuildSchemeProducer, CarthageError> {
		let project = Project(directoryURL: directoryURL)

		var eventSink = ProjectEventSink(colorOptions: options.colorOptions)
		project.projectEvents.observeNext { eventSink.put($0) }

		let buildProducer = project.loadCombinedCartfile()
			.map { _ in project }
			.flatMapError { error in
				if options.skipCurrent {
					return SignalProducer(error: error)
				} else {
					// Ignore Cartfile loading failures. Assume the user just
					// wants to build the enclosing project.
					return .empty
				}
			}
			.flatMap(.Merge) { project in
				return project.buildCheckedOutDependenciesWithConfiguration(options.configuration, dependenciesToBuild: options.dependenciesToBuild, forPlatforms: options.buildPlatform.platforms)
			}

		if options.skipCurrent {
			return buildProducer
		} else {
			let currentProducers = buildInDirectory(directoryURL, withConfiguration: options.configuration, platforms: options.buildPlatform.platforms)
				.flatMapError { error -> SignalProducer<BuildSchemeProducer, CarthageError> in
					switch error {
					case let .NoSharedFrameworkSchemes(project, _):
						// Log that building the current project is being skipped.
						eventSink.put(.SkippedBuilding(project, error.description))
						return .empty

					default:
						return SignalProducer(error: error)
					}
				}
			return buildProducer.concat(currentProducers)
		}
	}

	/// Opens a temporary file on disk, returning a handle and the URL to the
	/// file.
	private func openTemporaryFile() -> SignalProducer<(NSFileHandle, NSURL), NSError> {
		return SignalProducer.attempt {
			var temporaryDirectoryTemplate: [CChar] = (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent("carthage-xcodebuild.XXXXXX.log").nulTerminatedUTF8.map { CChar($0) }
			let logFD = temporaryDirectoryTemplate.withUnsafeMutableBufferPointer { (inout template: UnsafeMutableBufferPointer<CChar>) -> Int32 in
				return mkstemps(template.baseAddress, 4)
			}

			if logFD < 0 {
				return .Failure(NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil))
			}

			let temporaryPath = temporaryDirectoryTemplate.withUnsafeBufferPointer { (ptr: UnsafeBufferPointer<CChar>) -> String in
				return String.fromCString(ptr.baseAddress)!
			}

			let handle = NSFileHandle(fileDescriptor: logFD, closeOnDealloc: true)
			let fileURL = NSURL.fileURLWithPath(temporaryPath, isDirectory: false)
			return .Success((handle, fileURL))
		}
	}

	/// Opens a file handle for logging, returning the handle and the URL to any
	/// temporary file on disk.
	private func openLoggingHandle(options: Options) -> SignalProducer<(NSFileHandle, NSURL?), CarthageError> {
		if options.verbose {
			let out: (NSFileHandle, NSURL?) = (NSFileHandle.fileHandleWithStandardOutput(), nil)
			return SignalProducer(value: out)
		} else {
			return openTemporaryFile()
				.map { handle, URL in (handle, .Some(URL)) }
				.mapError { error in
					let temporaryDirectoryURL = NSURL.fileURLWithPath(NSTemporaryDirectory(), isDirectory: true)
					return .WriteFailed(temporaryDirectoryURL, error)
				}
		}
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

	/// Build only for watchOS.
	case watchOS

	/// Build only for tvOS.
	case tvOS

	/// Build for multiple platforms within the list.
	case Multiple([BuildPlatform])

	/// The set of `Platform` corresponding to this setting.
	public var platforms: Set<Platform> {
		switch self {
		case .All:
			return []

		case .iOS:
			return [ .iOS ]

		case .Mac:
			return [ .Mac ]

		case .watchOS:
			return [ .watchOS ]

		case .tvOS:
			return [ .tvOS ]

		case let .Multiple(buildPlatforms):
			return buildPlatforms.reduce([]) { (set, buildPlatform) in
				return set.union(buildPlatform.platforms)
			}
		}
	}
}

public func ==(lhs: BuildPlatform, rhs: BuildPlatform) -> Bool {
	switch (lhs, rhs) {
	case let (.Multiple(left), .Multiple(right)):
		return left == right

	case (.All, .All), (.iOS, .iOS), (.Mac, .Mac), (.watchOS, .watchOS), (.tvOS, .tvOS):
		return true

	case _:
		return false
	}
}

extension BuildPlatform: CustomStringConvertible {
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

		case .tvOS:
			return "tvOS"

		case let .Multiple(buildPlatforms):
			return buildPlatforms.map { $0.description }.joinWithSeparator(", ")
		}
	}
}

extension BuildPlatform: ArgumentType {
	public static let name = "platform"

	private static let acceptedStrings: [String: BuildPlatform] = [
		"Mac": .Mac, "OSX": .Mac, "macosx": .Mac,
		"iOS": .iOS, "iphoneos": .iOS, "iphonesimulator": .iOS,
		"watchOS": .watchOS, "watchsimulator": .watchOS,
		"tvOS": .tvOS, "tvsimulator": .tvOS,
		"all": .All
	]

	public static func fromString(string: String) -> BuildPlatform? {
		let tokens = string.split()

		let findBuildPlatform: String -> BuildPlatform? = { string in
			return self.acceptedStrings.lazy
				.filter { key, _ in string.caseInsensitiveCompare(key) == .OrderedSame }
				.map { _, platform in platform }
				.first
		}

		switch tokens.count {
		case 0:
			return nil

		case 1:
			return findBuildPlatform(tokens[0])

		default:
			var buildPlatforms = [BuildPlatform]()
			for token in tokens {
				if let found = findBuildPlatform(token) where found != .All {
					buildPlatforms.append(found)
				} else {
					// Reject if an invalid value is included in the comma-
					// separated string.
					return nil
				}
			}
			return .Multiple(buildPlatforms)
		}
	}
}
