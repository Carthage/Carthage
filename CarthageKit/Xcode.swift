//
//  Xcode.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-11.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa

/// Describes how to locate the actual project or workspace that Xcode should
/// build.
public enum ProjectLocator: Comparable {
	/// The `xcworkspace` at the given file URL should be built.
	case Workspace(NSURL)

	/// The `xcodeproj` at the given file URL should be built.
	case ProjectFile(NSURL)

	/// The file URL this locator refers to.
	public var fileURL: NSURL {
		switch self {
		case let .Workspace(URL):
			assert(URL.fileURL)
			return URL

		case let .ProjectFile(URL):
			assert(URL.fileURL)
			return URL
		}
	}

	/// The arguments that should be passed to `xcodebuild` to help it locate
	/// this project.
	private var arguments: [String] {
		switch self {
		case let .Workspace(URL):
			return [ "-workspace", URL.path! ]

		case let .ProjectFile(URL):
			return [ "-project", URL.path! ]
		}
	}
}

public func ==(lhs: ProjectLocator, rhs: ProjectLocator) -> Bool {
	switch (lhs, rhs) {
	case let (.Workspace(left), .Workspace(right)):
		return left == right

	case let (.ProjectFile(left), .ProjectFile(right)):
		return left == right

	default:
		return false
	}
}

public func <(lhs: ProjectLocator, rhs: ProjectLocator) -> Bool {
	// Prefer workspaces over projects.
	switch (lhs, rhs) {
	case let (.Workspace, .ProjectFile):
		return true

	case let (.ProjectFile, .Workspace):
		return false

	default:
		return lexicographicalCompare(lhs.fileURL.path!, rhs.fileURL.path!)
	}
}

/// Configures a build with Xcode.
public struct BuildArguments {
	/// The project to build.
	public let project: ProjectLocator

	/// The scheme to build in the project.
	public var scheme: String?

	/// The configuration to use when building the project.
	public var configuration: String?

	/// The platform to build for.
	public var platform: Platform?

	public init(project: ProjectLocator, scheme: String? = nil, configuration: String? = nil, platform: Platform? = nil) {
		self.project = project
		self.scheme = scheme
		self.configuration = configuration
		self.platform = platform
	}

	/// The `xcodebuild` invocation corresponding to the receiver.
	private var arguments: [String] {
		var args = [ "xcodebuild" ] + project.arguments

		if let scheme = scheme {
			args += [ "-scheme", scheme ]
		}

		if let configuration = configuration {
			args += [ "-configuration", configuration ]
		}

		if let platform = platform {
			args += platform.arguments
		}

		return args
	}
}

extension BuildArguments: Printable {
	public var description: String {
		return " ".join(arguments)
	}
}

/// A candidate match for a project's canonical `ProjectLocator`.
private struct ProjectEnumerationMatch: Comparable {
	let locator: ProjectLocator
	let level: Int

	/// Checks whether a project exists at the given URL, returning a match if
	/// so.
	static func matchURL(URL: NSURL, fromEnumerator enumerator: NSDirectoryEnumerator) -> Result<ProjectEnumerationMatch> {
		var typeIdentifier: AnyObject?
		var error: NSError?

		if !URL.getResourceValue(&typeIdentifier, forKey: NSURLTypeIdentifierKey, error: &error) {
			if let error = error {
				return failure(error)
			} else {
				return failure()
			}
		}

		if let typeIdentifier = typeIdentifier as? String {
			if (UTTypeConformsTo(typeIdentifier, "com.apple.dt.document.workspace") != 0) {
				return success(ProjectEnumerationMatch(locator: .Workspace(URL), level: enumerator.level))
			} else if (UTTypeConformsTo(typeIdentifier, "com.apple.xcode.project") != 0) {
				return success(ProjectEnumerationMatch(locator: .ProjectFile(URL), level: enumerator.level))
			}
		}

		return failure()
	}
}

private func ==(lhs: ProjectEnumerationMatch, rhs: ProjectEnumerationMatch) -> Bool {
	return lhs.locator == rhs.locator
}

private func <(lhs: ProjectEnumerationMatch, rhs: ProjectEnumerationMatch) -> Bool {
	if lhs.level < rhs.level {
		return true
	} else if lhs.level > rhs.level {
		return false
	}

	return lhs.locator < rhs.locator
}

/// Attempts to locate projects and workspaces within the given directory.
///
/// Sends all matches in preferential order.
public func locateProjectsInDirectory(directoryURL: NSURL) -> ColdSignal<ProjectLocator> {
	let enumerationOptions = NSDirectoryEnumerationOptions.SkipsHiddenFiles | NSDirectoryEnumerationOptions.SkipsPackageDescendants

	return ColdSignal.lazy {
		var enumerationError: NSError?
		let enumerator = NSFileManager.defaultManager().enumeratorAtURL(directoryURL, includingPropertiesForKeys: [ NSURLTypeIdentifierKey ], options: enumerationOptions) { (URL, error) in
			enumerationError = error
			return false
		}

		if let enumerator = enumerator {
			var matches: [ProjectEnumerationMatch] = []

			while let URL = enumerator.nextObject() as? NSURL {
				if let match = ProjectEnumerationMatch.matchURL(URL, fromEnumerator: enumerator).value() {
					matches.append(match)
				}
			}

			if matches.count > 0 {
				sort(&matches)
				return ColdSignal.fromValues(matches).map { $0.locator }
			}
		}

		return .error(enumerationError ?? RACError.Empty.error)
	}
}

/// Creates a task description for executing `xcodebuild` with the given
/// arguments.
public func xcodebuildTask(task: String, buildArguments: BuildArguments) -> TaskDescription {
	return TaskDescription(launchPath: "/usr/bin/xcrun", arguments: buildArguments.arguments + [ task ])
}

/// Sends each scheme found in the given project.
public func schemesInProject(project: ProjectLocator) -> ColdSignal<String> {
	let task = xcodebuildTask("-list", BuildArguments(project: project))

	return launchTask(task)
		.map { (data: NSData) -> String in
			return NSString(data: data, encoding: NSStringEncoding(NSUTF8StringEncoding))!
		}
		.map { (string: String) -> ColdSignal<String> in
			return string.linesSignal
		}
		.merge(identity)
		.skipWhile { (line: String) -> Bool in line.hasSuffix("Schemes:") ? false : true }
		.skip(1)
		.takeWhile { (line: String) -> Bool in line.isEmpty ? false : true }
		.map { (line: String) -> String in line.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceCharacterSet()) }
}

/// Represents a platform or SDK buildable by Xcode.
public enum Platform {
	/// Mac OS X.
	case MacOSX

	/// iOS, for device.
	case iPhoneOS

	/// iOS, for the simulator.
	case iPhoneSimulator

	/// Attempts to parse a platform name from a string returned from
	/// `xcodebuild`.
	public static func fromString(string: String) -> Result<Platform> {
		switch string {
		case "macosx":
			return success(.MacOSX)

		case "iphoneos":
			return success(.iPhoneOS)

		case "iphonesimulator":
			return success(.iPhoneSimulator)

		default:
			return failure()
		}
	}

	/// Whether this platform targets iOS.
	public var iOS: Bool {
		switch self {
		case .iPhoneOS:
			return true

		case .iPhoneSimulator:
			return true

		case .MacOSX:
			return false
		}
	}

	/// The arguments that should be passed to `xcodebuild` to select this
	/// platform for building.
	private var arguments: [String] {
		switch self {
		case .MacOSX:
			return [ "-sdk", "macosx" ]

		case .iPhoneOS:
			return [ "-sdk", "iphoneos" ]

		case .iPhoneSimulator:
			return [ "-sdk", "iphonesimulator" ]
		}
	}
}

/// Returns the value for the given build setting, or an error if it could not
/// be determined.
private func valueForBuildSetting(setting: String, buildArguments: BuildArguments) -> ColdSignal<String> {
	let task = xcodebuildTask("-showBuildSettings", buildArguments)

	return launchTask(task)
		.map { (data: NSData) -> String in
			return NSString(data: data, encoding: NSStringEncoding(NSUTF8StringEncoding))!
		}
		.map { (string: String) -> ColdSignal<String> in
			return string.linesSignal
		}
		.merge(identity)
		.map { (line: String) -> ColdSignal<String> in
			let components = split(line, { $0 == "=" }, maxSplit: 1)
			let trimSet = NSCharacterSet.whitespaceAndNewlineCharacterSet()

			if components.count == 2 && components[0].stringByTrimmingCharactersInSet(trimSet) == setting {
				return .single(components[1].stringByTrimmingCharactersInSet(trimSet))
			} else {
				return .empty()
			}
		}
		.merge(identity)
		.concat(.error(CarthageError.MissingBuildSetting(setting).error))
		.take(1)
}

/// Determines the relative path to the executable that will be built from the
/// given arguments.
private func executablePath(buildArguments: BuildArguments) -> ColdSignal<String> {
	// TODO: Combine with URLToBuiltProduct() somehow.
	return valueForBuildSetting("EXECUTABLE_PATH", buildArguments)
}

/// Determines where the build product for the given scheme will exist, when
/// built with the given settings.
private func URLToBuiltProduct(buildArguments: BuildArguments) -> ColdSignal<NSURL> {
	// TODO: Parse multiple build settings in the same pass.
	return valueForBuildSetting("BUILT_PRODUCTS_DIR", buildArguments)
		// TODO: This should be a zip.
		.combineLatestWith(valueForBuildSetting("WRAPPER_NAME", buildArguments))
		.map { (productsDir, wrapperName) in
			return NSURL.fileURLWithPath(productsDir, isDirectory: true)!.URLByAppendingPathComponent(wrapperName)
		}
}

/// Determines which platform the given scheme builds for, by default.
///
/// If the platform is unrecognized or could not be determined, an error will be
/// sent on the returned signal.
public func platformForScheme(scheme: String, inProject project: ProjectLocator) -> ColdSignal<Platform> {
	return valueForBuildSetting("PLATFORM_NAME", BuildArguments(project: project, scheme: scheme))
		.tryMap(Platform.fromString)
}

/// Builds one scheme of the given project, for all supported platforms.
public func buildScheme(scheme: String, withConfiguration configuration: String, inProject project: ProjectLocator, #workingDirectoryURL: NSURL) -> ColdSignal<()> {
	precondition(workingDirectoryURL.fileURL)

	let handle = NSFileHandle.fileHandleWithStandardOutput()
	let stdoutSink = SinkOf<NSData> { data in
		handle.writeData(data)
	}

	let buildArgs = BuildArguments(project: project, scheme: scheme, configuration: configuration)

	let buildPlatform = { (platform: Platform) -> ColdSignal<NSURL> in
		var copiedArgs = buildArgs
		copiedArgs.platform = platform

		var buildScheme = xcodebuildTask("build", copiedArgs)
		buildScheme.workingDirectoryPath = workingDirectoryURL.path!

		return launchTask(buildScheme, standardOutput: stdoutSink)
			.then(URLToBuiltProduct(copiedArgs))
	}

	return platformForScheme(scheme, inProject: project)
		.map { (platform: Platform) -> ColdSignal<NSURL> in
			switch platform {
			case .iPhoneSimulator: fallthrough
			case .iPhoneOS:
				return buildPlatform(.iPhoneSimulator)
					.concat(buildPlatform(.iPhoneOS))
					.reduce(initial: []) { $0 + [ $1 ] }
							.on(completed: { println("Completed reduce") })
					// TODO: This should be a zip.
					.combineLatestWith(executablePath(buildArgs))
					.map { (productURLs: [NSURL], executablePath: String) -> ColdSignal<NSURL> in
						let simulatorURL = productURLs[0]
						let deviceURL = productURLs[1]

						let folderURL = workingDirectoryURL.URLByAppendingPathComponent("Carthage/iOS", isDirectory: true)
						var error: NSError?
						if !NSFileManager.defaultManager().createDirectoryAtURL(folderURL, withIntermediateDirectories: true, attributes: nil, error: &error) {
							return .error(error ?? RACError.Empty.error)
						}

						let destinationURL = folderURL.URLByAppendingPathComponent(deviceURL.lastPathComponent)
						
						// TODO: Atomic copying.
						NSFileManager.defaultManager().removeItemAtURL(destinationURL, error: nil)
						
						if !NSFileManager.defaultManager().copyItemAtURL(deviceURL, toURL: destinationURL, error: &error) {
							return .error(error ?? RACError.Empty.error)
						}

						// TODO: Deduplicate, handle errors.
						let simulatorExecutable = simulatorURL.URLByDeletingLastPathComponent!.URLByAppendingPathComponent(executablePath, isDirectory: false)
						let deviceExecutable = deviceURL.URLByDeletingLastPathComponent!.URLByAppendingPathComponent(executablePath, isDirectory: false)
						let destinationExecutable = destinationURL.URLByDeletingLastPathComponent!.URLByAppendingPathComponent(executablePath, isDirectory: false)

						let lipoTask = TaskDescription(launchPath: "/usr/bin/xcrun", arguments: [ "lipo", "-create", simulatorExecutable.path!, deviceExecutable.path!, "-output", destinationExecutable.path! ])
						println(lipoTask)
						return launchTask(lipoTask, standardOutput: stdoutSink)
							.on(completed: { println("Completed task") })
							.then(.single(destinationURL))
					}
					.merge(identity)

			default:
				return buildPlatform(platform)
					.tryMap { (productURL: NSURL, error: NSErrorPointer) -> NSURL? in
						let folderURL = workingDirectoryURL.URLByAppendingPathComponent("Carthage/Mac", isDirectory: true)
						if !NSFileManager.defaultManager().createDirectoryAtURL(folderURL, withIntermediateDirectories: true, attributes: nil, error: error) {
							return nil
						}

						let destinationURL = folderURL.URLByAppendingPathComponent(productURL.lastPathComponent)
						
						// TODO: Atomic copying.
						NSFileManager.defaultManager().removeItemAtURL(destinationURL, error: nil)
						
						if !NSFileManager.defaultManager().copyItemAtURL(productURL, toURL: destinationURL, error: error) {
							return nil
						}

						return destinationURL
					}
			}
		}
		.merge(identity)
		.then(.empty())
}

public func buildInDirectory(directoryURL: NSURL, withConfiguration configuration: String) -> ColdSignal<()> {
	precondition(directoryURL.fileURL)

	let locatorSignal = locateProjectsInDirectory(directoryURL)
	return locatorSignal.filter { (project: ProjectLocator) in
			switch project {
			case .ProjectFile:
				return true

			default:
				return false
			}
		}
		.take(1)
		.map { (project: ProjectLocator) -> ColdSignal<String> in
			return schemesInProject(project)
		}
		.merge(identity)
		.combineLatestWith(locatorSignal.take(1))
		.map { (scheme: String, project: ProjectLocator) -> ColdSignal<()> in
			return buildScheme(scheme, withConfiguration: configuration, inProject: project, workingDirectoryURL: directoryURL)
				.on(subscribed: {
					println("*** Building scheme \(scheme)…\n")
				})
		}
		.concat(identity)
}
