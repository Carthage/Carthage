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

/// The name of the folder into which Carthage puts binaries it builds (relative
/// to the working directory).
// TODO: This should be configurable.
public let CarthageBinariesFolderName = "Carthage.build"

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

extension ProjectLocator: Printable {
	public var description: String {
		let lastComponent: String? = fileURL.lastPathComponent
		return lastComponent!
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
			return failure(error ?? CarthageError.ReadFailed(URL).error)
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

			sort(&matches)
			return ColdSignal.fromValues(matches).map { $0.locator }
		}

		return .error(enumerationError ?? CarthageError.ReadFailed(directoryURL).error)
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
		.skipWhile { line in !line.hasSuffix("Schemes:") }
		.skip(1)
		.takeWhile { line in !line.isEmpty }
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
			return failure(CarthageError.ParseError(description: "unexpected platform key \"(string)\"").error)
		}
	}

	/// Whether this platform targets iOS.
	public var targetsiOS: Bool {
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

/// Returns the value of all build settings in the given configuration.
public func buildSettings(arguments: BuildArguments) -> ColdSignal<Dictionary<String, String>> {
	let task = xcodebuildTask("-showBuildSettings", arguments)

	return launchTask(task)
		.map { (data: NSData) -> String in
			return NSString(data: data, encoding: NSStringEncoding(NSUTF8StringEncoding))!
		}
		.map { (string: String) -> ColdSignal<String> in
			return string.linesSignal
		}
		.merge(identity)
		.map { (line: String) -> Dictionary<String, String> in
			let components = split(line, { $0 == "=" }, maxSplit: 1)
			let trimSet = NSCharacterSet.whitespaceAndNewlineCharacterSet()

			if components.count == 2 {
				return [ components[0].stringByTrimmingCharactersInSet(trimSet): components[1].stringByTrimmingCharactersInSet(trimSet) ]
			} else {
				return [:]
			}
		}
		.reduce(initial: [:], combineDictionaries)
}

/// Returns the value for the given build setting, or an error if it could not
/// be determined.
private func valueForBuildSetting(setting: String, settings: Dictionary<String, String>) -> ColdSignal<String> {
	if let value = settings[setting] {
		return .single(value)
	} else {
		return .error(CarthageError.MissingBuildSetting(setting).error)
	}
}

/// Returns the value for the given build setting, or an error if it could not
/// be determined.
private func valueForBuildSetting(setting: String, arguments: BuildArguments) -> ColdSignal<String> {
	return buildSettings(arguments)
		.map { settings in valueForBuildSetting(setting, settings) }
		.merge(identity)
}

/// Determines the URL to the built products directory for the given settings.
private func URLToBuildProductsDirectory(settings: Dictionary<String, String>) -> ColdSignal<NSURL> {
	return valueForBuildSetting("BUILT_PRODUCTS_DIR", settings)
		.tryMap { productsDir -> Result<NSURL> in
			if let fileURL = NSURL.fileURLWithPath(productsDir, isDirectory: true) {
				return success(fileURL)
			} else {
				return failure(CarthageError.ParseError(description: "expected file URL for built products directory, got \(productsDir)").error)
			}
		}
}

/// Calculates a URL against `BUILT_PRODUCTS_DIR` using a build setting that
/// represents a relative path.
private func URLWithPathRelativeToBuildProductsDirectory(pathSettingName: String, settings: Dictionary<String, String>) -> ColdSignal<NSURL> {
	return URLToBuildProductsDirectory(settings)
		// TODO: This should be a zip.
		.combineLatestWith(valueForBuildSetting(pathSettingName, settings))
		.map { (productsDirURL, path) in productsDirURL.URLByAppendingPathComponent(path) }
}

/// Determines where the executable for the product of the given scheme will
/// exist, when built with the given settings.
private func URLToBuiltExecutable(settings: Dictionary<String, String>) -> ColdSignal<NSURL> {
	return URLWithPathRelativeToBuildProductsDirectory("EXECUTABLE_PATH", settings)
}

/// Determines where the build product for the given scheme will exist, when
/// built with the given settings.
private func URLToBuiltProduct(settings: Dictionary<String, String>) -> ColdSignal<NSURL> {
	return URLWithPathRelativeToBuildProductsDirectory("WRAPPER_NAME", settings)
}

/// Determines the relative path (from the build folder) where the modules of a
/// bundle will exist, when built with the given settings.
///
/// If the product does not build modules, the returned signal will complete
/// without sending any values.
private func pathToModulesFolder(settings: Dictionary<String, String>) -> ColdSignal<String> {
	return valueForBuildSetting("CONTENTS_FOLDER_PATH", settings)
		// TODO: This should be a zip.
		.combineLatestWith(valueForBuildSetting("PRODUCT_MODULE_NAME", settings))
		.catch { _ in .empty() }
		.map { (contentsPath, moduleName) -> String in
			return contentsPath.stringByAppendingPathComponent("Modules").stringByAppendingPathComponent(moduleName).stringByAppendingPathExtension("swiftmodule")!
		}
}

/// Finds the built product for the given settings, then copies it (preserving
/// its name) into the given folder. The folder will be created if it does not
/// already exist.
///
/// Returns a signal that will send the URL after copying upon success.
private func copyBuildProductIntoDirectory(directoryURL: NSURL, settings: Dictionary<String, String>) -> ColdSignal<NSURL> {
	return ColdSignal.lazy {
		var error: NSError?
		if !NSFileManager.defaultManager().createDirectoryAtURL(directoryURL, withIntermediateDirectories: true, attributes: nil, error: &error) {
			return .error(error ?? CarthageError.WriteFailed(directoryURL).error)
		}

		return valueForBuildSetting("WRAPPER_NAME", settings)
			.map(directoryURL.URLByAppendingPathComponent)
			.map { destinationURL in
				return URLToBuiltProduct(settings)
					.try { (productURL, error) in
						// TODO: Atomic copying.
						NSFileManager.defaultManager().removeItemAtURL(destinationURL, error: nil)
						return NSFileManager.defaultManager().copyItemAtURL(productURL, toURL: destinationURL, error: error)
					}
					.then(.single(destinationURL))
			}
			.merge(identity)
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

/// Attempts to merge the given executables into one fat binary, written to
/// the specified URL.
private func mergeExecutables(executableURLs: [NSURL], outputURL: NSURL) -> ColdSignal<()> {
	precondition(outputURL.fileURL)

	return ColdSignal.fromValues(executableURLs)
		.tryMap { URL -> Result<String> in
			if let path = URL.path {
				return success(path)
			} else {
				return failure(CarthageError.ParseError(description: "expected file URL to built executable, got (URL)").error)
			}
		}
		.reduce(initial: []) { $0 + [ $1 ] }
		.map { executablePaths -> ColdSignal<NSData> in
			let lipoTask = TaskDescription(launchPath: "/usr/bin/xcrun", arguments: [ "lipo", "-create" ] + executablePaths + [ "-output", outputURL.path! ])

			// TODO: Redirect stdout.
			return launchTask(lipoTask)
		}
		.merge(identity)
		.then(.empty())
}

/// If the given source URL represents an LLVM module, copies its contents into
/// the destination module.
///
/// Sends the URL to each file after copying.
private func mergeModuleIntoModule(sourceModuleDirectoryURL: NSURL, destinationModuleDirectoryURL: NSURL) -> ColdSignal<NSURL> {
	precondition(sourceModuleDirectoryURL.fileURL)
	precondition(destinationModuleDirectoryURL.fileURL)

	return ColdSignal { subscriber in
		let enumerator = NSFileManager.defaultManager().enumeratorAtURL(sourceModuleDirectoryURL, includingPropertiesForKeys: [ NSURLParentDirectoryURLKey ], options: NSDirectoryEnumerationOptions.SkipsSubdirectoryDescendants | NSDirectoryEnumerationOptions.SkipsHiddenFiles, errorHandler: nil)!

		while !subscriber.disposable.disposed {
			if let URL = enumerator.nextObject() as? NSURL {
				var parentDirectoryURL: AnyObject?
				var error: NSError?

				if !URL.getResourceValue(&parentDirectoryURL, forKey: NSURLParentDirectoryURLKey, error: &error) {
					subscriber.put(.Error(error ?? CarthageError.ReadFailed(URL).error))
					return
				}

				if let parentDirectoryURL = parentDirectoryURL as? NSURL {
					if !NSFileManager.defaultManager().createDirectoryAtURL(parentDirectoryURL, withIntermediateDirectories: true, attributes: nil, error: &error) {
						subscriber.put(.Error(error ?? CarthageError.WriteFailed(parentDirectoryURL).error))
						return
					}
				}

				let lastComponent: String? = URL.lastPathComponent
				let destinationURL = destinationModuleDirectoryURL.URLByAppendingPathComponent(lastComponent!)
				if NSFileManager.defaultManager().copyItemAtURL(URL, toURL: destinationURL, error: &error) {
					subscriber.put(.Next(Box(destinationURL)))
				} else {
					subscriber.put(.Error(error ?? CarthageError.WriteFailed(destinationURL).error))
					return
				}
			} else {
				break
			}
		}

		subscriber.put(.Completed)
	}
}

/// Builds one scheme of the given project, for all supported platforms.
///
/// Returns a signal of all standard output from `xcodebuild`, and a signal
/// which will send the URL to each product successfully built.
public func buildScheme(scheme: String, withConfiguration configuration: String, inProject project: ProjectLocator, #workingDirectoryURL: NSURL) -> (HotSignal<NSData>, ColdSignal<NSURL>) {
	precondition(workingDirectoryURL.fileURL)

	let (stdoutSignal, stdoutSink) = HotSignal<NSData>.pipe()
	let buildArgs = BuildArguments(project: project, scheme: scheme, configuration: configuration)

	let buildPlatform = { (platform: Platform) -> ColdSignal<Dictionary<String, String>> in
		var copiedArgs = buildArgs
		copiedArgs.platform = platform

		var buildScheme = xcodebuildTask("build", copiedArgs)
		buildScheme.workingDirectoryPath = workingDirectoryURL.path!

		return launchTask(buildScheme, standardOutput: stdoutSink)
			.then(buildSettings(copiedArgs))
	}

	// TODO: This should probably return a signal-of-signals, so callers can
	// track the starting and stopping of each scheme individually.
	//
	// This will also allow us to remove the event logging from
	// buildInDirectory().
	let buildSignal: ColdSignal<NSURL> = platformForScheme(scheme, inProject: project)
		.map { (platform: Platform) in
			switch platform {
			case .iPhoneSimulator: fallthrough
			case .iPhoneOS:
				return buildPlatform(.iPhoneSimulator)
					.concat(buildPlatform(.iPhoneOS))
					.reduce(initial: []) { $0 + [ $1 ] }
					.map { buildSettingsPerPlatform in
						let simulatorSettings = buildSettingsPerPlatform[0]
						let deviceSettings = buildSettingsPerPlatform[1]
						let folderURL = workingDirectoryURL.URLByAppendingPathComponent("\(CarthageBinariesFolderName)/iOS", isDirectory: true)

						return copyBuildProductIntoDirectory(folderURL, deviceSettings)
							.map { productURL in
								let mergeProductBinaries = URLToBuiltExecutable(simulatorSettings)
									.concat(URLToBuiltExecutable(deviceSettings))
									.reduce(initial: []) { $0 + [ $1 ] }
									// TODO: This should be a zip.
									.combineLatestWith(valueForBuildSetting("EXECUTABLE_PATH", deviceSettings).map(folderURL.URLByAppendingPathComponent))
									.map { (executableURLs: [NSURL], outputURL: NSURL) -> ColdSignal<()> in
										return mergeExecutables(executableURLs, outputURL)
									}
									.merge(identity)

								let sourceModulesURL = pathToModulesFolder(simulatorSettings)
									// TODO: This should be a zip.
									.combineLatestWith(URLToBuildProductsDirectory(simulatorSettings))
									.map { (modulesPath, productsURL) -> NSURL in
										return productsURL.URLByAppendingPathComponent(modulesPath)
									}

								let destinationModulesURL = pathToModulesFolder(deviceSettings)
									.map { modulesPath -> NSURL in
										return folderURL.URLByAppendingPathComponent(modulesPath)
									}

								let mergeProductModules = sourceModulesURL
									// TODO: This should be a zip.
									.combineLatestWith(destinationModulesURL)
									.map { (source: NSURL, destination: NSURL) -> ColdSignal<NSURL> in
										return mergeModuleIntoModule(source, destination)
									}
									.merge(identity)

								return mergeProductBinaries
									.then(mergeProductModules)
									.then(.single(productURL))
							}
							.merge(identity)
					}
					.merge(identity)

			default:
				return buildPlatform(platform)
					.map { settings -> ColdSignal<NSURL> in
						let folderURL = workingDirectoryURL.URLByAppendingPathComponent("\(CarthageBinariesFolderName)/Mac", isDirectory: true)
						return copyBuildProductIntoDirectory(folderURL, settings)
					}
					.merge(identity)
			}
		}
		.merge(identity)

	return (stdoutSignal, buildSignal)
}

/// A signal representing a scheme being built.
///
/// A signal of this type should send the project and scheme name when building
/// begins, then complete or error when building terminates.
public typealias BuildSchemeSignal = ColdSignal<(ProjectLocator, String)>

/// Attempts to build the dependency identified by the given project, then
/// places its build product into the root directory given.
///
/// Returns signals in the same format as buildInDirectory().
public func buildDependencyProject(dependency: ProjectIdentifier, rootDirectoryURL: NSURL, withConfiguration configuration: String) -> (HotSignal<NSData>, ColdSignal<BuildSchemeSignal>) {
	let dependencyURL = rootDirectoryURL.URLByAppendingPathComponent(dependency.relativePath, isDirectory: true)

	let (buildOutput, schemeSignals) = buildInDirectory(dependencyURL, withConfiguration: configuration)
	let copyProducts = ColdSignal<BuildSchemeSignal>.lazy {
		let rootBinariesURL = rootDirectoryURL.URLByAppendingPathComponent(CarthageBinariesFolderName, isDirectory: true)

		var error: NSError?
		if !NSFileManager.defaultManager().createDirectoryAtURL(rootBinariesURL, withIntermediateDirectories: true, attributes: nil, error: &error) {
			return .error(error ?? CarthageError.WriteFailed(rootBinariesURL).error)
		}

		// Link this dependency's Carthage.build folder to that of the root
		// project, so it can see all products built already, and so we can
		// automatically drop this dependency's product in the right place.
		let dependencyBinariesURL = dependencyURL.URLByAppendingPathComponent(CarthageBinariesFolderName, isDirectory: true)
		NSFileManager.defaultManager().removeItemAtURL(dependencyBinariesURL, error: nil)

		if !NSFileManager.defaultManager().createSymbolicLinkAtURL(dependencyBinariesURL, withDestinationURL: rootBinariesURL, error: &error) {
			return .error(error ?? CarthageError.WriteFailed(dependencyBinariesURL).error)
		}

		return schemeSignals
	}

	return (buildOutput, copyProducts)
}

/// Builds the first project or workspace found within the given directory.
///
/// Returns a signal of all standard output from `xcodebuild`, and a
/// signal-of-signals representing each scheme being built.
public func buildInDirectory(directoryURL: NSURL, withConfiguration configuration: String) -> (HotSignal<NSData>, ColdSignal<BuildSchemeSignal>) {
	precondition(directoryURL.fileURL)

	let (stdoutSignal, stdoutSink) = HotSignal<NSData>.pipe()
	let locatorSignal = locateProjectsInDirectory(directoryURL)

	let schemeSignals = locatorSignal
		.filter { (project: ProjectLocator) in
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
		.map { (scheme: String, project: ProjectLocator) -> ColdSignal<(ProjectLocator, String)> in
			let (buildOutput, productURLs) = buildScheme(scheme, withConfiguration: configuration, inProject: project, workingDirectoryURL: directoryURL)

			return ColdSignal.lazy {
				let outputDisposable = buildOutput.observe(stdoutSink)

				return ColdSignal.single((project, scheme))
					.concat(productURLs.then(.empty()))
					.on(disposed: {
						outputDisposable.dispose()
					})
			}
		}

	return (stdoutSignal, schemeSignals)
}
