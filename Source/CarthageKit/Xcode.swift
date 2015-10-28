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
		return fileURL.lastPathComponent!
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

	/// The run destination to try building for.
	public var destination: String?

	/// The amount of time xcodebuild spends searching for the destination (in seconds).
	public var destinationTimeout: UInt?

	/// The build setting whether the product includes only object code for
	/// the native architecture.
	public var onlyActiveArchitecture: OnlyActiveArchitecture = .NotSpecified

	/// The build setting whether full bitcode should be embedded in the binary.
	public var bitcodeGenerationMode: BitcodeGenerationMode = .None

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

		if let destination = destination {
			args += [ "-destination", destination ]
		}

		if let destinationTimeout = destinationTimeout {
			args += [ "-destination-timeout", String(destinationTimeout) ]
		}

		args += onlyActiveArchitecture.arguments
		args += bitcodeGenerationMode.arguments

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
			return URL.typeIdentifier.flatMap { typeIdentifier in
				if (UTTypeConformsTo(typeIdentifier, "com.apple.dt.document.workspace") != 0) {
					return .success(ProjectEnumerationMatch(locator: .Workspace(URL), level: enumerator.level))
				} else if (UTTypeConformsTo(typeIdentifier, "com.apple.xcode.project") != 0) {
					return .success(ProjectEnumerationMatch(locator: .ProjectFile(URL), level: enumerator.level))
				}

				return .failure(.NotAProject(URL))
			}
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
		|> map(sorted)
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
		|> timeoutWithError(.XcodebuildListTimeout(project, nil), afterInterval: 15, onScheduler: QueueScheduler())
		|> map { (line: String) -> String in line.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceCharacterSet()) }
}

/// Represents a platform to build for.
public enum Platform: String {
	/// Mac OS X.
	case Mac = "Mac"

	/// iOS for device and simulator.
	case iOS = "iOS"

	/// Apple Watch device and simulator.
	case watchOS = "watchOS"

	/// Apple TV device and simulator.
	case tvOS = "tvOS"

	/// All supported build platforms.
	public static let supportedPlatforms: [Platform] = [ .Mac, .iOS, .watchOS, .tvOS ]

	/// The relative path at which binaries corresponding to this platform will
	/// be stored.
	public var relativePath: String {
		let subfolderName = rawValue
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

		case .tvOS:
			return [ .tvOS, .tvSimulator ]
		}
	}
}

// TODO: this won't be necessary anymore with Swift 2.
extension Platform: Printable {
	public var description: String {
		return rawValue
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

	/// tvOS, for the Apple TV device.
	case tvOS = "appletvos"

	/// tvSimulator, for the Apple TV simulator.
	case tvSimulator = "appletvsimulator"

	/// Attempts to parse an SDK name from a string returned from `xcodebuild`.
	public static func fromString(string: String) -> Result<SDK, CarthageError> {
		return Result(self(rawValue: string.lowercaseString), failWith: .ParseError(description: "unexpected SDK key \"\(string)\""))
	}

	/// The platform that this SDK targets.
	public var platform: Platform {
		switch self {
		case .iPhoneOS, .iPhoneSimulator:
			return .iOS

		case .watchOS, .watchSimulator:
			return .watchOS

		case .tvOS, .tvSimulator:
			return .tvOS

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

		case .iPhoneOS, .iPhoneSimulator, .watchOS, .watchSimulator, .tvOS, .tvSimulator:
			return [ "-sdk", rawValue ]
		}
	}
}

// TODO: this won't be necessary anymore in Swift 2.
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

		case .tvOS:
			return "tvOS"

		case .tvSimulator:
			return "tvOS Simulator"
		}
	}
}

/// Represents a build setting whether the product includes only object code
/// for the native architecture.
public enum OnlyActiveArchitecture {
	/// Not specified.
	case NotSpecified

	/// The product includes only code for the native architecture.
	case Yes

	/// The product includes code for its target's valid architectures.
	case No

	/// The arguments that should be passed to `xcodebuild` to specify the
	/// setting for this case.
	private var arguments: [String] {
		switch self {
		case .NotSpecified:
			return []

		case .Yes:
			return [ "ONLY_ACTIVE_ARCH=YES" ]

		case .No:
			return [ "ONLY_ACTIVE_ARCH=NO" ]
		}
	}
}

/// Represents a build setting whether full bitcode should be embedded in the
/// binary.
public enum BitcodeGenerationMode: String {
	/// None.
	case None = ""

	/// Only bitcode marker will be embedded.
	case Marker = "marker"

	/// Full bitcode will be embedded.
	case Bitcode = "bitcode"

	/// The arguments that should be passed to `xcodebuild` to specify the
	/// setting for this case.
	private var arguments: [String] {
		switch self {
		case .None:
			return []

		case .Marker, Bitcode:
			return [ "BITCODE_GENERATION_MODE=\(rawValue)" ]
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
		return Result(self(rawValue: string), failWith: .ParseError(description: "unexpected product type \"\(string)\""))
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

						if let result = self.targetSettingsRegex.firstMatchInString(line, options: nil, range: NSMakeRange(0, (line as NSString).length)) {
							let targetRange = result.rangeAtIndex(1)

							flushTarget()
							currentTarget = (line as NSString).substringWithRange(targetRange)
							return
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

	/// Determines which SDKs the given scheme builds for, by default.
	///
	/// If an SDK is unrecognized or could not be determined, an error will be
	/// sent on the returned signal.
	public static func SDKsForScheme(scheme: String, inProject project: ProjectLocator) -> SignalProducer<SDK, CarthageError> {
		return loadWithArguments(BuildArguments(project: project, scheme: scheme))
			|> take(1)
			|> flatMap(.Merge) { $0.buildSDKs }
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

	/// Attempts to determine the SDKs this scheme builds for.
	public var buildSDKs: SignalProducer<SDK, CarthageError> {
		let supportedPlatforms = self["SUPPORTED_PLATFORMS"]

		if let supportedPlatforms = supportedPlatforms.value {
			let platforms = split(supportedPlatforms) { $0 == " " }
			return SignalProducer<String, CarthageError>(values: platforms)
				|> map { platform in SignalProducer(result: SDK.fromString(platform)) }
				|> flatten(.Merge)
		}

		let firstBuildSDK = self["PLATFORM_NAME"].flatMap(SDK.fromString)
		return SignalProducer(result: firstBuildSDK)
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

	/// Attempts to determine whether bitcode is enabled or not.
	public var bitcodeEnabled: Result<Bool, CarthageError> {
		return self["ENABLE_BITCODE"].map { $0 == "YES" }
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
/// If this built product has any *.bcsymbolmap files they will also be copied.
///
/// Returns a signal that will send the URL after copying upon .success.
private func copyBuildProductIntoDirectory(directoryURL: NSURL, settings: BuildSettings) -> SignalProducer<NSURL, CarthageError> {
	let target = settings.wrapperName.map(directoryURL.URLByAppendingPathComponent)
	return SignalProducer(result: target &&& settings.wrapperURL)
		|> flatMap(.Merge) { (target, source) in
			return copyProduct(source, target)
		}
		|> flatMap(.Merge) { url in
			return copyBCSymbolMapsForBuildProductIntoDirectory(directoryURL, settings)
				|> then(SignalProducer(value: url))
		}
}

/// Finds any *.bcsymbolmap files for the built product and copies them into
/// the given folder. Does nothing if bitcode is disabled.
///
/// Returns a signal that will send the URL after copying for each file.
private func copyBCSymbolMapsForBuildProductIntoDirectory(directoryURL: NSURL, settings: BuildSettings) -> SignalProducer<NSURL, CarthageError> {
	if settings.bitcodeEnabled.value == true {
		let bcsymbolmapsProducer = SignalProducer(result: settings.wrapperURL)
			|> flatMap(.Merge) { wrapperURL in BCSymbolMapsForFramework(wrapperURL) }
		return copyFileURLsFromProducer(bcsymbolmapsProducer, intoDirectory: directoryURL)
	} else {
		return .empty
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
private func shouldBuildScheme(buildArguments: BuildArguments, forPlatforms: Set<Platform>) -> SignalProducer<Bool, CarthageError> {
	precondition(buildArguments.scheme != nil)

	return BuildSettings.loadWithArguments(buildArguments)
		|> flatMap(.Concat) { settings -> SignalProducer<ProductType, CarthageError> in
			let productType = SignalProducer(result: settings.productType)

			if forPlatforms.isEmpty {
				return productType
					|> catch { _ in .empty }
			} else {
				return settings.buildSDKs
					|> filter { forPlatforms.contains($0.platform) }
					|> flatMap(.Merge) { _ in productType }
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
/// Any *.bcsymbolmap files for the built products are also copied.
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
				|> then(copyBCSymbolMapsForBuildProductIntoDirectory(destinationFolderURL, secondProductSettings))
				|> then(SignalProducer(value: productURL))
		}
}


/// A callback function used to determine whether or not an SDK should be built
public typealias SDKFilterCallback = (sdks: [SDK], scheme: String, configuration: String, project: ProjectLocator) -> Result<[SDK], CarthageError>

/// Builds one scheme of the given project, for all supported SDKs.
///
/// Returns a signal of all standard output from `xcodebuild`, and a signal
/// which will send the URL to each product successfully built.
public func buildScheme(scheme: String, withConfiguration configuration: String, inProject project: ProjectLocator, #workingDirectoryURL: NSURL, sdkFilter: SDKFilterCallback = { .success($0.0) }) -> SignalProducer<TaskEvent<NSURL>, CarthageError> {
	precondition(workingDirectoryURL.fileURL)

	let buildArgs = BuildArguments(project: project, scheme: scheme, configuration: configuration)

	let buildSDK = { (sdk: SDK) -> SignalProducer<TaskEvent<BuildSettings>, CarthageError> in
		var argsForLoading = buildArgs
		argsForLoading.sdk = sdk

		var argsForBuilding = argsForLoading
		argsForBuilding.onlyActiveArchitecture = .No

		// If SDK is the iOS simulator, then also find and set a valid destination.
		// This fixes problems when the project deployment version is lower than
		// the target's one and includes simulators unsupported by the target.
		//
		// Example: Target is at 8.0, project at 7.0, xcodebuild chooses the first
		// simulator on the list, iPad 2 7.1, which is invalid for the target.
		//
		// See https://github.com/Carthage/Carthage/issues/417.
		func fetchDestination() -> SignalProducer<String?, CarthageError> {
			if sdk == .iPhoneSimulator {
				let destinationLookup = TaskDescription(launchPath: "/usr/bin/xcrun", arguments: [ "simctl", "list", "devices" ])
				return launchTask(destinationLookup)
					|> ignoreTaskData
					|> map { data in
						let string = NSString(data: data, encoding: NSStringEncoding(NSUTF8StringEncoding))!
						// The output as of Xcode 6.4 is structured text so we
						// parse it using regex. The destination will be omitted
						// altogether if parsing fails. Xcode 7.0 beta 4 added a
						// JSON output option as `xcrun simctl list devices --json`
						// so this can be switched once 7.0 becomes a requirement.
						let regex = NSRegularExpression(pattern: "-- iOS [0-9.]+ --\\n.*?\\(([0-9A-Z]{8}-([0-9A-Z]{4}-){3}[0-9A-Z]{12})\\)", options: nil, error: nil)!
						let lastDeviceResult = regex.matchesInString(string as String, options: nil, range: NSRange(location: 0, length: string.length)).last as? NSTextCheckingResult
						return lastDeviceResult.map { result in
							// We use the ID here instead of the name as it's guaranteed to be unique, the name isn't.
							let deviceID = string.substringWithRange(result.rangeAtIndex(1))
							return "platform=iOS Simulator,id=\(deviceID)"
						}
					}
					|> mapError { .TaskError($0) }
			}
			return SignalProducer(value: nil)
		}

		return fetchDestination()
			|> flatMap(.Concat) { destination -> SignalProducer<TaskEvent<BuildSettings>, CarthageError> in
				if let destination = destination {
					argsForBuilding.destination = destination
					// Also set the destination lookup timeout. Since we're building
					// for the simulator the lookup shouldn't take more than a
					// fraction of a second, but we set to 3 just to be safe.
					argsForBuilding.destinationTimeout = 3
				}

				return BuildSettings.loadWithArguments(argsForLoading)
					|> filter { settings in
						// Only copy build products for the product types we care about.
						if let productType = settings.productType.value {
							return shouldBuildProductType(productType)
						} else {
							return false
						}
					}
					|> flatMap(.Concat) { settings -> SignalProducer<TaskEvent<BuildSettings>, CarthageError> in
						if settings.bitcodeEnabled.value == true {
							argsForBuilding.bitcodeGenerationMode = .Bitcode
						}

						var buildScheme = xcodebuildTask("build", argsForBuilding)
						buildScheme.workingDirectoryPath = workingDirectoryURL.path!

						return launchTask(buildScheme)
							|> map { taskEvent in
								taskEvent.map { _ in settings }
							}
							|> mapError { .TaskError($0) }
					}
			}
	}

	return BuildSettings.SDKsForScheme(scheme, inProject: project)
		|> reduce([:]) { (var sdksByPlatform: [Platform: [SDK]], sdk: SDK) in
			let platform = sdk.platform

			if var sdks = sdksByPlatform[platform] {
				sdks.append(sdk)
				sdksByPlatform.updateValue(sdks, forKey: platform)
			} else {
				sdksByPlatform[platform] = [ sdk ]
			}

			return sdksByPlatform
		}
		|> flatMap(.Concat) { sdksByPlatform -> SignalProducer<(Platform, [SDK]), CarthageError> in
			if sdksByPlatform.isEmpty {
				fatalError("No SDKs found for scheme \(scheme)")
			}

			let values = map(sdksByPlatform) { ($0, $1) }
			return SignalProducer(values: values)
		}
		|> flatMap(.Concat) { platform, sdks -> SignalProducer<(Platform, [SDK]), CarthageError> in
			let filterResult = sdkFilter(sdks: sdks, scheme: scheme, configuration: configuration, project: project)
			return SignalProducer(result: filterResult.map { (platform, $0) })
		}
		|> filter { _, sdks in
			return !sdks.isEmpty
		}
		|> flatMap(.Concat) { platform, sdks in
			let folderURL = workingDirectoryURL.URLByAppendingPathComponent(platform.relativePath, isDirectory: true).URLByResolvingSymlinksInPath!

			// TODO: Generalize this further?
			switch sdks.count {
			case 1:
				return buildSDK(sdks[0])
					|> flatMapTaskEvents(.Merge) { settings in
						return copyBuildProductIntoDirectory(folderURL, settings)
					}

			case 2:
				let firstSDK = sdks[0]
				let secondSDK = sdks[1]

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
				fatalError("SDK count \(sdks.count) in scheme \(scheme) is not supported")
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
public func buildDependencyProject(dependency: ProjectIdentifier, rootDirectoryURL: NSURL, withConfiguration configuration: String, platforms: Set<Platform> = [], sdkFilter: SDKFilterCallback = { .success($0.0) }) -> SignalProducer<BuildSchemeProducer, CarthageError> {
	let rootBinariesURL = rootDirectoryURL.URLByAppendingPathComponent(CarthageBinariesFolderPath, isDirectory: true).URLByResolvingSymlinksInPath!
	let rawDependencyURL = rootDirectoryURL.URLByAppendingPathComponent(dependency.relativePath, isDirectory: true)
	let dependencyURL = rawDependencyURL.URLByResolvingSymlinksInPath!

	let schemeProducers = buildInDirectory(dependencyURL, withConfiguration: configuration, platforms: platforms, sdkFilter: sdkFilter)
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
					case let (_, .NoSharedFrameworkSchemes(_, platforms)):
						return .NoSharedFrameworkSchemes(dependency, platforms)

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


public func getSecuritySigningIdentities() -> SignalProducer<String, CarthageError> {
	let securityTask = TaskDescription(launchPath: "/usr/bin/security", arguments: [ "find-identity", "-v", "-p", "codesigning" ])
	
	return launchTask(securityTask)
		|> ignoreTaskData
		|> mapError { .TaskError($0) }
		|> map { (data: NSData) -> String in
			return NSString(data: data, encoding: NSStringEncoding(NSUTF8StringEncoding))! as String
		}
		|> flatMap(.Merge) { (string: String) -> SignalProducer<String, CarthageError> in
			return string.linesProducer |> promoteErrors(CarthageError.self)
		}
}

public typealias CodeSigningIdentity = String

/// Matches lines of the form:
///
/// '  1) 4E8D512C8480AAC679947D6E50190AE97AB3E825 "3rd Party Mac Developer Application: Developer Name (DUCNFCN445)"'
/// '  2) 8B0EBBAE7E7230BB6AF5D69CA09B769663BC844D "Mac Developer: Developer Name (DUCNFCN445)"'
private let signingIdentitiesRegex = NSRegularExpression(pattern:
	(
		"\\s*"               + // Leading spaces
		"\\d+\\)\\s+"        + // Number of identity
		"([A-F0-9]+)\\s+"    + // Hash (e.g. 4E8D512C8480AAC67995D69CA09B769663BC844D)
		"\"(.+):\\s"         + // Identity type (e.g. Mac Developer, iPhone Developer)
		"(.+)\\s\\("         + // Developer Name
		"([A-Z0-9]+)\\)\"\\s*" // Developer ID (e.g. DUCNFCN445)
	),
 options: nil, error: nil)!

public func parseSecuritySigningIdentities(securityIdentities: SignalProducer<String, CarthageError> = getSecuritySigningIdentities()) -> SignalProducer<CodeSigningIdentity, CarthageError> {
	return securityIdentities
		|> map { (identityLine: String) -> CodeSigningIdentity? in
			let fullRange = NSMakeRange(0, count(identityLine))
			
			if let match = signingIdentitiesRegex.matchesInString(identityLine, options: nil, range: fullRange).first as? NSTextCheckingResult {
				let id = identityLine as NSString
				
				return id.substringWithRange(match.rangeAtIndex(2))
			}
			
			return nil
		}
		|> ignoreNil
}

/// Builds the first project or workspace found within the given directory which
/// has at least one shared framework scheme.
///
/// Returns a signal of all standard output from `xcodebuild`, and a
/// signal-of-signals representing each scheme being built.
public func buildInDirectory(directoryURL: NSURL, withConfiguration configuration: String, platforms: Set<Platform> = [], sdkFilter: SDKFilterCallback = { .success($0.0) }) -> SignalProducer<BuildSchemeProducer, CarthageError> {
	precondition(directoryURL.fileURL)

	return SignalProducer { observer, disposable in
		// Use SignalProducer.buffer() to avoid enumerating the given directory
		// multiple times.
		let (locatorBuffer, locatorObserver) = SignalProducer<(ProjectLocator, [String]), CarthageError>.buffer()

		locateProjectsInDirectory(directoryURL)
			|> flatMap(.Concat) { (project: ProjectLocator) -> SignalProducer<(ProjectLocator, [String]), CarthageError> in
				return schemesInProject(project)
					|> flatMap(.Merge) { scheme -> SignalProducer<String, CarthageError> in
						let buildArguments = BuildArguments(project: project, scheme: scheme, configuration: configuration)

						return shouldBuildScheme(buildArguments, platforms)
							|> filter { $0 }
							|> map { _ in scheme }
					}
					|> collect
					|> catch { error in
						switch error {
						case .NoSharedSchemes:
							return SignalProducer(value: [])

						default:
							return SignalProducer(error: error)
						}
					}
					|> map { (project, $0) }
			}
			|> startWithSignal { signal, signalDisposable in
				disposable += signalDisposable
				signal.observe(locatorObserver)
			}

		locatorBuffer
			|> collect
			// Allow dependencies which have no projects, not to error out with
			// `.NoSharedFrameworkSchemes`.
			|> filter { projects in !projects.isEmpty }
			|> flatMap(.Merge) { (projects: [(ProjectLocator, [String])]) -> SignalProducer<(String, ProjectLocator), CarthageError> in
				return SignalProducer(values: projects)
					|> map { (project: ProjectLocator, schemes: [String]) in
						// Only look for schemes that actually reside in the project
						let containedSchemes = schemes.filter { (scheme: String) -> Bool in
							if let schemePath = project.fileURL.URLByAppendingPathComponent("xcshareddata/xcschemes/\(scheme).xcscheme").path {
								return NSFileManager.defaultManager().fileExistsAtPath(schemePath)
							}
							return false
						}
						return (project, containedSchemes)
					}
					|> filter { (project: ProjectLocator, schemes: [String]) in
						switch project {
						case .ProjectFile where !schemes.isEmpty:
							return true

						default:
							return false
						}
					}
					|> concat(SignalProducer(error: .NoSharedFrameworkSchemes(.Git(GitURL(directoryURL.path!)), platforms)))
					|> take(1)
					|> flatMap(.Merge) { project, schemes in SignalProducer(values: schemes.map { ($0, project) }) }
			}
			|> flatMap(.Merge) { scheme, project -> SignalProducer<(String, ProjectLocator), CarthageError> in
				return locatorBuffer
					// This scheduler hop is required to avoid disallowed recursive signals.
					// See https://github.com/ReactiveCocoa/ReactiveCocoa/pull/2042.
					|> startOn(QueueScheduler(name: "org.carthage.CarthageKit.Xcode.buildInDirectory"))
					// Pick up the first workspace which can build the scheme.
					|> filter { project, schemes in
						switch project {
						case .Workspace where contains(schemes, scheme):
							return true

						default:
							return false
						}
					}
					// If there is no appropriate workspace, use the project in
					// which the scheme is defined instead.
					|> concat(SignalProducer(value: (project, [])))
					|> take(1)
					|> map { project, _ in (scheme, project) }
			}
			|> map { (scheme: String, project: ProjectLocator) -> BuildSchemeProducer in
				let initialValue = (project, scheme)

				let wrappedSDKFilter: SDKFilterCallback = { sdks, scheme, configuration, project in
					let filteredSDKs: [SDK]
					if platforms.isEmpty {
						filteredSDKs = sdks
					} else {
						filteredSDKs = sdks.filter { platforms.contains($0.platform) }
					}

					return sdkFilter(sdks: filteredSDKs, scheme: scheme, configuration: configuration, project: project)
				}

				let buildProgress = buildScheme(scheme, withConfiguration: configuration, inProject: project, workingDirectoryURL: directoryURL, sdkFilter: wrappedSDKFilter)
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
			|> startWithSignal { signal, signalDisposable in
				disposable += signalDisposable
				signal.observe(observer)
			}
	}
}

/// Strips a framework from unexpected architectures, optionally codesigning the
/// result.
public func stripFramework(frameworkURL: NSURL, #keepingArchitectures: [String], codesigningIdentity: String? = nil) -> SignalProducer<(), CarthageError> {
	let stripArchitectures = architecturesInFramework(frameworkURL)
		|> filter { !contains(keepingArchitectures, $0) }
		|> flatMap(.Concat) { stripArchitecture(frameworkURL, $0) }

	// Xcode doesn't copy `Modules` directory at all.
	let stripModules = stripModulesDirectory(frameworkURL)

	let sign = codesigningIdentity.map { codesign(frameworkURL, $0) } ?? .empty

	return stripArchitectures
		|> concat(stripModules)
		|> concat(sign)
}

/// Copies a product into the given folder. The folder will be created if it
/// does not already exist.
///
/// Returns a signal that will send the URL after copying upon .success.
public func copyProduct(from: NSURL, to: NSURL) -> SignalProducer<NSURL, CarthageError> {
	return SignalProducer<NSURL, CarthageError>.try {
		var error: NSError? = nil

		let manager = NSFileManager.defaultManager()

		if !manager.createDirectoryAtURL(to.URLByDeletingLastPathComponent!, withIntermediateDirectories: true, attributes: nil, error: &error)
			// Although the method's documentation says: “YES if createIntermediates
			// is set and the directory already exists)”, it seems to rarely
			// returns NO and NSFileWriteFileExistsError error. So we should
			// ignore that specific error.
			//
			// See https://github.com/Carthage/Carthage/issues/591.
			&& error?.code != NSFileWriteFileExistsError
		{
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

/// Copies existing files sent from the given producer into the given directory.
///
/// Returns a producer that will send locations where the copied files are.
public func copyFileURLsFromProducer(producer: SignalProducer<NSURL, CarthageError>, intoDirectory directoryURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	return producer
		|> filter { fileURL in fileURL.checkResourceIsReachableAndReturnError(nil) }
		|> flatMap(.Merge) { fileURL in
			let fileName = fileURL.lastPathComponent!
			let destinationURL = directoryURL.URLByAppendingPathComponent(fileName, isDirectory: false)
			let resolvedDestinationURL = destinationURL.URLByResolvingSymlinksInPath!

			return copyProduct(fileURL, resolvedDestinationURL)
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

/// Strips `Modules` directory from the given framework.
public func stripModulesDirectory(frameworkURL: NSURL) -> SignalProducer<(), CarthageError> {
	return SignalProducer.try {
		let modulesDirectoryURL = frameworkURL.URLByAppendingPathComponent("Modules", isDirectory: true)

		var isDirectory: ObjCBool = false
		if !NSFileManager.defaultManager().fileExistsAtPath(modulesDirectoryURL.path!, isDirectory: &isDirectory) || !isDirectory {
			return .success(())
		}

		var error: NSError? = nil
		if !NSFileManager.defaultManager().removeItemAtURL(modulesDirectoryURL, error: &error) {
			return .failure(.WriteFailed(modulesDirectoryURL, error))
		}

		return .success(())
	}
}

/// Sends a set of UUIDs for each architecture present in the given framework.
public func UUIDsForFramework(frameworkURL: NSURL) -> SignalProducer<Set<NSUUID>, CarthageError> {
	return SignalProducer.try { () -> Result<NSURL, CarthageError> in
			return binaryURL(frameworkURL)
		}
		|> flatMap(.Merge, UUIDsFromDwarfdump)
}

/// Sends a set of UUIDs for each architecture present in the given dSYM.
public func UUIDsForDSYM(dSYMURL: NSURL) -> SignalProducer<Set<NSUUID>, CarthageError> {
	return UUIDsFromDwarfdump(dSYMURL)
}

/// Sends an NSURL for each bcsymbolmap file for the given framework.
/// The files do not necessarily exist on disk.
///
/// The returned URLs are relative to the parent directory of the framework.
public func BCSymbolMapsForFramework(frameworkURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	let directoryURL = frameworkURL.URLByDeletingLastPathComponent!
	return UUIDsForFramework(frameworkURL)
		|> flatMap(.Merge) { UUIDs in SignalProducer(values: UUIDs) }
		|> map { UUID in
			return directoryURL.URLByAppendingPathComponent(UUID.UUIDString, isDirectory: false).URLByAppendingPathExtension("bcsymbolmap")
		}
}

/// Sends a set of UUIDs for each architecture present in the given URL.
private func UUIDsFromDwarfdump(URL: NSURL) -> SignalProducer<Set<NSUUID>, CarthageError> {
	let dwarfdumpTask = TaskDescription(launchPath: "/usr/bin/xcrun", arguments: [ "dwarfdump", "--uuid", URL.path! ])

	return launchTask(dwarfdumpTask)
		|> ignoreTaskData
		|> mapError { .TaskError($0) }
		|> map { NSString(data: $0, encoding: NSUTF8StringEncoding) ?? "" }
		|> flatMap(.Merge) { output -> SignalProducer<Set<NSUUID>, CarthageError> in
			// UUIDs are letters, decimals, or hyphens.
			let UUIDCharacterSet = NSMutableCharacterSet()
			UUIDCharacterSet.formUnionWithCharacterSet(NSCharacterSet.letterCharacterSet())
			UUIDCharacterSet.formUnionWithCharacterSet(NSCharacterSet.decimalDigitCharacterSet())
			UUIDCharacterSet.formUnionWithCharacterSet(NSCharacterSet(charactersInString: "-"))

			let scanner = NSScanner(string: output as String)
			var UUIDs = Set<NSUUID>()

			// The output of dwarfdump is a series of lines formatted as follows
			// for each architecture:
			//
			//     UUID: <UUID> (<Architecture>) <PathToBinary>
			//
			while !scanner.atEnd {
				scanner.scanString("UUID: ", intoString: nil)

				var UUIDString: NSString?
				scanner.scanCharactersFromSet(UUIDCharacterSet, intoString: &UUIDString)

				if let UUIDString = UUIDString as? String, let UUID = NSUUID(UUIDString: UUIDString) {
					UUIDs.insert(UUID)
				}

				// Scan until a newline or end of file.
				scanner.scanUpToCharactersFromSet(NSCharacterSet.newlineCharacterSet(), intoString: nil)
			}

			if !UUIDs.isEmpty {
				return SignalProducer(value: UUIDs)
			} else {
				return SignalProducer(error: .InvalidUUIDs(description: "Could not parse UUIDs using dwarfdump from \(URL.path!)"))
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
