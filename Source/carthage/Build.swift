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

extension BuildOptions: OptionsType {
	public static func create(configuration: String) -> (BuildPlatform) -> (String?) -> (String?) -> (Bool) -> BuildOptions {
		return { buildPlatform in { toolchain in { derivedDataPath in { useBuildProductsCache in
			return self.init(configuration: configuration, platforms: buildPlatform.platforms, toolchain: toolchain, derivedDataPath: derivedDataPath, useBuildProductsCache: useBuildProductsCache)
		} } } }
	}

	public static func evaluate(m: CommandMode) -> Result<BuildOptions, CommandantError<CarthageError>> {
		return evaluate(m, addendum: "")
	}

	public static func evaluate(m: CommandMode, addendum: String) -> Result<BuildOptions, CommandantError<CarthageError>> {
		return create
			<*> m <| Option(key: "configuration", defaultValue: "Release", usage: "the Xcode configuration to build" + addendum)
			<*> m <| Option(key: "platform", defaultValue: .all, usage: "the platforms to build for (one of 'all', 'macOS', 'iOS', 'watchOS', 'tvOS', or comma-separated values of the formers except for 'all')" + addendum)
			<*> m <| Option<String?>(key: "toolchain", defaultValue: nil, usage: "the toolchain to build with")
			<*> m <| Option<String?>(key: "derived-data", defaultValue: nil, usage: "path to the custom derived data folder")
			<*> m <| Option(key: "use-build-products-cache", defaultValue: false, usage: "build products should be cached instead of building")
	}
}

public struct BuildCommand: CommandType {
	public struct Options: OptionsType {
		public let buildOptions: BuildOptions
		public let skipCurrent: Bool
		public let colorOptions: ColorOptions
		public let isVerbose: Bool
		public let directoryPath: String
		public let dependenciesToBuild: [String]?

		public static func create(buildOptions: BuildOptions) -> (Bool) -> (ColorOptions) -> (Bool) -> (String) -> ([String]) -> Options {
			return { skipCurrent in { colorOptions in { isVerbose in { directoryPath in { dependenciesToBuild in
				let dependenciesToBuild: [String]? = dependenciesToBuild.isEmpty ? nil : dependenciesToBuild
				return self.init(buildOptions: buildOptions, skipCurrent: skipCurrent, colorOptions: colorOptions, isVerbose: isVerbose, directoryPath: directoryPath, dependenciesToBuild: dependenciesToBuild)
			} } } } }
		}

		public static func evaluate(m: CommandMode) -> Result<Options, CommandantError<CarthageError>> {
			return create
				<*> BuildOptions.evaluate(m)
				<*> m <| Option(key: "skip-current", defaultValue: true, usage: "don't skip building the Carthage project (in addition to its dependencies)")
				<*> ColorOptions.evaluate(m)
				<*> m <| Option(key: "verbose", defaultValue: false, usage: "print xcodebuild output inline")
				<*> m <| Option(key: "project-directory", defaultValue: FileManager.`default`.currentDirectoryPath, usage: "the directory containing the Carthage project")
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
			.flatMap(.merge) { (stdoutHandle, temporaryURL) -> SignalProducer<(), CarthageError> in
				let directoryURL = URL(fileURLWithPath: options.directoryPath, isDirectory: true)

				var buildProgress = self.buildProjectInDirectoryURL(directoryURL, options: options)
					.flatten(.concat)

				let stderrHandle = FileHandle.standardError

				// Redirect any error-looking messages from stdout, because
				// Xcode doesn't always forward them.
				if !options.isVerbose {
					let (_stdoutSignal, stdoutObserver) = Signal<Data, NoError>.pipe()
					let stdoutProducer = SignalProducer(signal: _stdoutSignal)
					let grepTask: BuildSchemeProducer = Task("/usr/bin/grep", arguments: [ "--extended-regexp", "(warning|error|failed):" ]).launch(standardInput: stdoutProducer)
						.on(next: { taskEvent in
							switch taskEvent {
							case let .StandardOutput(data):
								stderrHandle.write(data)

							default:
								break
							}
						})
						.flatMapError { _ in .empty }
						.then(.empty)

					buildProgress = buildProgress
						.on(next: { taskEvent in
							switch taskEvent {
							case let .StandardOutput(data):
								stdoutObserver.send(value: data)

							default:
								break
							}
						}, terminated: {
							stdoutObserver.sendCompleted()
						}, interrupted: {
							stdoutObserver.sendInterrupted()
						})

					buildProgress = SignalProducer<BuildSchemeProducer, CarthageError>(values: [ grepTask, buildProgress ])
						.flatten(.merge)
				}

				let formatting = options.colorOptions.formatting

				return buildProgress
					.on(started: {
						if let path = temporaryURL?.carthage_path {
							carthage.println(formatting.bullets + "xcodebuild output can be found in " + formatting.path(string: path))
						}
					}, next: { taskEvent in
						switch taskEvent {
						case let .Launch(task):
							stdoutHandle.write(task.description.dataUsingEncoding(NSUTF8StringEncoding)!)

						case let .StandardOutput(data):
							stdoutHandle.write(data)

						case let .StandardError(data):
							stderrHandle.write(data)

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
	private func buildProjectInDirectoryURL(directoryURL: URL, options: Options) -> SignalProducer<BuildSchemeProducer, CarthageError> {
		let project = Project(directoryURL: directoryURL)

		var eventSink = ProjectEventSink(colorOptions: options.colorOptions)
		project.projectEvents.observeValues { eventSink.put($0) }

		let buildProducer = project.loadCombinedCartfile()
			.map { _ in project }
			.flatMapError { error -> SignalProducer<Project, CarthageError> in
				if options.skipCurrent {
					return SignalProducer(error: error)
				} else {
					// Ignore Cartfile loading failures. Assume the user just
					// wants to build the enclosing project.
					return .empty
				}
			}
			.flatMap(.merge) { project in
				return project.buildCheckedOutDependenciesWithOptions(options.buildOptions, dependenciesToBuild: options.dependenciesToBuild)
			}

		if options.skipCurrent {
			return buildProducer
		} else {
			let currentProducers = buildInDirectory(directoryURL, withOptions: options.buildOptions, cachedBinariesPath: nil)
				.flatMapError { error -> SignalProducer<BuildSchemeProducer, CarthageError> in
					switch error {
					case let .noSharedFrameworkSchemes(project, _):
						// Log that building the current project is being skipped.
						eventSink.put(.skippedBuilding(project, error.description))
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
	private func openTemporaryFile() -> SignalProducer<(FileHandle, URL), NSError> {
		return SignalProducer.attempt {
			var temporaryDirectoryTemplate: [CChar] = (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent("carthage-xcodebuild.XXXXXX.log").nulTerminatedUTF8.map { CChar($0) }
			let logFD = temporaryDirectoryTemplate.withUnsafeMutableBufferPointer { (inout template: UnsafeMutableBufferPointer<CChar>) -> Int32 in
				return mkstemps(template.baseAddress, 4)
			}

			if logFD < 0 {
				return .failure(NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil))
			}

			let temporaryPath = temporaryDirectoryTemplate.withUnsafeBufferPointer { (ptr: UnsafeBufferPointer<CChar>) -> String in
				return String.fromCString(ptr.baseAddress)!
			}

			let handle = FileHandle(fileDescriptor: logFD, closeOnDealloc: true)
			let fileURL = URL(fileURLWithPath: temporaryPath, isDirectory: false)
			return .success((handle, fileURL))
		}
	}

	/// Opens a file handle for logging, returning the handle and the URL to any
	/// temporary file on disk.
	private func openLoggingHandle(options: Options) -> SignalProducer<(FileHandle, URL?), CarthageError> {
		if options.isVerbose {
			let out: (FileHandle, URL?) = (FileHandle.standardOutput, nil)
			return SignalProducer(value: out)
		} else {
			return openTemporaryFile()
				.map { handle, url in (handle, Optional(url)) }
				.mapError { error in
					let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
					return .writeFailed(temporaryDirectoryURL, error)
				}
		}
	}
}

/// Represents the user's chosen platform to build for.
public enum BuildPlatform: Equatable {
	/// Build for all available platforms.
	case all

	/// Build only for iOS.
	case iOS

	/// Build only for macOS.
	case macOS

	/// Build only for watchOS.
	case watchOS

	/// Build only for tvOS.
	case tvOS

	/// Build for multiple platforms within the list.
	case multiple([BuildPlatform])

	/// The set of `Platform` corresponding to this setting.
	public var platforms: Set<Platform> {
		switch self {
		case .all:
			return []

		case .iOS:
			return [ .iOS ]

		case .macOS:
			return [ .macOS ]

		case .watchOS:
			return [ .watchOS ]

		case .tvOS:
			return [ .tvOS ]

		case let .multiple(buildPlatforms):
			return buildPlatforms.reduce([]) { (set, buildPlatform) in
				return set.union(buildPlatform.platforms)
			}
		}
	}
}

public func ==(lhs: BuildPlatform, rhs: BuildPlatform) -> Bool {
	switch (lhs, rhs) {
	case let (.multiple(left), .multiple(right)):
		return left == right

	case (.all, .all), (.iOS, .iOS), (.macOS, .macOS), (.watchOS, .watchOS), (.tvOS, .tvOS):
		return true

	case _:
		return false
	}
}

extension BuildPlatform: CustomStringConvertible {
	public var description: String {
		switch self {
		case .all:
			return "all"

		case .iOS:
			return "iOS"

		case .macOS:
			return "macOS"

		case .watchOS:
			return "watchOS"

		case .tvOS:
			return "tvOS"

		case let .multiple(buildPlatforms):
			return buildPlatforms.map { $0.description }.joinWithSeparator(", ")
		}
	}
}

extension BuildPlatform: ArgumentType {
	public static let name = "platform"

	private static let acceptedStrings: [String: BuildPlatform] = [
		"macOS": .macOS, "Mac": .macOS, "OSX": .macOS, "macosx": .macOS,
		"iOS": .iOS, "iphoneos": .iOS, "iphonesimulator": .iOS,
		"watchOS": .watchOS, "watchsimulator": .watchOS,
		"tvOS": .tvOS, "tvsimulator": .tvOS, "appletvos": .tvOS, "appletvsimulator": .tvOS,
		"all": .all
	]

	public static func fromString(string: String) -> BuildPlatform? {
		let tokens = string.split()

		let findBuildPlatform: (String) -> BuildPlatform? = { string in
			return self.acceptedStrings.lazy
				.filter { key, _ in string.caseInsensitiveCompare(key) == .orderedSame }
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
				if let found = findBuildPlatform(token) where found != .all {
					buildPlatforms.append(found)
				} else {
					// Reject if an invalid value is included in the comma-
					// separated string.
					return nil
				}
			}
			return .multiple(buildPlatforms)
		}
	}
}
