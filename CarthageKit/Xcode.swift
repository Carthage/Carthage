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
import ReactiveTask

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

/// Describes the type of product built by an Xcode target.
public enum ProductType: Equatable {
	/// A framework bundle.
	case Framework

	/// A static library.
	case StaticLibrary

	/// A unit test bundle.
	case TestBundle

	/// Attempts to parse a product type from a string returned from
	/// `xcodebuild`.
	public static func fromString(string: String) -> Result<ProductType> {
		switch string {
		case "com.apple.product-type.framework":
			return success(.Framework)

		case "com.apple.product-type.library.static":
			return success(.StaticLibrary)

		case "com.apple.product-type.bundle.unit-test":
			return success(.TestBundle)

		default:
			return failure(CarthageError.ParseError(description: "unexpected product type \"(string)\"").error)
		}
	}
}

public func ==(lhs: ProductType, rhs: ProductType) -> Bool {
	switch (lhs, rhs) {
	case (.Framework, .Framework):
		return true

	case (.StaticLibrary, .StaticLibrary):
		return true

	case (.TestBundle, .TestBundle):
		return true

	default:
		return false
	}
}

/// A map of build settings and their values, as generated by Xcode.
public struct BuildSettings {
	/// The target to which these settings apply.
	public let target: String

	/// All build settings given at initialization.
	public let settings: Dictionary<String, String>

	public init(target: String, settings: Dictionary<String, String>) {
		self.target = target
		self.settings = settings
	}

	/// Matches lines of the forms:
	///
	/// Build settings for action build and target "ReactiveCocoaLayout Mac":
	/// Build settings for action test and target CarthageKitTests:
	private static let targetSettingsRegex = NSRegularExpression(pattern: "^Build settings for action (?:\\S+) and target \\\"?([^\":]+)\\\"?:$", options: NSRegularExpressionOptions.CaseInsensitive | NSRegularExpressionOptions.AnchorsMatchLines, error: nil)!

	/// Invokes `xcodebuild` to retrieve build settings for the given build
	/// arguments.
	///
	/// Upon success, sends one BuildSettings value for each target included in
	/// the referenced scheme.
	public static func loadWithArguments(arguments: BuildArguments) -> ColdSignal<BuildSettings> {
		let task = xcodebuildTask("-showBuildSettings", arguments)

		return launchTask(task)
			.map { (data: NSData) -> String in
				return NSString(data: data, encoding: NSStringEncoding(NSUTF8StringEncoding))!
			}
			.map { (string: String) -> ColdSignal<BuildSettings> in
				return ColdSignal { (sink, disposable) in
					var currentSettings: [String: String] = [:]
					var currentTarget: String?

					let flushTarget = { () -> () in
						if let currentTarget = currentTarget {
							let buildSettings = self(target: currentTarget, settings: currentSettings)
							sink.put(.Next(Box(buildSettings)))
						}

						currentTarget = nil
						currentSettings = [:]
					}

					(string as NSString).enumerateLinesUsingBlock { (line, stop) in
						if disposable.disposed {
							stop.memory = true
							return
						}

						let matches: NSArray? = self.targetSettingsRegex.matchesInString(line, options: nil, range: NSMakeRange(0, (line as NSString).length))
						if let matches = matches {
							if matches.count > 0 {
								let result = matches.firstObject as NSTextCheckingResult
								let targetRange = result.rangeAtIndex(1)

								flushTarget()
								currentTarget = (line as NSString).substringWithRange(targetRange)
								return
							}
						}

						let components = split(line, { $0 == "=" }, maxSplit: 1)
						let trimSet = NSCharacterSet.whitespaceAndNewlineCharacterSet()

						if components.count == 2 {
							currentSettings[components[0].stringByTrimmingCharactersInSet(trimSet)] = components[1].stringByTrimmingCharactersInSet(trimSet)
						}
					}

					flushTarget()
					sink.put(.Completed)
				}
			}
			.merge(identity)
	}

	/// Determines which platform the given scheme builds for, by default.
	///
	/// If the platform is unrecognized or could not be determined, an error will be
	/// sent on the returned signal.
	public static func platformForScheme(scheme: String, inProject project: ProjectLocator) -> ColdSignal<Platform> {
		return loadWithArguments(BuildArguments(project: project, scheme: scheme))
			.take(1)
			.tryMap { settings -> Result<String> in
				return settings["PLATFORM_NAME"]
			}
			.tryMap(Platform.fromString)
	}

	/// Returns the value for the given build setting, or an error if it could
	/// not be determined.
	public subscript(key: String) -> Result<String> {
		if let value = settings[key] {
			return success(value)
		} else {
			return failure(CarthageError.MissingBuildSetting(key).error)
		}
	}

	/// Attempts to determine the ProductType specified in these build settings.
	public var productType: Result<ProductType> {
		return self["PRODUCT_TYPE"].flatMap { typeString in
			return ProductType.fromString(typeString)
		}
	}

	/// Attempts to determine the URL to the built products directory.
	public var builtProductsDirectoryURL: Result<NSURL> {
		return self["BUILT_PRODUCTS_DIR"].flatMap { productsDir in
			if let fileURL = NSURL.fileURLWithPath(productsDir, isDirectory: true) {
				return success(fileURL)
			} else {
				return failure(CarthageError.ParseError(description: "expected file URL for built products directory, got \(productsDir)").error)
			}
		}
	}

	/// Attempts to determine the relative path (from the build folder) to the
	/// built executable.
	public var executablePath: Result<String> {
		return self["EXECUTABLE_PATH"]
	}

	/// Attempts to determine the URL to the built executable.
	public var executableURL: Result<NSURL> {
		return builtProductsDirectoryURL.flatMap { builtProductsURL in
			return self.executablePath.map { executablePath in
				return builtProductsURL.URLByAppendingPathComponent(executablePath)
			}
		}
	}

	/// Attempts to determine the name of the built product's wrapper bundle.
	public var wrapperName: Result<String> {
		return self["WRAPPER_NAME"]
	}

	/// Attempts to determine the URL to the built product's wrapper.
	public var wrapperURL: Result<NSURL> {
		return builtProductsDirectoryURL.flatMap { builtProductsURL in
			return self.wrapperName.map { wrapperName in
				return builtProductsURL.URLByAppendingPathComponent(wrapperName)
			}
		}
	}

	/// Attempts to determine the relative path (from the build folder) where
	/// the Swift modules for the built product will exist.
	///
	/// If the product does not build any modules, `nil` will be returned.
	private var relativeModulesPath: Result<String?> {
		if let moduleName = self["PRODUCT_MODULE_NAME"].value() {
			return self["CONTENTS_FOLDER_PATH"].map { contentsPath in
				return contentsPath.stringByAppendingPathComponent("Modules").stringByAppendingPathComponent(moduleName).stringByAppendingPathExtension("swiftmodule")!
			}
		} else {
			return success(nil)
		}
	}
}

/// Finds the built product for the given settings, then copies it (preserving
/// its name) into the given folder. The folder will be created if it does not
/// already exist.
///
/// Returns a signal that will send the URL after copying upon success.
private func copyBuildProductIntoDirectory(directoryURL: NSURL, settings: BuildSettings) -> ColdSignal<NSURL> {
	return ColdSignal.fromResult(settings.wrapperName)
		.map(directoryURL.URLByAppendingPathComponent)
		.combineLatestWith(.fromResult(settings.wrapperURL))
		.map { (target, source) in
			return copyFramework(source, target)
		}
		.merge(identity)
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

	return ColdSignal { (sink, disposable) in
		let enumerator = NSFileManager.defaultManager().enumeratorAtURL(sourceModuleDirectoryURL, includingPropertiesForKeys: [ NSURLParentDirectoryURLKey ], options: NSDirectoryEnumerationOptions.SkipsSubdirectoryDescendants | NSDirectoryEnumerationOptions.SkipsHiddenFiles, errorHandler: nil)!

		while !disposable.disposed {
			if let URL = enumerator.nextObject() as? NSURL {
				var parentDirectoryURL: AnyObject?
				var error: NSError?

				if !URL.getResourceValue(&parentDirectoryURL, forKey: NSURLParentDirectoryURLKey, error: &error) {
					sink.put(.Error(error ?? CarthageError.ReadFailed(URL).error))
					return
				}

				if let parentDirectoryURL = parentDirectoryURL as? NSURL {
					if !NSFileManager.defaultManager().createDirectoryAtURL(parentDirectoryURL, withIntermediateDirectories: true, attributes: nil, error: &error) {
						sink.put(.Error(error ?? CarthageError.WriteFailed(parentDirectoryURL).error))
						return
					}
				}

				let lastComponent: String? = URL.lastPathComponent
				let destinationURL = destinationModuleDirectoryURL.URLByAppendingPathComponent(lastComponent!)
				if NSFileManager.defaultManager().copyItemAtURL(URL, toURL: destinationURL, error: &error) {
					sink.put(.Next(Box(destinationURL)))
				} else {
					sink.put(.Error(error ?? CarthageError.WriteFailed(destinationURL).error))
					return
				}
			} else {
				break
			}
		}

		sink.put(.Completed)
	}
}

/// Determines whether the specified product type should be built automatically.
private func shouldBuildProductType(productType: ProductType) -> Bool {
	return productType == .Framework
}

/// Determines whether the given scheme should be built automatically.
private func shouldBuildScheme(buildArguments: BuildArguments) -> ColdSignal<Bool> {
	precondition(buildArguments.scheme != nil)

	return BuildSettings.loadWithArguments(buildArguments)
		.map { settings -> ColdSignal<ProductType> in
			return ColdSignal.fromResult(settings.productType)
				.catch { _ in .empty() }
		}
		.concat(identity)
		.filter(shouldBuildProductType)
		// If we find any framework target, we should indeed build this scheme.
		.map { _ in true }
		// Otherwise, nope.
		.concat(.single(false))
		.take(1)
}

/// Aggregates all of the build settings sent on the given signal, associating
/// each with the name of its target.
///
/// Returns a signal which will send the aggregated dictionary upon completion
/// of the input signal, then itself complete.
private func settingsByTarget(signal: ColdSignal<BuildSettings>) -> ColdSignal<[String: BuildSettings]> {
	return signal
		.map { settings in [ settings.target: settings ] }
		.reduce(initial: [:], combineDictionaries)
}

/// Combines the built products corresponding to the given settings, by creating
/// a fat binary of their executables and merging any Swift modules together,
/// generating a new built product in the given directory.
///
/// In order for this process to make any sense, the build products should have
/// been created from the same target, and differ only in the platform they were
/// built for.
///
/// Upon success, sends the URL to the merged product, then completes.
private func mergeBuildProductsIntoDirectory(firstProductSettings: BuildSettings, secondProductSettings: BuildSettings, destinationFolderURL: NSURL) -> ColdSignal<NSURL> {
	return copyBuildProductIntoDirectory(destinationFolderURL, firstProductSettings)
		.map { productURL in
			let mergeProductBinaries = ColdSignal.fromResult(firstProductSettings.executableURL)
				.concat(ColdSignal.fromResult(secondProductSettings.executableURL))
				.reduce(initial: []) { $0 + [ $1 ] }
				.zipWith(ColdSignal.fromResult(firstProductSettings.executablePath)
					.map(destinationFolderURL.URLByAppendingPathComponent))
				.map { (executableURLs: [NSURL], outputURL: NSURL) -> ColdSignal<()> in
					return mergeExecutables(executableURLs, outputURL)
				}
				.merge(identity)

			let sourceModulesURL = ColdSignal.fromResult(secondProductSettings.relativeModulesPath)
				.filter { $0 != nil }
				.zipWith(ColdSignal.fromResult(secondProductSettings.builtProductsDirectoryURL))
				.map { (modulesPath, productsURL) -> NSURL in
					return productsURL.URLByAppendingPathComponent(modulesPath!)
				}

			let destinationModulesURL = ColdSignal.fromResult(firstProductSettings.relativeModulesPath)
				.filter { $0 != nil }
				.map { modulesPath -> NSURL in
					return destinationFolderURL.URLByAppendingPathComponent(modulesPath!)
				}

			let mergeProductModules = sourceModulesURL
				.zipWith(destinationModulesURL)
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

/// Builds one scheme of the given project, for all supported platforms.
///
/// Returns a signal of all standard output from `xcodebuild`, and a signal
/// which will send the URL to each product successfully built.
public func buildScheme(scheme: String, withConfiguration configuration: String, inProject project: ProjectLocator, #workingDirectoryURL: NSURL) -> (HotSignal<NSData>, ColdSignal<NSURL>) {
	precondition(workingDirectoryURL.fileURL)

	let (stdoutSignal, stdoutSink) = HotSignal<NSData>.pipe()
	let buildArgs = BuildArguments(project: project, scheme: scheme, configuration: configuration)

	let buildPlatform = { (platform: Platform) -> ColdSignal<BuildSettings> in
		var copiedArgs = buildArgs
		copiedArgs.platform = platform

		var buildScheme = xcodebuildTask("build", copiedArgs)
		buildScheme.workingDirectoryPath = workingDirectoryURL.path!

		return launchTask(buildScheme, standardOutput: stdoutSink)
			.then(BuildSettings.loadWithArguments(copiedArgs))
			.filter { settings in
				// Only copy build products for the product types we care about.
				if let productType = settings.productType.value() {
					return shouldBuildProductType(productType)
				} else {
					return false
				}
			}
	}

	let buildSignal: ColdSignal<NSURL> = BuildSettings.platformForScheme(scheme, inProject: project)
		.map { (platform: Platform) in
			switch platform {
			case .iPhoneSimulator, .iPhoneOS:
				let folderURL = workingDirectoryURL.URLByAppendingPathComponent("\(CarthageBinariesFolderName)/iOS", isDirectory: true)

				return settingsByTarget(buildPlatform(.iPhoneSimulator))
					.map { simulatorSettingsByTarget -> ColdSignal<(BuildSettings, BuildSettings)> in
						return settingsByTarget(buildPlatform(.iPhoneOS))
							.map { deviceSettingsByTarget -> ColdSignal<(BuildSettings, BuildSettings)> in
								assert(simulatorSettingsByTarget.count == deviceSettingsByTarget.count, "Number of targets built for iOS Simulator (\(simulatorSettingsByTarget.count)) does not match number of targets built for iOS Device (\(deviceSettingsByTarget.count))")

								return ColdSignal { (sink, disposable) in
									for (target, simulatorSettings) in simulatorSettingsByTarget {
										if disposable.disposed {
											break
										}

										let deviceSettings = deviceSettingsByTarget[target]
										assert(deviceSettings != nil, "No iOS Device build settings found for target \"\(target)\"")

										sink.put(.Next(Box((simulatorSettings, deviceSettings!))))
									}

									sink.put(.Completed)
								}
							}
							.merge(identity)
					}
					.merge(identity)
					.map { (simulatorSettings, deviceSettings) -> ColdSignal<NSURL> in
						return mergeBuildProductsIntoDirectory(deviceSettings, simulatorSettings, folderURL)
					}
					.concat(identity)

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
			let buildArguments = BuildArguments(project: project, scheme: scheme, configuration: configuration)

			return shouldBuildScheme(buildArguments)
				.filter(identity)
				.map { _ in
					let (buildOutput, productURLs) = buildScheme(scheme, withConfiguration: configuration, inProject: project, workingDirectoryURL: directoryURL)
					buildOutput.observe(stdoutSink)

					return ColdSignal.single((project, scheme))
						.concat(productURLs.then(.empty()))
				}
				.merge(identity)
		}

	return (stdoutSignal, schemeSignals)
}

/// Strips a framework from unexpected architectures, optionally codesigning the
/// result.
public func stripFramework(frameworkURL: NSURL, #keepingArchitectures: [String], codesigningIdentity: String? = nil) -> ColdSignal<()> {
	let strip = architecturesInFramework(frameworkURL)
		.filter { !contains(keepingArchitectures, $0) }
		.map { stripArchitecture(frameworkURL, $0) }
		.concat(identity)

	let sign = codesigningIdentity.map { codesign(frameworkURL, $0) } ?? .empty()

	return strip.concat(sign)
}

/// Copies a framework into the given folder. The folder will be created if it
/// does not already exist.
///
/// Returns a signal that will send the URL after copying upon success.
public func copyFramework(from: NSURL, to: NSURL) -> ColdSignal<NSURL> {
	return ColdSignal.lazy {
		var error: NSError? = nil

		let manager = NSFileManager.defaultManager()

		if !manager.createDirectoryAtURL(to.URLByDeletingLastPathComponent!, withIntermediateDirectories: true, attributes: nil, error: &error) {
			return .error(error ?? CarthageError.WriteFailed(to.URLByDeletingLastPathComponent!).error)
		}

		if manager.fileExistsAtPath(to.path!) {
			if !manager.removeItemAtURL(to, error: &error) {
				return .error(error!)
			}
		}

		if manager.copyItemAtURL(from, toURL: to, error: &error) {
			return .single(to)
		} else {
			return .error(error ?? RACError.Empty.error)
		}
	}
}

/// Strips the given architecture from a framework.
private func stripArchitecture(frameworkURL: NSURL, architecture: String) -> ColdSignal<()> {
	return ColdSignal.lazy {
		return ColdSignal.fromResult(binaryURL(frameworkURL))
			.map { binaryURL -> ColdSignal<NSData> in
				let lipoTask = TaskDescription(launchPath: "/usr/bin/xcrun", arguments: [ "lipo", "-remove", architecture, "-output", binaryURL.path! , binaryURL.path!])

				return launchTask(lipoTask)
			}
			.merge(identity)
			.then(.empty())
	}
}

/// Returns a signal of all architectures present in a given framework.
public func architecturesInFramework(frameworkURL: NSURL) -> ColdSignal<String> {
	return ColdSignal.lazy {
		return ColdSignal.fromResult(binaryURL(frameworkURL))
			.map { binaryURL -> ColdSignal<String> in
				let lipoTask = TaskDescription(launchPath: "/usr/bin/xcrun", arguments: [ "lipo", "-info", binaryURL.path!])

				return launchTask(lipoTask)
					.map { data -> ColdSignal<String> in
						let output = NSString(data: data, encoding: NSUTF8StringEncoding) ?? ""

						let characterSet = NSMutableCharacterSet.alphanumericCharacterSet()
						characterSet.addCharactersInString(" _-")

						if output.hasPrefix("Architectures in the fat file:") {
							// The output of "lipo -info PathToBinary" for fat
							// files looks roughly like so:
							//
							//     Architectures in the fat file: PathToBinary are: armv7 arm64
							//
							let scanner = NSScanner(string: output)
							var architectures: NSString?

							scanner.scanUpToString(binaryURL.path!, intoString: nil)
							scanner.scanString(binaryURL.path!, intoString: nil)
							scanner.scanString("are:", intoString: nil)
							scanner.scanCharactersFromSet(characterSet, intoString: &architectures)

							let components = architectures?
								.componentsSeparatedByString(" ")
								.filter { ($0 as NSString).length > 0 } as [String]?

							if let components = components {
								return ColdSignal.fromValues(components)
							}
						}

						if output.hasPrefix("Non-fat file") {
							// The output of "lipo -info PathToBinary" for thin
							// files looks roughly like so:
							//
							//     Non-fat file: PathToBinary is architecture: x86_64
							//
							let scanner = NSScanner(string: output)
							var architecture: NSString?

							scanner.scanUpToString(binaryURL.path!, intoString: nil)
							scanner.scanString(binaryURL.path!, intoString: nil)
							scanner.scanString("is architecture:", intoString: nil)
							scanner.scanCharactersFromSet(characterSet, intoString: &architecture)

							if let architecture = architecture {
								return ColdSignal.single(architecture)
							}
						}

						return ColdSignal.error(CarthageError.InvalidArchitectures(description: "Could not read architectures from \(frameworkURL.path!)").error)
					}
					.merge(identity)
			}
			.merge(identity)
	}
}

/// Returns the URL of a binary inside a given framework.
private func binaryURL(frameworkURL: NSURL) -> Result<NSURL> {
	let plistURL = frameworkURL.URLByAppendingPathComponent("Info.plist")

	let plist = NSDictionary(contentsOfURL: plistURL)

	if let binaryName = plist?["CFBundleExecutable"] as String? {
		return success(frameworkURL.URLByAppendingPathComponent(binaryName))
	} else {
		return failure(CarthageError.ReadFailed(plistURL).error)
	}
}

/// Signs a framework with the given codesigning identity.
private func codesign(frameworkURL: NSURL, expandedIdentity: String) -> ColdSignal<()> {
	return ColdSignal.lazy { () -> ColdSignal<()> in
		let codesignTask = TaskDescription(launchPath: "/usr/bin/xcrun", arguments: [ "codesign", "--force", "--sign", expandedIdentity, "--preserve-metadata=identifier,entitlements", frameworkURL.path!])

		// TODO: Redirect stdout.
		return launchTask(codesignTask).then(.empty())
	}
}
