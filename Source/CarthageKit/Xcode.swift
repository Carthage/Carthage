//
//  Xcode.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-11.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

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
	case (.Workspace, .ProjectFile):
		return true

	case (.ProjectFile, .Workspace):
		return false

	default:
		return lhs.fileURL.path!.characters.lexicographicalCompare(rhs.fileURL.path!.characters)
	}
}

extension ProjectLocator: CustomStringConvertible {
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

extension BuildArguments: CustomStringConvertible {
	public var description: String {
		return arguments.joinWithSeparator(" ")
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
				if (UTTypeConformsTo(typeIdentifier, "com.apple.dt.document.workspace")) {
					return .Success(ProjectEnumerationMatch(locator: .Workspace(URL), level: enumerator.level))
				} else if (UTTypeConformsTo(typeIdentifier, "com.apple.xcode.project")) {
					return .Success(ProjectEnumerationMatch(locator: .ProjectFile(URL), level: enumerator.level))
				}

				return .Failure(.NotAProject(URL))
			}
		}

		return .Failure(.ReadFailed(URL, nil))
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
	let enumerationOptions: NSDirectoryEnumerationOptions = [ .SkipsHiddenFiles, .SkipsPackageDescendants ]

	return NSFileManager.defaultManager().carthage_enumeratorAtURL(directoryURL.URLByResolvingSymlinksInPath!, includingPropertiesForKeys: [ NSURLTypeIdentifierKey ], options: enumerationOptions, catchErrors: true)
		.reduce([]) { (var matches: [ProjectEnumerationMatch], tuple) -> [ProjectEnumerationMatch] in
			let (enumerator, URL) = tuple
			if let match = ProjectEnumerationMatch.matchURL(URL, fromEnumerator: enumerator).value {
				matches.append(match)
			}

			return matches
		}
		.map { $0.sort() }
		.flatMap(.Merge) { matches -> SignalProducer<ProjectEnumerationMatch, CarthageError> in
			return SignalProducer(values: matches)
		}
		.map { (match: ProjectEnumerationMatch) -> ProjectLocator in
			return match.locator
		}
}

/// Creates a task description for executing `xcodebuild` with the given
/// arguments.
public func xcodebuildTask(task: String, _ buildArguments: BuildArguments) -> TaskDescription {
	return TaskDescription(launchPath: "/usr/bin/xcrun", arguments: buildArguments.arguments + [ task ])
}

/// Sends each scheme found in the given project.
public func schemesInProject(project: ProjectLocator) -> SignalProducer<String, CarthageError> {
	let task = xcodebuildTask("-list", BuildArguments(project: project))

	return launchTask(task)
		.ignoreTaskData()
		.mapError(CarthageError.TaskError)
		.map { (data: NSData) -> String in
			return NSString(data: data, encoding: NSStringEncoding(NSUTF8StringEncoding))! as String
		}
		.flatMap(.Merge) { (string: String) -> SignalProducer<String, CarthageError> in
			return string.linesProducer.promoteErrors(CarthageError.self)
		}
		.flatMap(.Merge) { line -> SignalProducer<String, CarthageError> in
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
		.skipWhile { line in !line.hasSuffix("Schemes:") }
		.skip(1)
		.takeWhile { line in !line.isEmpty }
		// xcodebuild has a bug where xcodebuild -list can sometimes hang
		// indefinitely on projects that don't share any schemes, so
		// automatically bail out if it looks like that's happening.
		.timeoutWithError(.XcodebuildListTimeout(project, nil), afterInterval: 15, onScheduler: QueueScheduler(queue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)))
		.map { (line: String) -> String in line.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceCharacterSet()) }
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
		return (CarthageBinariesFolderPath as NSString).stringByAppendingPathComponent(subfolderName)
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
extension Platform: CustomStringConvertible {
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
		return Result(self.init(rawValue: string.lowercaseString), failWith: .ParseError(description: "unexpected SDK key \"\(string)\""))
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
extension SDK: CustomStringConvertible {
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
		return Result(self.init(rawValue: string), failWith: .ParseError(description: "unexpected product type \"\(string)\""))
	}
}

/// Describes the type of Mach-O files.
/// See https://developer.apple.com/library/mac/documentation/DeveloperTools/Reference/XcodeBuildSettingRef/1-Build_Setting_Reference/build_setting_ref.html#//apple_ref/doc/uid/TP40003931-CH3-SW73.
public enum MachOType: String {
	/// Executable binary.
	case Executable = "mh_executable"

	/// Bundle binary.
	case Bundle = "mh_bundle"

	/// Relocatable object file.
	case Object = "mh_object"

	/// Dynamic library binary.
	case Dylib = "mh_dylib"

	/// Static library binary.
	case Staticlib = "staticlib"

	/// Attempts to parse a Mach-O type from a string returned from `xcodebuild`.
	public static func fromString(string: String) -> Result<MachOType, CarthageError> {
		return Result(self.init(rawValue: string), failWith: .ParseError(description: "unexpected Mach-O type \"\(string)\""))
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
	private static let targetSettingsRegex = try! NSRegularExpression(pattern: "^Build settings for action (?:\\S+) and target \\\"?([^\":]+)\\\"?:$", options: [ .CaseInsensitive, .AnchorsMatchLines ])

	/// Invokes `xcodebuild` to retrieve build settings for the given build
	/// arguments.
	///
	/// Upon .success, sends one BuildSettings value for each target included in
	/// the referenced scheme.
	public static func loadWithArguments(arguments: BuildArguments) -> SignalProducer<BuildSettings, CarthageError> {
		let task = xcodebuildTask("-showBuildSettings", arguments)

		return launchTask(task)
			.ignoreTaskData()
			.mapError(CarthageError.TaskError)
			.map { (data: NSData) -> String in
				return NSString(data: data, encoding: NSStringEncoding(NSUTF8StringEncoding))! as String
			}
			.flatMap(.Merge) { (string: String) -> SignalProducer<BuildSettings, CarthageError> in
				return SignalProducer { observer, disposable in
					var currentSettings: [String: String] = [:]
					var currentTarget: String?

					let flushTarget = { () -> () in
						if let currentTarget = currentTarget {
							let buildSettings = self.init(target: currentTarget, settings: currentSettings)
							observer.sendNext(buildSettings)
						}

						currentTarget = nil
						currentSettings = [:]
					}

					(string as NSString).enumerateLinesUsingBlock { (line, stop) in
						if disposable.disposed {
							stop.memory = true
							return
						}

						if let result = self.targetSettingsRegex.firstMatchInString(line, options: [], range: NSMakeRange(0, (line as NSString).length)) {
							let targetRange = result.rangeAtIndex(1)

							flushTarget()
							currentTarget = (line as NSString).substringWithRange(targetRange)
							return
						}

						let components = line.characters.split(1) { $0 == "=" }.map(String.init)
						let trimSet = NSCharacterSet.whitespaceAndNewlineCharacterSet()

						if components.count == 2 {
							currentSettings[components[0].stringByTrimmingCharactersInSet(trimSet)] = components[1].stringByTrimmingCharactersInSet(trimSet)
						}
					}

					flushTarget()
					observer.sendCompleted()
				}
			}
	}

	/// Determines which SDKs the given scheme builds for, by default.
	///
	/// If an SDK is unrecognized or could not be determined, an error will be
	/// sent on the returned signal.
	public static func SDKsForScheme(scheme: String, inProject project: ProjectLocator) -> SignalProducer<SDK, CarthageError> {
		return loadWithArguments(BuildArguments(project: project, scheme: scheme))
			.take(1)
			.flatMap(.Merge) { $0.buildSDKs }
	}

	/// Returns the value for the given build setting, or an error if it could
	/// not be determined.
	public subscript(key: String) -> Result<String, CarthageError> {
		if let value = settings[key] {
			return .Success(value)
		} else {
			return .Failure(.MissingBuildSetting(key))
		}
	}

	/// Attempts to determine the SDKs this scheme builds for.
	public var buildSDKs: SignalProducer<SDK, CarthageError> {
		let supportedPlatforms = self["SUPPORTED_PLATFORMS"]

		if let supportedPlatforms = supportedPlatforms.value {
			let platforms = supportedPlatforms.characters.split { $0 == " " }.map(String.init)
			return SignalProducer<String, CarthageError>(values: platforms)
				.map { platform in SignalProducer(result: SDK.fromString(platform)) }
				.flatten(.Merge)
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

	public var machOType: Result<MachOType, CarthageError> {
		return self["MACH_O_TYPE"].flatMap { typeString in
			return MachOType.fromString(typeString)
		}
	}

	/// Attempts to determine the URL to the built products directory.
	public var builtProductsDirectoryURL: Result<NSURL, CarthageError> {
		return self["BUILT_PRODUCTS_DIR"].map { productsDir in
			return NSURL.fileURLWithPath(productsDir, isDirectory: true)
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
				let path1 = (contentsPath as NSString).stringByAppendingPathComponent("Modules")
				let path2 = (path1 as NSString).stringByAppendingPathComponent(moduleName)
				return (path2 as NSString).stringByAppendingPathExtension("swiftmodule")
			}
		} else {
			return .Success(nil)
		}
	}
}

extension BuildSettings: CustomStringConvertible {
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
private func copyBuildProductIntoDirectory(directoryURL: NSURL, _ settings: BuildSettings) -> SignalProducer<NSURL, CarthageError> {
	let target = settings.wrapperName.map(directoryURL.URLByAppendingPathComponent)
	return SignalProducer(result: target &&& settings.wrapperURL)
		.flatMap(.Merge) { (target, source) in
			return copyProduct(source, target)
		}
		.flatMap(.Merge) { url in
			return copyBCSymbolMapsForBuildProductIntoDirectory(directoryURL, settings)
				.then(SignalProducer(value: url))
		}
}

/// Finds any *.bcsymbolmap files for the built product and copies them into
/// the given folder. Does nothing if bitcode is disabled.
///
/// Returns a signal that will send the URL after copying for each file.
private func copyBCSymbolMapsForBuildProductIntoDirectory(directoryURL: NSURL, _ settings: BuildSettings) -> SignalProducer<NSURL, CarthageError> {
	if settings.bitcodeEnabled.value == true {
		return SignalProducer(result: settings.wrapperURL)
			.flatMap(.Merge) { wrapperURL in BCSymbolMapsForFramework(wrapperURL) }
			.copyFileURLsIntoDirectory(directoryURL)
	} else {
		return .empty
	}
}

/// Attempts to merge the given executables into one fat binary, written to
/// the specified URL.
private func mergeExecutables(executableURLs: [NSURL], _ outputURL: NSURL) -> SignalProducer<(), CarthageError> {
	precondition(outputURL.fileURL)

	return SignalProducer(values: executableURLs)
		.attemptMap { URL -> Result<String, CarthageError> in
			if let path = URL.path {
				return .Success(path)
			} else {
				return .Failure(.ParseError(description: "expected file URL to built executable, got (URL)"))
			}
		}
		.collect()
		.flatMap(.Merge) { executablePaths -> SignalProducer<TaskEvent<NSData>, CarthageError> in
			let lipoTask = TaskDescription(launchPath: "/usr/bin/xcrun", arguments: [ "lipo", "-create" ] + executablePaths + [ "-output", outputURL.path! ])

			return launchTask(lipoTask)
				.mapError(CarthageError.TaskError)
		}
		.then(.empty)
}

/// If the given source URL represents an LLVM module, copies its contents into
/// the destination module.
///
/// Sends the URL to each file after copying.
private func mergeModuleIntoModule(sourceModuleDirectoryURL: NSURL, _ destinationModuleDirectoryURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	precondition(sourceModuleDirectoryURL.fileURL)
	precondition(destinationModuleDirectoryURL.fileURL)

	return NSFileManager.defaultManager().carthage_enumeratorAtURL(sourceModuleDirectoryURL, includingPropertiesForKeys: [], options: [ .SkipsSubdirectoryDescendants, .SkipsHiddenFiles ], catchErrors: true)
		.flatMap(.Merge) { enumerator, URL -> SignalProducer<NSURL, CarthageError> in
			let lastComponent: String? = URL.lastPathComponent
			let destinationURL = destinationModuleDirectoryURL.URLByAppendingPathComponent(lastComponent!).URLByResolvingSymlinksInPath!

			do {
				try NSFileManager.defaultManager().copyItemAtURL(URL, toURL: destinationURL)
				return SignalProducer(value: destinationURL)
			} catch let error as NSError {
				return SignalProducer(error: .WriteFailed(destinationURL, error))
			}
		}
}

/// Determines whether the specified product type should be built automatically.
private func shouldBuildProductType(productType: ProductType) -> Bool {
	return productType == .Framework
}

/// Determines whether the specified Mach-O type should be built automatically.
private func shouldBuildMachOType(machOType: MachOType) -> Bool {
	return machOType == .Dylib
}

/// Determines whether the given scheme should be built automatically.
private func shouldBuildScheme(buildArguments: BuildArguments, _ forPlatforms: Set<Platform>) -> SignalProducer<Bool, CarthageError> {
	precondition(buildArguments.scheme != nil)

	return BuildSettings.loadWithArguments(buildArguments)
		.flatMap(.Concat) { settings -> SignalProducer<(ProductType, MachOType), CarthageError> in
			let typePair = SignalProducer(result: settings.productType &&& settings.machOType)

			if forPlatforms.isEmpty {
				return typePair
					.flatMapError { _ in .empty }
			} else {
				return settings.buildSDKs
					.filter { forPlatforms.contains($0.platform) }
					.flatMap(.Merge) { _ in typePair }
					.flatMapError { _ in .empty }
			}
		}
		.filter { shouldBuildProductType($0) && shouldBuildMachOType($1) }
		// If we find any dynamic framework target, we should indeed build this scheme.
		.map { _ in true }
		// Otherwise, nope.
		.concat(SignalProducer(value: false))
		.take(1)
}

/// Aggregates all of the build settings sent on the given signal, associating
/// each with the name of its target.
///
/// Returns a signal which will send the aggregated dictionary upon completion
/// of the input signal, then itself complete.
private func settingsByTarget<Error>(producer: SignalProducer<TaskEvent<BuildSettings>, Error>) -> SignalProducer<TaskEvent<[String: BuildSettings]>, Error> {
	return SignalProducer { observer, disposable in
		var settings: [String: BuildSettings] = [:]

		producer.startWithSignal { signal, signalDisposable in
			disposable += signalDisposable

			signal.observe { event in
				switch event {
				case let .Next(settingsEvent):
					let transformedEvent = settingsEvent.map { settings in [ settings.target: settings ] }

					if let transformed = transformedEvent.value {
						settings = combineDictionaries(settings, rhs: transformed)
					} else {
						observer.sendNext(transformedEvent)
					}

				case let .Failed(error):
					observer.sendFailed(error)

				case .Completed:
					observer.sendNext(.Success(settings))
					observer.sendCompleted()

				case .Interrupted:
					observer.sendInterrupted()
				}
			}
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
private func mergeBuildProductsIntoDirectory(firstProductSettings: BuildSettings, _ secondProductSettings: BuildSettings, _ destinationFolderURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	return copyBuildProductIntoDirectory(destinationFolderURL, firstProductSettings)
		.flatMap(.Merge) { productURL -> SignalProducer<NSURL, CarthageError> in
			let executableURLs = (firstProductSettings.executableURL &&& secondProductSettings.executableURL).map { [ $0, $1 ] }
			let outputURL = firstProductSettings.executablePath.map(destinationFolderURL.URLByAppendingPathComponent)

			let mergeProductBinaries = SignalProducer(result: executableURLs &&& outputURL)
				.flatMap(.Concat) { (executableURLs: [NSURL], outputURL: NSURL) -> SignalProducer<(), CarthageError> in
					return mergeExecutables(executableURLs, outputURL.URLByResolvingSymlinksInPath!)
				}

			let sourceModulesURL = SignalProducer(result: secondProductSettings.relativeModulesPath &&& secondProductSettings.builtProductsDirectoryURL)
				.filter { $0.0 != nil }
				.map { (modulesPath, productsURL) -> NSURL in
					return productsURL.URLByAppendingPathComponent(modulesPath!)
				}

			let destinationModulesURL = SignalProducer(result: firstProductSettings.relativeModulesPath)
				.filter { $0 != nil }
				.map { modulesPath -> NSURL in
					return destinationFolderURL.URLByAppendingPathComponent(modulesPath!)
				}

			let mergeProductModules = zip(sourceModulesURL, destinationModulesURL)
				.flatMap(.Merge) { (source: NSURL, destination: NSURL) -> SignalProducer<NSURL, CarthageError> in
					return mergeModuleIntoModule(source, destination)
				}

			return mergeProductBinaries
				.then(mergeProductModules)
				.then(copyBCSymbolMapsForBuildProductIntoDirectory(destinationFolderURL, secondProductSettings))
				.then(SignalProducer(value: productURL))
		}
}


/// A callback function used to determine whether or not an SDK should be built
public typealias SDKFilterCallback = (sdks: [SDK], scheme: String, configuration: String, project: ProjectLocator) -> Result<[SDK], CarthageError>

/// Builds one scheme of the given project, for all supported SDKs.
///
/// Returns a signal of all standard output from `xcodebuild`, and a signal
/// which will send the URL to each product successfully built.
public func buildScheme(scheme: String, withConfiguration configuration: String, inProject project: ProjectLocator, workingDirectoryURL: NSURL, sdkFilter: SDKFilterCallback = { .Success($0.0) }) -> SignalProducer<TaskEvent<NSURL>, CarthageError> {
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
					.ignoreTaskData()
					.map { data in
						let string = NSString(data: data, encoding: NSStringEncoding(NSUTF8StringEncoding))!
						// The output as of Xcode 6.4 is structured text so we
						// parse it using regex. The destination will be omitted
						// altogether if parsing fails. Xcode 7.0 beta 4 added a
						// JSON output option as `xcrun simctl list devices --json`
						// so this can be switched once 7.0 becomes a requirement.
						let regex = try! NSRegularExpression(pattern: "-- iOS [0-9.]+ --\\n.*?\\(([0-9A-Z]{8}-([0-9A-Z]{4}-){3}[0-9A-Z]{12})\\)", options: [])
						let lastDeviceResult = regex.matchesInString(string as String, options: [], range: NSRange(location: 0, length: string.length)).last
						return lastDeviceResult.map { result in
							// We use the ID here instead of the name as it's guaranteed to be unique, the name isn't.
							let deviceID = string.substringWithRange(result.rangeAtIndex(1))
							return "platform=iOS Simulator,id=\(deviceID)"
						}
					}
					.mapError(CarthageError.TaskError)
			}
			return SignalProducer(value: nil)
		}

		return fetchDestination()
			.flatMap(.Concat) { destination -> SignalProducer<TaskEvent<BuildSettings>, CarthageError> in
				if let destination = destination {
					argsForBuilding.destination = destination
					// Also set the destination lookup timeout. Since we're building
					// for the simulator the lookup shouldn't take more than a
					// fraction of a second, but we set to 3 just to be safe.
					argsForBuilding.destinationTimeout = 3
				}

				return BuildSettings.loadWithArguments(argsForLoading)
					.filter { settings in
						// Only copy build products for the product types and the
						// Mach-O types we care about.
						if let (productType, machOType) = (settings.productType &&& settings.machOType).value {
							return shouldBuildProductType(productType) && shouldBuildMachOType(machOType)
						} else {
							return false
						}
					}
					.flatMap(.Concat) { settings -> SignalProducer<TaskEvent<BuildSettings>, CarthageError> in
						if settings.bitcodeEnabled.value == true {
							argsForBuilding.bitcodeGenerationMode = .Bitcode
						}

						var buildScheme = xcodebuildTask("build", argsForBuilding)
						buildScheme.workingDirectoryPath = workingDirectoryURL.path!

						return launchTask(buildScheme)
							.map { taskEvent in
								taskEvent.map { _ in settings }
							}
							.mapError { .TaskError($0) }
					}
			}
	}

	return BuildSettings.SDKsForScheme(scheme, inProject: project)
		.reduce([:]) { (var sdksByPlatform: [Platform: [SDK]], sdk: SDK) in
			let platform = sdk.platform

			if var sdks = sdksByPlatform[platform] {
				sdks.append(sdk)
				sdksByPlatform.updateValue(sdks, forKey: platform)
			} else {
				sdksByPlatform[platform] = [ sdk ]
			}

			return sdksByPlatform
		}
		.flatMap(.Concat) { sdksByPlatform -> SignalProducer<(Platform, [SDK]), CarthageError> in
			if sdksByPlatform.isEmpty {
				fatalError("No SDKs found for scheme \(scheme)")
			}

			let values = sdksByPlatform.map { ($0, $1) }
			return SignalProducer(values: values)
		}
		.flatMap(.Concat) { platform, sdks -> SignalProducer<(Platform, [SDK]), CarthageError> in
			let filterResult = sdkFilter(sdks: sdks, scheme: scheme, configuration: configuration, project: project)
			return SignalProducer(result: filterResult.map { (platform, $0) })
		}
		.filter { _, sdks in
			return !sdks.isEmpty
		}
		.flatMap(.Concat) { platform, sdks -> SignalProducer<TaskEvent<NSURL>, CarthageError> in
			let folderURL = workingDirectoryURL.URLByAppendingPathComponent(platform.relativePath, isDirectory: true).URLByResolvingSymlinksInPath!

			// TODO: Generalize this further?
			switch sdks.count {
			case 1:
				return buildSDK(sdks[0])
					.flatMapTaskEvents(.Merge) { settings in
						return copyBuildProductIntoDirectory(folderURL, settings)
					}

			case 2:
				let firstSDK = sdks[0]
				let secondSDK = sdks[1]

				return settingsByTarget(buildSDK(firstSDK))
					.flatMap(.Concat) { settingsEvent -> SignalProducer<TaskEvent<(BuildSettings, BuildSettings)>, CarthageError> in
						switch settingsEvent {
						case let .StandardOutput(data):
							return SignalProducer(value: .StandardOutput(data))

						case let .StandardError(data):
							return SignalProducer(value: .StandardError(data))

						case let .Success(firstSettingsByTarget):
							return settingsByTarget(buildSDK(secondSDK))
								.flatMapTaskEvents(.Concat) { (secondSettingsByTarget: [String: BuildSettings]) -> SignalProducer<(BuildSettings, BuildSettings), CarthageError> in
									assert(firstSettingsByTarget.count == secondSettingsByTarget.count, "Number of targets built for \(firstSDK) (\(firstSettingsByTarget.count)) does not match number of targets built for \(secondSDK) (\(secondSettingsByTarget.count))")

									return SignalProducer { observer, disposable in
										for (target, firstSettings) in firstSettingsByTarget {
											if disposable.disposed {
												break
											}

											let secondSettings = secondSettingsByTarget[target]
											assert(secondSettings != nil, "No \(secondSDK) build settings found for target \"\(target)\"")

											observer.sendNext((firstSettings, secondSettings!))
										}

										observer.sendCompleted()
									}
								}
						}
					}
					.flatMapTaskEvents(.Concat) { (firstSettings, secondSettings) in
						return mergeBuildProductsIntoDirectory(secondSettings, firstSettings, folderURL)
					}

			default:
				fatalError("SDK count \(sdks.count) in scheme \(scheme) is not supported")
			}
		}
		.flatMapTaskEvents(.Concat) { builtProductURL -> SignalProducer<NSURL, CarthageError> in
			return createDebugInformation(builtProductURL)
				.then(SignalProducer(value: builtProductURL))
		}
}

public func createDebugInformation(builtProductURL: NSURL) -> SignalProducer<TaskEvent<NSURL>, CarthageError> {
	let dSYMURL = builtProductURL.URLByAppendingPathExtension("dSYM")

	if let
		executableName = builtProductURL.URLByDeletingPathExtension?.lastPathComponent,
		executable = builtProductURL.URLByAppendingPathComponent(executableName).path,
		dSYM = dSYMURL.path
	{
		let dsymutilTask = TaskDescription(launchPath: "/usr/bin/xcrun", arguments: ["dsymutil", executable, "-o", dSYM])

		return launchTask(dsymutilTask)
			.mapError(CarthageError.TaskError)
			.flatMapTaskEvents(.Concat) { _ in SignalProducer(value: dSYMURL) }
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
public func buildDependencyProject(dependency: ProjectIdentifier, _ rootDirectoryURL: NSURL, withConfiguration configuration: String, platforms: Set<Platform> = [], sdkFilter: SDKFilterCallback = { .Success($0.0) }) -> SignalProducer<BuildSchemeProducer, CarthageError> {
	let rootBinariesURL = rootDirectoryURL.URLByAppendingPathComponent(CarthageBinariesFolderPath, isDirectory: true).URLByResolvingSymlinksInPath!
	let rawDependencyURL = rootDirectoryURL.URLByAppendingPathComponent(dependency.relativePath, isDirectory: true)
	let dependencyURL = rawDependencyURL.URLByResolvingSymlinksInPath!

	let schemeProducers = buildInDirectory(dependencyURL, withConfiguration: configuration, platforms: platforms, sdkFilter: sdkFilter)
	return SignalProducer.attempt { () -> Result<SignalProducer<BuildSchemeProducer, CarthageError>, CarthageError> in
			do {
				try NSFileManager.defaultManager().createDirectoryAtURL(rootBinariesURL, withIntermediateDirectories: true, attributes: nil)
			} catch let error as NSError {
				return .Failure(.WriteFailed(rootBinariesURL, error))
			}

			// Link this dependency's Carthage/Build folder to that of the root
			// project, so it can see all products built already, and so we can
			// automatically drop this dependency's product in the right place.
			let dependencyBinariesURL = dependencyURL.URLByAppendingPathComponent(CarthageBinariesFolderPath, isDirectory: true)

			do {
				try NSFileManager.defaultManager().removeItemAtURL(dependencyBinariesURL)
			} catch {
				let dependencyParentURL = dependencyBinariesURL.URLByDeletingLastPathComponent!

				do {
					try NSFileManager.defaultManager().createDirectoryAtURL(dependencyParentURL, withIntermediateDirectories: true, attributes: nil)
				} catch let error as NSError {
					return .Failure(.WriteFailed(dependencyParentURL, error))
				}
			}

			var isSymlink: AnyObject?
			do {
				try rawDependencyURL.getResourceValue(&isSymlink, forKey: NSURLIsSymbolicLinkKey)
			} catch let error as NSError {
				return .Failure(.ReadFailed(rawDependencyURL, error))
			}

			if isSymlink as? Bool == true {
				// Since this dependency is itself a symlink, we'll create an
				// absolute link back to the project's Build folder.
				do {
					try NSFileManager.defaultManager().createSymbolicLinkAtURL(dependencyBinariesURL, withDestinationURL: rootBinariesURL)
				} catch let error as NSError {
					return .Failure(.WriteFailed(dependencyBinariesURL, error))
				}
			} else {
				// The relative path to this dependency's Carthage/Build folder, from
				// the root.
				let dependencyBinariesRelativePath = (dependency.relativePath as NSString).stringByAppendingPathComponent(CarthageBinariesFolderPath)
				let componentsForGettingTheHellOutOfThisRelativePath = Array(count: (dependencyBinariesRelativePath as NSString).pathComponents.count - 1, repeatedValue: "..")

				// Directs a link from, e.g., /Carthage/Checkouts/ReactiveCocoa/Carthage/Build to /Carthage/Build
				let linkDestinationPath = componentsForGettingTheHellOutOfThisRelativePath.reduce(CarthageBinariesFolderPath) { trailingPath, pathComponent in
					return (pathComponent as NSString).stringByAppendingPathComponent(trailingPath)
				}

				do {
					try NSFileManager.defaultManager().createSymbolicLinkAtPath(dependencyBinariesURL.path!, withDestinationPath: linkDestinationPath)
				} catch let error as NSError {
					return .Failure(.WriteFailed(dependencyBinariesURL, error))
				}
			}

			return .Success(schemeProducers)
		}
		.flatMap(.Merge) { schemeProducers in
			return schemeProducers
				.mapError { error in
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
		.ignoreTaskData()
		.mapError(CarthageError.TaskError)
		.map { (data: NSData) -> String in
			return NSString(data: data, encoding: NSStringEncoding(NSUTF8StringEncoding))! as String
		}
		.flatMap(.Merge) { (string: String) -> SignalProducer<String, CarthageError> in
			return string.linesProducer.promoteErrors(CarthageError.self)
		}
}

public typealias CodeSigningIdentity = String

/// Matches lines of the form:
///
/// '  1) 4E8D512C8480AAC679947D6E50190AE97AB3E825 "3rd Party Mac Developer Application: Developer Name (DUCNFCN445)"'
/// '  2) 8B0EBBAE7E7230BB6AF5D69CA09B769663BC844D "Mac Developer: Developer Name (DUCNFCN445)"'
private let signingIdentitiesRegex = try! NSRegularExpression(pattern:
	(
		"\\s*"               + // Leading spaces
		"\\d+\\)\\s+"        + // Number of identity
		"([A-F0-9]+)\\s+"    + // Hash (e.g. 4E8D512C8480AAC67995D69CA09B769663BC844D)
		"\"(.+):\\s"         + // Identity type (e.g. Mac Developer, iPhone Developer)
		"(.+)\\s\\("         + // Developer Name
		"([A-Z0-9]+)\\)\"\\s*" // Developer ID (e.g. DUCNFCN445)
	),
 options: [])

public func parseSecuritySigningIdentities(securityIdentities securityIdentities: SignalProducer<String, CarthageError> = getSecuritySigningIdentities()) -> SignalProducer<CodeSigningIdentity, CarthageError> {
	return securityIdentities
		.map { (identityLine: String) -> CodeSigningIdentity? in
			let fullRange = NSMakeRange(0, identityLine.characters.count)
			
			if let match = signingIdentitiesRegex.matchesInString(identityLine, options: [], range: fullRange).first {
				let id = identityLine as NSString
				
				return id.substringWithRange(match.rangeAtIndex(2))
			}
			
			return nil
		}
		.ignoreNil()
}

/// Builds the first project or workspace found within the given directory which
/// has at least one shared framework scheme.
///
/// Returns a signal of all standard output from `xcodebuild`, and a
/// signal-of-signals representing each scheme being built.
public func buildInDirectory(directoryURL: NSURL, withConfiguration configuration: String, platforms: Set<Platform> = [], sdkFilter: SDKFilterCallback = { .Success($0.0) }) -> SignalProducer<BuildSchemeProducer, CarthageError> {
	precondition(directoryURL.fileURL)

	return SignalProducer { observer, disposable in
		// Use SignalProducer.buffer() to avoid enumerating the given directory
		// multiple times.
		let (locatorBuffer, locatorObserver) = SignalProducer<(ProjectLocator, [String]), CarthageError>.buffer()

		locateProjectsInDirectory(directoryURL)
			.flatMap(.Concat) { (project: ProjectLocator) -> SignalProducer<(ProjectLocator, [String]), CarthageError> in
				return schemesInProject(project)
					.flatMap(.Merge) { scheme -> SignalProducer<String, CarthageError> in
						let buildArguments = BuildArguments(project: project, scheme: scheme, configuration: configuration)

						return shouldBuildScheme(buildArguments, platforms)
							.filter { $0 }
							.map { _ in scheme }
					}
					.collect()
					.flatMapError { error in
						switch error {
						case .NoSharedSchemes:
							return SignalProducer(value: [])

						default:
							return SignalProducer(error: error)
						}
					}
					.map { (project, $0) }
			}
			.startWithSignal { signal, signalDisposable in
				disposable += signalDisposable
				signal.observe(locatorObserver)
			}

		locatorBuffer
			.collect()
			// Allow dependencies which have no projects, not to error out with
			// `.NoSharedFrameworkSchemes`.
			.filter { projects in !projects.isEmpty }
			.flatMap(.Merge) { (projects: [(ProjectLocator, [String])]) -> SignalProducer<(String, ProjectLocator), CarthageError> in
				return SignalProducer(values: projects)
					.map { (project: ProjectLocator, schemes: [String]) in
						// Only look for schemes that actually reside in the project
						let containedSchemes = schemes.filter { (scheme: String) -> Bool in
							if let schemePath = project.fileURL.URLByAppendingPathComponent("xcshareddata/xcschemes/\(scheme).xcscheme").path {
								return NSFileManager.defaultManager().fileExistsAtPath(schemePath)
							}
							return false
						}
						return (project, containedSchemes)
					}
					.filter { (project: ProjectLocator, schemes: [String]) in
						switch project {
						case .ProjectFile where !schemes.isEmpty:
							return true

						default:
							return false
						}
					}
					.concat(SignalProducer(error: .NoSharedFrameworkSchemes(.Git(GitURL(directoryURL.path!)), platforms)))
					.take(1)
					.flatMap(.Merge) { project, schemes in SignalProducer(values: schemes.map { ($0, project) }) }
			}
			.flatMap(.Merge) { scheme, project -> SignalProducer<(String, ProjectLocator), CarthageError> in
				return locatorBuffer
					// This scheduler hop is required to avoid disallowed recursive signals.
					// See https://github.com/ReactiveCocoa/ReactiveCocoa/pull/2042.
					.startOn(QueueScheduler(queue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), name: "org.carthage.CarthageKit.Xcode.buildInDirectory"))
					// Pick up the first workspace which can build the scheme.
					.filter { project, schemes in
						switch project {
						case .Workspace where schemes.contains(scheme):
							return true

						default:
							return false
						}
					}
					// If there is no appropriate workspace, use the project in
					// which the scheme is defined instead.
					.concat(SignalProducer(value: (project, [])))
					.take(1)
					.map { project, _ in (scheme, project) }
			}
			.map { (scheme: String, project: ProjectLocator) -> BuildSchemeProducer in
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
					.map { taskEvent in
						return taskEvent.map { _ in initialValue }
					}
					.filter { taskEvent in taskEvent.value == nil }

				return BuildSchemeProducer(value: .Success(initialValue))
					.concat(buildProgress)
			}
			.startWithSignal { signal, signalDisposable in
				disposable += signalDisposable
				signal.observe(observer)
			}
	}
}

/// Strips a framework from unexpected architectures, optionally codesigning the
/// result.
public func stripFramework(frameworkURL: NSURL, keepingArchitectures: [String], codesigningIdentity: String? = nil) -> SignalProducer<(), CarthageError> {
	let stripArchitectures = architecturesInFramework(frameworkURL)
		.filter { !keepingArchitectures.contains($0) }
		.flatMap(.Concat) { stripArchitecture(frameworkURL, $0) }

	// Xcode doesn't copy `Modules` directory at all.
	let stripModules = stripModulesDirectory(frameworkURL)

	let sign = codesigningIdentity.map { codesign(frameworkURL, $0) } ?? .empty

	return stripArchitectures
		.concat(stripModules)
		.concat(sign)
}

/// Copies a product into the given folder. The folder will be created if it
/// does not already exist.
///
/// Returns a signal that will send the URL after copying upon .success.
public func copyProduct(from: NSURL, _ to: NSURL) -> SignalProducer<NSURL, CarthageError> {
	return SignalProducer<NSURL, CarthageError>.attempt {
		let manager = NSFileManager.defaultManager()

		do {
			try manager.createDirectoryAtURL(to.URLByDeletingLastPathComponent!, withIntermediateDirectories: true, attributes: nil)
		} catch let error as NSError {
			// Although the method's documentation says: “YES if createIntermediates
			// is set and the directory already exists)”, it seems to rarely
			// returns NO and NSFileWriteFileExistsError error. So we should
			// ignore that specific error.
			//
			// See https://github.com/Carthage/Carthage/issues/591.
			if error.code != NSFileWriteFileExistsError {
				return .Failure(.WriteFailed(to.URLByDeletingLastPathComponent!, error))
			}
		}

		do {
			try manager.removeItemAtURL(to)
		} catch let error as NSError {
			if error.code != NSFileNoSuchFileError {
				return .Failure(.WriteFailed(to, error))
			}
		}

		do {
			try manager.copyItemAtURL(from, toURL: to)
			return .Success(to)
		} catch let error as NSError {
			return .Failure(.WriteFailed(to, error))
		}
	}
}

extension SignalProducerType where Value == NSURL, Error == CarthageError {
	/// Copies existing files sent from the producer into the given directory.
	///
	/// Returns a producer that will send locations where the copied files are.
	public func copyFileURLsIntoDirectory(directoryURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
		return producer
			.filter { fileURL in fileURL.checkResourceIsReachableAndReturnError(nil) }
			.flatMap(.Merge) { fileURL -> SignalProducer<NSURL, CarthageError> in
				let fileName = fileURL.lastPathComponent!
				let destinationURL = directoryURL.URLByAppendingPathComponent(fileName, isDirectory: false)
				let resolvedDestinationURL = destinationURL.URLByResolvingSymlinksInPath!

				return copyProduct(fileURL, resolvedDestinationURL)
			}
	}
}

/// Strips the given architecture from a framework.
private func stripArchitecture(frameworkURL: NSURL, _ architecture: String) -> SignalProducer<(), CarthageError> {
	return SignalProducer.attempt { () -> Result<NSURL, CarthageError> in
			return binaryURL(frameworkURL)
		}
		.flatMap(.Merge) { binaryURL -> SignalProducer<TaskEvent<NSData>, CarthageError> in
			let lipoTask = TaskDescription(launchPath: "/usr/bin/xcrun", arguments: [ "lipo", "-remove", architecture, "-output", binaryURL.path! , binaryURL.path!])
			return launchTask(lipoTask)
				.mapError(CarthageError.TaskError)
		}
		.then(.empty)
}

/// Returns a signal of all architectures present in a given framework.
public func architecturesInFramework(frameworkURL: NSURL) -> SignalProducer<String, CarthageError> {
	return SignalProducer.attempt { () -> Result<NSURL, CarthageError> in
			return binaryURL(frameworkURL)
		}
		.flatMap(.Merge) { binaryURL -> SignalProducer<String, CarthageError> in
			let lipoTask = TaskDescription(launchPath: "/usr/bin/xcrun", arguments: [ "lipo", "-info", binaryURL.path!])

			return launchTask(lipoTask)
				.ignoreTaskData()
				.mapError(CarthageError.TaskError)
				.map { NSString(data: $0, encoding: NSUTF8StringEncoding) ?? "" }
				.flatMap(.Merge) { output -> SignalProducer<String, CarthageError> in
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
	return SignalProducer.attempt {
		let modulesDirectoryURL = frameworkURL.URLByAppendingPathComponent("Modules", isDirectory: true)

		var isDirectory: ObjCBool = false
		if !NSFileManager.defaultManager().fileExistsAtPath(modulesDirectoryURL.path!, isDirectory: &isDirectory) || !isDirectory {
			return .Success(())
		}

		do {
			try NSFileManager.defaultManager().removeItemAtURL(modulesDirectoryURL)
		} catch let error as NSError {
			return .Failure(.WriteFailed(modulesDirectoryURL, error))
		}

		return .Success(())
	}
}

/// Sends a set of UUIDs for each architecture present in the given framework.
public func UUIDsForFramework(frameworkURL: NSURL) -> SignalProducer<Set<NSUUID>, CarthageError> {
	return SignalProducer.attempt { () -> Result<NSURL, CarthageError> in
			return binaryURL(frameworkURL)
		}
		.flatMap(.Merge, transform: UUIDsFromDwarfdump)
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
		.flatMap(.Merge) { UUIDs in SignalProducer(values: UUIDs) }
		.map { UUID in
			return directoryURL.URLByAppendingPathComponent(UUID.UUIDString, isDirectory: false).URLByAppendingPathExtension("bcsymbolmap")
		}
}

/// Sends a set of UUIDs for each architecture present in the given URL.
private func UUIDsFromDwarfdump(URL: NSURL) -> SignalProducer<Set<NSUUID>, CarthageError> {
	let dwarfdumpTask = TaskDescription(launchPath: "/usr/bin/xcrun", arguments: [ "dwarfdump", "--uuid", URL.path! ])

	return launchTask(dwarfdumpTask)
		.ignoreTaskData()
		.mapError(CarthageError.TaskError)
		.map { NSString(data: $0, encoding: NSUTF8StringEncoding) ?? "" }
		.flatMap(.Merge) { output -> SignalProducer<Set<NSUUID>, CarthageError> in
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
		return .Success(frameworkURL.URLByAppendingPathComponent(binaryName))
	} else {
		return .Failure(.ReadFailed(frameworkURL, nil))
	}
}

/// Signs a framework with the given codesigning identity.
private func codesign(frameworkURL: NSURL, _ expandedIdentity: String) -> SignalProducer<(), CarthageError> {
	let codesignTask = TaskDescription(launchPath: "/usr/bin/xcrun", arguments: [ "codesign", "--force", "--sign", expandedIdentity, "--preserve-metadata=identifier,entitlements", frameworkURL.path! ])

	return launchTask(codesignTask)
		.mapError(CarthageError.TaskError)
		.then(.empty)
}
