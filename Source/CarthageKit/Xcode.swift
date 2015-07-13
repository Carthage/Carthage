//
//  Xcode.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-11.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Box
import Foundation
import Result
import ReactiveCocoa
import ReactiveTask

/// The name of the folder into which Carthage puts binaries it builds (relative
/// to the working directory).
public let CarthageBinariesFolderPath = "Carthage/Build"

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

	/// The platform SDK to build for.
	public var sdk: SDK?

	public init(project: ProjectLocator, scheme: String? = nil, configuration: String? = nil, sdk: SDK? = nil) {
		self.project = project
		self.scheme = scheme
		self.configuration = configuration
		self.sdk = sdk
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

		if let sdk = sdk {
			args += sdk.arguments
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
	static func matchURL(URL: NSURL, fromEnumerator enumerator: NSDirectoryEnumerator) -> Result<ProjectEnumerationMatch, CarthageError> {
		if let URL = URL.URLByResolvingSymlinksInPath {
			var typeIdentifier: AnyObject?
			var error: NSError?

			if !URL.getResourceValue(&typeIdentifier, forKey: NSURLTypeIdentifierKey, error: &error) {
				return .failure(.ReadFailed(URL, error))
			}

			if let typeIdentifier = typeIdentifier as? String {
				if (UTTypeConformsTo(typeIdentifier, "com.apple.dt.document.workspace") != 0) {
					return .success(ProjectEnumerationMatch(locator: .Workspace(URL), level: enumerator.level))
				} else if (UTTypeConformsTo(typeIdentifier, "com.apple.xcode.project") != 0) {
					return .success(ProjectEnumerationMatch(locator: .ProjectFile(URL), level: enumerator.level))
				}
			}

			return .failure(.NotAProject(URL))
		}

		return .failure(.ReadFailed(URL, nil))
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
public func locateProjectsInDirectory(directoryURL: NSURL) -> SignalProducer<ProjectLocator, CarthageError> {
	let enumerationOptions = NSDirectoryEnumerationOptions.SkipsHiddenFiles | NSDirectoryEnumerationOptions.SkipsPackageDescendants

	return NSFileManager.defaultManager().carthage_enumeratorAtURL(directoryURL.URLByResolvingSymlinksInPath!, includingPropertiesForKeys: [ NSURLTypeIdentifierKey ], options: enumerationOptions, catchErrors: true)
		|> reduce([]) { (var matches: [ProjectEnumerationMatch], tuple) -> [ProjectEnumerationMatch] in
			let (enumerator, URL) = tuple
			if let match = ProjectEnumerationMatch.matchURL(URL, fromEnumerator: enumerator).value {
				matches.append(match)
			}

			return matches
		}
		|> map { (var matches) -> [ProjectEnumerationMatch] in
			sort(&matches)
			return matches
		}
		|> flatMap(.Merge) { matches -> SignalProducer<ProjectEnumerationMatch, CarthageError> in
			return SignalProducer(values: matches)
		}
		|> map { (match: ProjectEnumerationMatch) -> ProjectLocator in
			return match.locator
		}
}

/// Creates a task description for executing `xcodebuild` with the given
/// arguments.
public func xcodebuildTask(task: String, buildArguments: BuildArguments) -> TaskDescription {
	return TaskDescription(launchPath: "/usr/bin/xcrun", arguments: buildArguments.arguments + [ task ])
}

/// Sends each scheme found in the given project.
public func schemesInProject(project: ProjectLocator) -> SignalProducer<String, CarthageError> {
	let task = xcodebuildTask("-list", BuildArguments(project: project))

	return launchTask(task)
		|> ignoreTaskData
		|> mapError { .TaskError($0) }
		|> map { (data: NSData) -> String in
			return NSString(data: data, encoding: NSStringEncoding(NSUTF8StringEncoding))! as String
		}
		|> flatMap(.Merge) { (string: String) -> SignalProducer<String, CarthageError> in
			return string.linesProducer |> promoteErrors(CarthageError.self)
		}
		|> flatMap(.Merge) { line -> SignalProducer<String, CarthageError> in
			// Matches one of these two possible messages:
			//
			// '    This project contains no schemes.'
			// 'There are no schemes in workspace "Carthage".'
			if line.hasSuffix("contains no schemes.") || line.hasPrefix("There are no schemes") {
				return SignalProducer(error: .NoSharedSchemes(project, nil))
			} else {
				return SignalProducer(value: line)
			}
		}
		|> skipWhile { line in !line.hasSuffix("Schemes:") }
		|> skip(1)
		|> takeWhile { line in !line.isEmpty }
		// xcodebuild has a bug where xcodebuild -list can sometimes hang
		// indefinitely on projects that don't share any schemes, so
		// automatically bail out if it looks like that's happening.
		|> timeoutWithError(.XcodebuildListTimeout(project, nil), afterInterval: 8, onScheduler: QueueScheduler())
		|> map { (line: String) -> String in line.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceCharacterSet()) }
		|> filter { (line: String) -> Bool in
			if let schemePath = project.fileURL.URLByAppendingPathComponent("xcshareddata/xcschemes/\(line).xcscheme").path {
				return NSFileManager.defaultManager().fileExistsAtPath(schemePath)
			}
			return false
		}
}

/// Represents a platform to build for.
public enum Platform {
	/// Mac OS X.
	case Mac

	/// iOS for device and simulator.
	case iOS

	/// Apple Watch device and simulator.
	case watchOS

	/// All supported build platforms.
	public static let supportedPlatforms: [Platform] = [ .Mac, .iOS, .watchOS ]

	/// The relative path at which binaries corresponding to this platform will
	/// be stored.
	public var relativePath: String {
		let subfolderName: String

		switch self {
		case .Mac:
			subfolderName = "Mac"

		case .iOS:
			subfolderName = "iOS"

		case .watchOS:
			subfolderName = "watchOS"
		}

		return CarthageBinariesFolderPath.stringByAppendingPathComponent(subfolderName)
	}

	/// The SDKs that need to be built for this platform.
	public var SDKs: [SDK] {
		switch self {
		case .Mac:
			return [ .MacOSX ]

		case .iOS:
			return [ .iPhoneSimulator, .iPhoneOS ]

		case .watchOS:
			return [ .watchOS, .watchSimulator ]
		}
	}
}

extension Platform: Printable {
	public var description: String {
		switch self {
		case .Mac:
			return "Mac"

		case .iOS:
			return "iOS"

		case .watchOS:
			return "watchOS"
		}
	}
}

/// Represents an SDK buildable by Xcode.
public enum SDK: String {
	/// Mac OS X.
	case MacOSX = "macosx"

	/// iOS, for device.
	case iPhoneOS = "iphoneos"

	/// iOS, for the simulator.
	case iPhoneSimulator = "iphonesimulator"

	/// watchOS, for the Apple Watch device.
	case watchOS = "watchos"

	/// watchSimulator, for the Apple Watch simulator.
	case watchSimulator = "watchsimulator"

	/// Attempts to parse an SDK name from a string returned from `xcodebuild`.
	public static func fromString(string: String) -> Result<SDK, CarthageError> {
		return Result(self(rawValue: string), failWith: .ParseError(description: "unexpected SDK key \"(string)\""))
	}

	/// The platform that this SDK targets.
	public var platform: Platform {
		switch self {
		case .iPhoneOS, .iPhoneSimulator:
			return .iOS

		case .watchOS, .watchSimulator:
			return .watchOS

		case .MacOSX:
			return .Mac
		}
	}

	/// The arguments that should be passed to `xcodebuild` to select this
	/// SDK for building.
	private var arguments: [String] {
		switch self {
		case .MacOSX:
			// Passing in -sdk macosx appears to break implicit dependency
			// resolution (see Carthage/Carthage#347).
			//
			// Since we wouldn't be trying to build this target unless it were
			// for OS X already, just let xcodebuild figure out the SDK on its
			// own.
			return []

		case .iPhoneOS, .iPhoneSimulator, .watchOS, .watchSimulator:
			return [ "-sdk", rawValue ]
		}
	}
}

extension SDK: Printable {
	public var description: String {
		switch self {
		case .iPhoneOS:
			return "iOS Device"

		case .iPhoneSimulator:
			return "iOS Simulator"

		case .MacOSX:
			return "Mac OS X"

		case .watchOS:
			return "watchOS"

		case .watchSimulator:
			return "watchOS Simulator"
		}
	}
}

/// Describes the type of product built by an Xcode target.
public enum ProductType: String {
	/// A framework bundle.
	case Framework = "com.apple.product-type.framework"

	/// A static library.
	case StaticLibrary = "com.apple.product-type.library.static"

	/// A unit test bundle.
	case TestBundle = "com.apple.product-type.bundle.unit-test"

	/// Attempts to parse a product type from a string returned from
	/// `xcodebuild`.
	public static func fromString(string: String) -> Result<ProductType, CarthageError> {
		return Result(self(rawValue: string), failWith: .ParseError(description: "unexpected product type \"(string)\""))
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
	/// Upon .success, sends one BuildSettings value for each target included in
	/// the referenced scheme.
	public static func loadWithArguments(arguments: BuildArguments) -> SignalProducer<BuildSettings, CarthageError> {
		let task = xcodebuildTask("-showBuildSettings", arguments)

		return launchTask(task)
			|> ignoreTaskData
			|> mapError { .TaskError($0) }
			|> map { (data: NSData) -> String in
				return NSString(data: data, encoding: NSStringEncoding(NSUTF8StringEncoding))! as String
			}
			|> flatMap(.Merge) { (string: String) -> SignalProducer<BuildSettings, CarthageError> in
				return SignalProducer { observer, disposable in
					var currentSettings: [String: String] = [:]
					var currentTarget: String?

					let flushTarget = { () -> () in
						if let currentTarget = currentTarget {
							let buildSettings = self(target: currentTarget, settings: currentSettings)
							sendNext(observer, buildSettings)
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
								let result = matches.firstObject as! NSTextCheckingResult
								let targetRange = result.rangeAtIndex(1)

								flushTarget()
								currentTarget = (line as NSString).substringWithRange(targetRange)
								return
							}
						}

						let components = split(line, maxSplit: 1) { $0 == "=" }
						let trimSet = NSCharacterSet.whitespaceAndNewlineCharacterSet()

						if components.count == 2 {
							currentSettings[components[0].stringByTrimmingCharactersInSet(trimSet)] = components[1].stringByTrimmingCharactersInSet(trimSet)
						}
					}

					flushTarget()
					sendCompleted(observer)
				}
			}
	}

	/// Determines which SDK the given scheme builds for, by default.
	///
	/// If the SDK is unrecognized or could not be determined, an error will be
	/// sent on the returned signal.
	public static func SDKForScheme(scheme: String, inProject project: ProjectLocator) -> SignalProducer<SDK, CarthageError> {
		return loadWithArguments(BuildArguments(project: project, scheme: scheme))
			|> take(1)
			|> tryMap { $0.buildSDK }
	}

	/// Returns the value for the given build setting, or an error if it could
	/// not be determined.
	public subscript(key: String) -> Result<String, CarthageError> {
		if let value = settings[key] {
			return .success(value)
		} else {
			return .failure(.MissingBuildSetting(key))
		}
	}

	/// Attempts to determine the SDK this scheme builds for.
	public var buildSDK: Result<SDK, CarthageError> {
		return self["PLATFORM_NAME"].flatMap(SDK.fromString)
	}

	/// Attempts to determine the ProductType specified in these build settings.
	public var productType: Result<ProductType, CarthageError> {
		return self["PRODUCT_TYPE"].flatMap { typeString in
			return ProductType.fromString(typeString)
		}
	}

	/// Attempts to determine the URL to the built products directory.
	public var builtProductsDirectoryURL: Result<NSURL, CarthageError> {
		return self["BUILT_PRODUCTS_DIR"].flatMap { productsDir in
			if let fileURL = NSURL.fileURLWithPath(productsDir, isDirectory: true) {
				return .success(fileURL)
			} else {
				return .failure(.ParseError(description: "expected file URL for built products directory, got \(productsDir)"))
			}
		}
	}

	/// Attempts to determine the relative path (from the build folder) to the
	/// built executable.
	public var executablePath: Result<String, CarthageError> {
		return self["EXECUTABLE_PATH"]
	}

	/// Attempts to determine the URL to the built executable.
	public var executableURL: Result<NSURL, CarthageError> {
		return builtProductsDirectoryURL.flatMap { builtProductsURL in
			return self.executablePath.map { executablePath in
				return builtProductsURL.URLByAppendingPathComponent(executablePath)
			}
		}
	}

	/// Attempts to determine the name of the built product's wrapper bundle.
	public var wrapperName: Result<String, CarthageError> {
		return self["WRAPPER_NAME"]
	}

	/// Attempts to determine the URL to the built product's wrapper.
	public var wrapperURL: Result<NSURL, CarthageError> {
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
	private var relativeModulesPath: Result<String?, CarthageError> {
		if let moduleName = self["PRODUCT_MODULE_NAME"].value {
			return self["CONTENTS_FOLDER_PATH"].map { contentsPath in
				return contentsPath.stringByAppendingPathComponent("Modules").stringByAppendingPathComponent(moduleName).stringByAppendingPathExtension("swiftmodule")!
			}
		} else {
			return .success(nil)
		}
	}
}

extension BuildSettings: Printable {
	public var description: String {
		return "Build settings for target \"\(target)\": \(settings)"
	}
}

/// Finds the built product for the given settings, then copies it (preserving
/// its name) into the given folder. The folder will be created if it does not
/// already exist.
///
/// Returns a signal that will send the URL after copying upon .success.
private func copyBuildProductIntoDirectory(directoryURL: NSURL, settings: BuildSettings) -> SignalProducer<NSURL, CarthageError> {
	let target = settings.wrapperName.map(directoryURL.URLByAppendingPathComponent)
	return SignalProducer(result: target &&& settings.wrapperURL)
		|> flatMap(.Merge) { (target, source) in
			return copyFramework(source, target)
		}
}

/// Attempts to merge the given executables into one fat binary, written to
/// the specified URL.
private func mergeExecutables(executableURLs: [NSURL], outputURL: NSURL) -> SignalProducer<(), CarthageError> {
	precondition(outputURL.fileURL)

	return SignalProducer(values: executableURLs)
		|> tryMap { URL -> Result<String, CarthageError> in
			if let path = URL.path {
				return .success(path)
			} else {
				return .failure(.ParseError(description: "expected file URL to built executable, got (URL)"))
			}
		}
		|> collect
		|> flatMap(.Merge) { executablePaths -> SignalProducer<TaskEvent<NSData>, CarthageError> in
			let lipoTask = TaskDescription(launchPath: "/usr/bin/xcrun", arguments: [ "lipo", "-create" ] + executablePaths + [ "-output", outputURL.path! ])

			return launchTask(lipoTask)
				|> mapError { .TaskError($0) }
		}
		|> then(.empty)
}

/// If the given source URL represents an LLVM module, copies its contents into
/// the destination module.
///
/// Sends the URL to each file after copying.
private func mergeModuleIntoModule(sourceModuleDirectoryURL: NSURL, destinationModuleDirectoryURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	precondition(sourceModuleDirectoryURL.fileURL)
	precondition(destinationModuleDirectoryURL.fileURL)

	return NSFileManager.defaultManager().carthage_enumeratorAtURL(sourceModuleDirectoryURL, includingPropertiesForKeys: [], options: NSDirectoryEnumerationOptions.SkipsSubdirectoryDescendants | NSDirectoryEnumerationOptions.SkipsHiddenFiles, catchErrors: true)
		|> flatMap(.Merge) { enumerator, URL in
			let lastComponent: String? = URL.lastPathComponent
			let destinationURL = destinationModuleDirectoryURL.URLByAppendingPathComponent(lastComponent!).URLByResolvingSymlinksInPath!

			var error: NSError?
			if NSFileManager.defaultManager().copyItemAtURL(URL, toURL: destinationURL, error: &error) {
				return SignalProducer(value: destinationURL)
			} else {
				return SignalProducer(error: .WriteFailed(destinationURL, error))
			}
		}
}

/// Determines whether the specified product type should be built automatically.
private func shouldBuildProductType(productType: ProductType) -> Bool {
	return productType == .Framework
}

/// Determines whether the given scheme should be built automatically.
private func shouldBuildScheme(buildArguments: BuildArguments, forPlatform: Platform?) -> SignalProducer<Bool, CarthageError> {
	precondition(buildArguments.scheme != nil)

	return BuildSettings.loadWithArguments(buildArguments)
		|> flatMap(.Concat) { settings -> SignalProducer<ProductType, CarthageError> in
			let productType = SignalProducer(result: settings.productType)

			if let forPlatform = forPlatform {
				return SignalProducer(result: settings.buildSDK)
					|> map { $0.platform }
					|> filter { $0 == forPlatform }
					|> flatMap(.Merge) { _ in productType }
					|> catch { _ in .empty }
			} else {
				return productType
					|> catch { _ in .empty }
			}
		}
		|> filter(shouldBuildProductType)
		// If we find any framework target, we should indeed build this scheme.
		|> map { _ in true }
		// Otherwise, nope.
		|> concat(SignalProducer(value: false))
		|> take(1)
}

/// Aggregates all of the build settings sent on the given signal, associating
/// each with the name of its target.
///
/// Returns a signal which will send the aggregated dictionary upon completion
/// of the input signal, then itself complete.
private func settingsByTarget<Error>(producer: SignalProducer<TaskEvent<BuildSettings>, Error>) -> SignalProducer<TaskEvent<[String: BuildSettings]>, Error> {
	return SignalProducer { observer, disposable in
		let settings: MutableBox<[String: BuildSettings]> = MutableBox([:])

		producer.startWithSignal { signal, signalDisposable in
			disposable += signalDisposable

			signal.observe(next: { settingsEvent in
				let transformedEvent = settingsEvent.map { settings in [ settings.target: settings ] }

				if let transformed = transformedEvent.value {
					settings.value = combineDictionaries(settings.value, transformed)
				} else {
					sendNext(observer, transformedEvent)
				}
			}, error: { error in
				sendError(observer, error)
			}, completed: {
				sendNext(observer, .Success(Box(settings.value)))
				sendCompleted(observer)
			}, interrupted: {
				sendInterrupted(observer)
			})
		}
	}
}

/// Combines the built products corresponding to the given settings, by creating
/// a fat binary of their executables and merging any Swift modules together,
/// generating a new built product in the given directory.
///
/// In order for this process to make any sense, the build products should have
/// been created from the same target, and differ only in the SDK they were
/// built for.
///
/// Upon .success, sends the URL to the merged product, then completes.
private func mergeBuildProductsIntoDirectory(firstProductSettings: BuildSettings, secondProductSettings: BuildSettings, destinationFolderURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	return copyBuildProductIntoDirectory(destinationFolderURL, firstProductSettings)
		|> flatMap(.Merge) { productURL in
			let executableURLs = (firstProductSettings.executableURL &&& secondProductSettings.executableURL).map { [ $0, $1 ] }
			let outputURL = firstProductSettings.executablePath.map(destinationFolderURL.URLByAppendingPathComponent)

			let mergeProductBinaries = SignalProducer(result: executableURLs &&& outputURL)
				|> flatMap(.Concat) { (executableURLs: [NSURL], outputURL: NSURL) -> SignalProducer<(), CarthageError> in
					return mergeExecutables(executableURLs, outputURL.URLByResolvingSymlinksInPath!)
				}

			let sourceModulesURL = SignalProducer(result: secondProductSettings.relativeModulesPath &&& secondProductSettings.builtProductsDirectoryURL)
				|> filter { $0.0 != nil }
				|> map { (modulesPath, productsURL) -> NSURL in
					return productsURL.URLByAppendingPathComponent(modulesPath!)
				}

			let destinationModulesURL = SignalProducer(result: firstProductSettings.relativeModulesPath)
				|> filter { $0 != nil }
				|> map { modulesPath -> NSURL in
					return destinationFolderURL.URLByAppendingPathComponent(modulesPath!)
				}

			let mergeProductModules = zip(sourceModulesURL, destinationModulesURL)
				|> flatMap(.Merge) { (source: NSURL, destination: NSURL) -> SignalProducer<NSURL, CarthageError> in
					return mergeModuleIntoModule(source, destination)
				}

			return mergeProductBinaries
				|> then(mergeProductModules)
				|> then(SignalProducer(value: productURL))
		}
}

/// Builds one scheme of the given project, for all supported SDKs.
///
/// Returns a signal of all standard output from `xcodebuild`, and a signal
/// which will send the URL to each product successfully built.
public func buildScheme(scheme: String, withConfiguration configuration: String, inProject project: ProjectLocator, #workingDirectoryURL: NSURL) -> SignalProducer<TaskEvent<NSURL>, CarthageError> {
	precondition(workingDirectoryURL.fileURL)

	let buildArgs = BuildArguments(project: project, scheme: scheme, configuration: configuration)
	let buildSDK = { (sdk: SDK) -> SignalProducer<TaskEvent<BuildSettings>, CarthageError> in
		var copiedArgs = buildArgs
		copiedArgs.sdk = sdk

		var buildScheme = xcodebuildTask("build", copiedArgs)
		buildScheme.workingDirectoryPath = workingDirectoryURL.path!

		return launchTask(buildScheme)
			|> mapError { .TaskError($0) }
			|> flatMapTaskEvents(.Concat) { _ in
				return BuildSettings.loadWithArguments(copiedArgs)
					|> filter { settings in
						// Only copy build products for the product types we care about.
						if let productType = settings.productType.value {
							return shouldBuildProductType(productType)
						} else {
							return false
						}
					}
			}
	}

	return BuildSettings.SDKForScheme(scheme, inProject: project)
		|> map { $0.platform }
		|> flatMap(.Concat) { (platform: Platform) in
			let folderURL = workingDirectoryURL.URLByAppendingPathComponent(platform.relativePath, isDirectory: true).URLByResolvingSymlinksInPath!

			// TODO: Generalize this further?
			switch platform.SDKs.count {
			case 1:
				return buildSDK(platform.SDKs[0])
					|> flatMapTaskEvents(.Merge) { settings in
						return copyBuildProductIntoDirectory(folderURL, settings)
					}

			case 2:
				let firstSDK = platform.SDKs[0]
				let secondSDK = platform.SDKs[1]

				return settingsByTarget(buildSDK(firstSDK))
					|> flatMap(.Concat) { settingsEvent -> SignalProducer<TaskEvent<(BuildSettings, BuildSettings)>, CarthageError> in
						switch settingsEvent {
						case let .StandardOutput(data):
							return SignalProducer(value: .StandardOutput(data))

						case let .StandardError(data):
							return SignalProducer(value: .StandardError(data))

						case let .Success(firstSettingsByTarget):
							return settingsByTarget(buildSDK(secondSDK))
								|> flatMapTaskEvents(.Concat) { (secondSettingsByTarget: [String: BuildSettings]) -> SignalProducer<(BuildSettings, BuildSettings), CarthageError> in
									assert(firstSettingsByTarget.value.count == secondSettingsByTarget.count, "Number of targets built for \(firstSDK) (\(firstSettingsByTarget.value.count)) does not match number of targets built for \(secondSDK) (\(secondSettingsByTarget.count))")

									return SignalProducer { observer, disposable in
										for (target, firstSettings) in firstSettingsByTarget.value {
											if disposable.disposed {
												break
											}

											let secondSettings = secondSettingsByTarget[target]
											assert(secondSettings != nil, "No \(secondSDK) build settings found for target \"\(target)\"")

											sendNext(observer, (firstSettings, secondSettings!))
										}

										sendCompleted(observer)
									}
								}
						}
					}
					|> flatMapTaskEvents(.Concat) { (firstSettings, secondSettings) in
						return mergeBuildProductsIntoDirectory(secondSettings, firstSettings, folderURL)
					}

			default:
				fatalError("SDK count \(platform.SDKs.count) for platform \(platform) is not supported")
			}
		}
		|> flatMapTaskEvents(.Concat) { builtProductURL in
			return createDebugInformation(builtProductURL)
				|> then(SignalProducer(value: builtProductURL))
		}
}

public func createDebugInformation(builtProductURL: NSURL) -> SignalProducer<TaskEvent<NSURL>, CarthageError> {
	let dSYMURL = builtProductURL.URLByAppendingPathExtension("dSYM")

	if let builtProduct = builtProductURL.path, dSYM = dSYMURL.path {
		let executable = builtProduct.stringByAppendingPathComponent(builtProduct.lastPathComponent.stringByDeletingPathExtension)
		let dsymutilTask = TaskDescription(launchPath: "/usr/bin/xcrun", arguments: ["dsymutil", executable, "-o", dSYM])

		return launchTask(dsymutilTask)
			|> mapError { .TaskError($0) }
			|> flatMapTaskEvents(.Concat) { _ in SignalProducer(value: dSYMURL) }
	} else {
		return .empty
	}
}

/// A producer representing a scheme to be built.
///
/// A producer of this type will send the project and scheme name when building
/// begins, then complete or error when building terminates.
public typealias BuildSchemeProducer = SignalProducer<TaskEvent<(ProjectLocator, String)>, CarthageError>

/// Attempts to build the dependency identified by the given project, then
/// places its build product into the root directory given.
///
/// Returns producers in the same format as buildInDirectory().
public func buildDependencyProject(dependency: ProjectIdentifier, rootDirectoryURL: NSURL, withConfiguration configuration: String, platform: Platform? = nil) -> SignalProducer<BuildSchemeProducer, CarthageError> {
	let rootBinariesURL = rootDirectoryURL.URLByAppendingPathComponent(CarthageBinariesFolderPath, isDirectory: true).URLByResolvingSymlinksInPath!
	let rawDependencyURL = rootDirectoryURL.URLByAppendingPathComponent(dependency.relativePath, isDirectory: true)
	let dependencyURL = rawDependencyURL.URLByResolvingSymlinksInPath!

	let schemeProducers = buildInDirectory(dependencyURL, withConfiguration: configuration, platform: platform)
	return SignalProducer.try { () -> Result<SignalProducer<BuildSchemeProducer, CarthageError>, CarthageError> in
			var error: NSError?
			if !NSFileManager.defaultManager().createDirectoryAtURL(rootBinariesURL, withIntermediateDirectories: true, attributes: nil, error: &error) {
				return .failure(.WriteFailed(rootBinariesURL, error))
			}

			// Link this dependency's Carthage/Build folder to that of the root
			// project, so it can see all products built already, and so we can
			// automatically drop this dependency's product in the right place.
			let dependencyBinariesURL = dependencyURL.URLByAppendingPathComponent(CarthageBinariesFolderPath, isDirectory: true)

			if !NSFileManager.defaultManager().removeItemAtURL(dependencyBinariesURL, error: nil) {
				let dependencyParentURL = dependencyBinariesURL.URLByDeletingLastPathComponent!
				if !NSFileManager.defaultManager().createDirectoryAtURL(dependencyParentURL, withIntermediateDirectories: true, attributes: nil, error: &error) {
					return .failure(.WriteFailed(dependencyParentURL, error))
				}
			}

			var isSymlink: AnyObject?
			if !rawDependencyURL.getResourceValue(&isSymlink, forKey: NSURLIsSymbolicLinkKey, error: &error) {
				return .failure(.ReadFailed(rawDependencyURL, error))
			}

			if isSymlink as? Bool == true {
				// Since this dependency is itself a symlink, we'll create an
				// absolute link back to the project's Build folder.
				if !NSFileManager.defaultManager().createSymbolicLinkAtURL(dependencyBinariesURL, withDestinationURL: rootBinariesURL, error: &error) {
					return .failure(.WriteFailed(dependencyBinariesURL, error))
				}
			} else {
				// The relative path to this dependency's Carthage/Build folder, from
				// the root.
				let dependencyBinariesRelativePath = dependency.relativePath.stringByAppendingPathComponent(CarthageBinariesFolderPath)
				let componentsForGettingTheHellOutOfThisRelativePath = Array(count: dependencyBinariesRelativePath.pathComponents.count - 1, repeatedValue: "..")

				// Directs a link from, e.g., /Carthage/Checkouts/ReactiveCocoa/Carthage/Build to /Carthage/Build
				let linkDestinationPath = reduce(componentsForGettingTheHellOutOfThisRelativePath, CarthageBinariesFolderPath) { trailingPath, pathComponent in
					return pathComponent.stringByAppendingPathComponent(trailingPath)
				}

				if !NSFileManager.defaultManager().createSymbolicLinkAtPath(dependencyBinariesURL.path!, withDestinationPath: linkDestinationPath, error: &error) {
					return .failure(.WriteFailed(dependencyBinariesURL, error))
				}
			}

			return .success(schemeProducers)
		}
		|> flatMap(.Merge) { schemeProducers in
			return schemeProducers
				|> mapError { error in
					switch (dependency, error) {
					case let (.GitHub(repo), .NoSharedSchemes(project, _)):
						return .NoSharedSchemes(project, repo)

					case let (.GitHub(repo), .XcodebuildListTimeout(project, _)):
						return .XcodebuildListTimeout(project, repo)

					default:
						return error
					}
				}
		}
}

/// Builds the first project or workspace found within the given directory.
///
/// Returns a signal of all standard output from `xcodebuild`, and a
/// signal-of-signals representing each scheme being built.
public func buildInDirectory(directoryURL: NSURL, withConfiguration configuration: String, platform: Platform? = nil) -> SignalProducer<BuildSchemeProducer, CarthageError> {
	precondition(directoryURL.fileURL)

	let locatorProducer = locateProjectsInDirectory(directoryURL)

	return locatorProducer
		|> filter { (project: ProjectLocator) in
			switch project {
			case .ProjectFile:
				return true

			default:
				return false
			}
		}
		|> take(1)
		|> flatMap(.Merge) { (project: ProjectLocator) -> SignalProducer<String, CarthageError> in
			return schemesInProject(project)
		}
		|> combineLatestWith(locatorProducer |> take(1))
		|> map { (scheme: String, project: ProjectLocator) -> BuildSchemeProducer in
			let buildArguments = BuildArguments(project: project, scheme: scheme, configuration: configuration)

			return shouldBuildScheme(buildArguments, platform)
				|> filter { $0 }
				|> flatMap(.Merge) { _ in
					let initialValue = (project, scheme)

					let buildProgress = buildScheme(scheme, withConfiguration: configuration, inProject: project, workingDirectoryURL: directoryURL)
						// Discard any existing Success values, since we want to
						// use our initial value instead of waiting for
						// completion.
						|> map { taskEvent in
							return taskEvent.map { _ in initialValue }
						}
						|> filter { taskEvent in taskEvent.value == nil }

					return BuildSchemeProducer(value: .Success(Box(initialValue)))
						|> concat(buildProgress)
				}
		}
}

/// Strips a framework from unexpected architectures, optionally codesigning the
/// result.
public func stripFramework(frameworkURL: NSURL, #keepingArchitectures: [String], codesigningIdentity: String? = nil) -> SignalProducer<(), CarthageError> {
	let strip = architecturesInFramework(frameworkURL)
		|> filter { !contains(keepingArchitectures, $0) }
		|> flatMap(.Concat) { stripArchitecture(frameworkURL, $0) }

	let sign = codesigningIdentity.map { codesign(frameworkURL, $0) } ?? .empty
	return strip |> concat(sign)
}

/// Copies a framework into the given folder. The folder will be created if it
/// does not already exist.
///
/// Returns a signal that will send the URL after copying upon .success.
public func copyFramework(from: NSURL, to: NSURL) -> SignalProducer<NSURL, CarthageError> {
	return SignalProducer<NSURL, CarthageError>.try {
		var error: NSError? = nil

		let manager = NSFileManager.defaultManager()

		if !manager.createDirectoryAtURL(to.URLByDeletingLastPathComponent!, withIntermediateDirectories: true, attributes: nil, error: &error) {
			return .failure(.WriteFailed(to.URLByDeletingLastPathComponent!, error))
		}

		if !manager.removeItemAtURL(to, error: &error) && error?.code != NSFileNoSuchFileError {
			return .failure(.WriteFailed(to, error))
		}

		if manager.copyItemAtURL(from, toURL: to, error: &error) {
			return .success(to)
		} else {
			return .failure(.WriteFailed(to, error))
		}
	}
}

/// Strips the given architecture from a framework.
private func stripArchitecture(frameworkURL: NSURL, architecture: String) -> SignalProducer<(), CarthageError> {
	return SignalProducer.try { () -> Result<NSURL, CarthageError> in
			return binaryURL(frameworkURL)
		}
		|> flatMap(.Merge) { binaryURL -> SignalProducer<TaskEvent<NSData>, CarthageError> in
			let lipoTask = TaskDescription(launchPath: "/usr/bin/xcrun", arguments: [ "lipo", "-remove", architecture, "-output", binaryURL.path! , binaryURL.path!])
			return launchTask(lipoTask)
				|> mapError { .TaskError($0) }
		}
		|> then(.empty)
}

/// Returns a signal of all architectures present in a given framework.
public func architecturesInFramework(frameworkURL: NSURL) -> SignalProducer<String, CarthageError> {
	return SignalProducer.try { () -> Result<NSURL, CarthageError> in
			return binaryURL(frameworkURL)
		}
		|> flatMap(.Merge) { binaryURL -> SignalProducer<String, CarthageError> in
			let lipoTask = TaskDescription(launchPath: "/usr/bin/xcrun", arguments: [ "lipo", "-info", binaryURL.path!])

			return launchTask(lipoTask)
				|> ignoreTaskData
				|> mapError { .TaskError($0) }
				|> map { NSString(data: $0, encoding: NSUTF8StringEncoding) ?? "" }
				|> flatMap(.Merge) { output -> SignalProducer<String, CarthageError> in
					let characterSet = NSMutableCharacterSet.alphanumericCharacterSet()
					characterSet.addCharactersInString(" _-")

					let scanner = NSScanner(string: output as String)

					if scanner.scanString("Architectures in the fat file:", intoString: nil) {
						// The output of "lipo -info PathToBinary" for fat files
						// looks roughly like so:
						//
						//     Architectures in the fat file: PathToBinary are: armv7 arm64
						//
						var architectures: NSString?

						scanner.scanString(binaryURL.path!, intoString: nil)
						scanner.scanString("are:", intoString: nil)
						scanner.scanCharactersFromSet(characterSet, intoString: &architectures)

						let components = architectures?
							.componentsSeparatedByString(" ")
							.map { $0 as! String }
							.filter { !$0.isEmpty }

						if let components = components {
							return SignalProducer(values: components)
						}
					}

					if scanner.scanString("Non-fat file:", intoString: nil) {
						// The output of "lipo -info PathToBinary" for thin
						// files looks roughly like so:
						//
						//     Non-fat file: PathToBinary is architecture: x86_64
						//
						var architecture: NSString?

						scanner.scanString(binaryURL.path!, intoString: nil)
						scanner.scanString("is architecture:", intoString: nil)
						scanner.scanCharactersFromSet(characterSet, intoString: &architecture)

						if let architecture = architecture {
							return SignalProducer(value: architecture as String)
						}
					}

					return SignalProducer(error: .InvalidArchitectures(description: "Could not read architectures from \(frameworkURL.path!)"))
				}
		}
}

/// Returns the URL of a binary inside a given framework.
private func binaryURL(frameworkURL: NSURL) -> Result<NSURL, CarthageError> {
	let bundle = NSBundle(path: frameworkURL.path!)

	if let binaryName = bundle?.objectForInfoDictionaryKey("CFBundleExecutable") as? String {
		return .success(frameworkURL.URLByAppendingPathComponent(binaryName))
	} else {
		return .failure(.ReadFailed(frameworkURL, nil))
	}
}

/// Signs a framework with the given codesigning identity.
private func codesign(frameworkURL: NSURL, expandedIdentity: String) -> SignalProducer<(), CarthageError> {
	let codesignTask = TaskDescription(launchPath: "/usr/bin/xcrun", arguments: [ "codesign", "--force", "--sign", expandedIdentity, "--preserve-metadata=identifier,entitlements", frameworkURL.path! ])

	return launchTask(codesignTask)
		|> mapError { .TaskError($0) }
		|> then(.empty)
}
