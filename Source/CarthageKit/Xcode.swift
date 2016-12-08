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
	case workspace(URL)

	/// The `xcodeproj` at the given file URL should be built.
	case projectFile(URL)

	/// The file URL this locator refers to.
	public var fileURL: URL {
		switch self {
		case let .workspace(url):
			assert(url.isFileURL)
			return url

		case let .projectFile(url):
			assert(url.isFileURL)
			return url
		}
	}

	/// The number of levels deep the current object is in the directory hierarchy.
	public var level: Int {
		return fileURL.carthage_pathComponents.count - 1
	}
}

public func ==(lhs: ProjectLocator, rhs: ProjectLocator) -> Bool {
	switch (lhs, rhs) {
	case let (.workspace(left), .workspace(right)):
		return left == right

	case let (.projectFile(left), .projectFile(right)):
		return left == right

	default:
		return false
	}
}

public func <(lhs: ProjectLocator, rhs: ProjectLocator) -> Bool {
	// Prefer top-level directories
	let leftLevel = lhs.level
	let rightLevel = rhs.level
	guard leftLevel == rightLevel else {
		return leftLevel < rightLevel
	}

	// Prefer workspaces over projects.
	switch (lhs, rhs) {
	case (.workspace, .projectFile):
		return true

	case (.projectFile, .workspace):
		return false

	default:
		return lhs.fileURL.carthage_path.characters.lexicographicalCompare(rhs.fileURL.carthage_path.characters)
	}
}

extension ProjectLocator: CustomStringConvertible {
	public var description: String {
		return fileURL.carthage_lastPathComponent
	}
}

/// Attempts to locate projects and workspaces within the given directory.
///
/// Sends all matches in preferential order.
public func locateProjectsInDirectory(directoryURL: URL) -> SignalProducer<ProjectLocator, CarthageError> {
	let enumerationOptions: NSDirectoryEnumerationOptions = [ .SkipsHiddenFiles, .SkipsPackageDescendants ]

	return gitmodulesEntriesInRepository(directoryURL, revision: nil)
		.map { directoryURL.appendingPathComponent($0.path) }
		.concat(value: directoryURL.appendingPathComponent(CarthageProjectCheckoutsPath))
		.collect()
		.flatMap(.merge) { directoriesToSkip in
			return FileManager.`default`
				.carthage_enumerator(at: directoryURL.resolvingSymlinksInPath(), includingPropertiesForKeys: [ NSURLTypeIdentifierKey ], options: enumerationOptions, catchErrors: true)
				.map { _, url in url }
				.filter { url in
					return !directoriesToSkip.contains { $0.hasSubdirectory(url) }
				}
		}
		.map { url -> ProjectLocator? in
			if let uti = url.typeIdentifier.value {
				if (UTTypeConformsTo(uti as CFString, "com.apple.dt.document.workspace" as CFString)) {
					return .workspace(url)
				} else if (UTTypeConformsTo(uti as CFString, "com.apple.xcode.project" as CFString)) {
					return .projectFile(url)
				}
			}
			return nil
		}
		.skipNil()
		.collect()
		.map { $0.sort() }
		.flatMap(.merge) { SignalProducer<ProjectLocator, CarthageError>(values: $0) }
}

/// Creates a task description for executing `xcodebuild` with the given
/// arguments.
public func xcodebuildTask(tasks: [String], _ buildArguments: BuildArguments) -> Task {
	return Task("/usr/bin/xcrun", arguments: buildArguments.arguments + tasks)
}

/// Creates a task description for executing `xcodebuild` with the given
/// arguments.
public func xcodebuildTask(task: String, _ buildArguments: BuildArguments) -> Task {
	return xcodebuildTask([task], buildArguments)
}

/// Sends each scheme found in the given project.
public func schemesInProject(project: ProjectLocator) -> SignalProducer<String, CarthageError> {
	let task = xcodebuildTask("-list", BuildArguments(project: project))

	return task.launch()
		.ignoreTaskData()
		.mapError(CarthageError.taskError)
		// xcodebuild has a bug where xcodebuild -list can sometimes hang
		// indefinitely on projects that don't share any schemes, so
		// automatically bail out if it looks like that's happening.
		.timeout(after: 60, raising: .xcodebuildTimeout(project), on: QueueScheduler(qos: QOS_CLASS_DEFAULT))
		.retry(upTo: 2)
		.map { data in
			return String(data: data, encoding: NSUTF8StringEncoding)!
		}
		.flatMap(.merge) { string in
			return string.linesProducer
		}
		.flatMap(.merge) { line -> SignalProducer<String, CarthageError> in
			// Matches one of these two possible messages:
			//
			// '    This project contains no schemes.'
			// 'There are no schemes in workspace "Carthage".'
			if line.hasSuffix("contains no schemes.") || line.hasPrefix("There are no schemes") {
				return SignalProducer(error: .noSharedSchemes(project, nil))
			} else {
				return SignalProducer(value: line)
			}
		}
		.skip { line in !line.hasSuffix("Schemes:") }
		.skip(first: 1)
		.take { line in !line.isEmpty }
		.map { (line: String) -> String in line.stringByTrimmingCharactersInSet(.whitespaces) }
}

/// Finds schemes of projects or workspaces, which Carthage should build, found
/// within the given directory.
public func buildableSchemesInDirectory(directoryURL: URL, withConfiguration configuration: String, forPlatforms platforms: Set<Platform> = []) -> SignalProducer<(ProjectLocator, [String]), CarthageError> {
	precondition(directoryURL.isFileURL)

	return locateProjectsInDirectory(directoryURL)
		.flatMap(.concat) { project -> SignalProducer<(ProjectLocator, [String]), CarthageError> in
			return schemesInProject(project)
				.flatMap(.merge) { scheme -> SignalProducer<String, CarthageError> in
					let buildArguments = BuildArguments(project: project, scheme: scheme, configuration: configuration)

					return shouldBuildScheme(buildArguments, platforms)
						.filter { $0 }
						.map { _ in scheme }
				}
				.collect()
				.flatMapError { error in
					if case .noSharedSchemes = error {
						return .init(value: [])
					} else {
						return .init(error: error)
					}
				}
				.map { (project, $0) }
		}
}

/// Sends pairs of a scheme and a project, the scheme actually resides in
/// the project.
public func schemesInProjects(projects: [(ProjectLocator, [String])]) -> SignalProducer<[(String, ProjectLocator)], CarthageError> {
	return SignalProducer(values: projects)
		.map { (project: ProjectLocator, schemes: [String]) in
			// Only look for schemes that actually reside in the project
			let containedSchemes = schemes.filter { (scheme: String) -> Bool in
				let schemePath = project.fileURL.appendingPathComponent("xcshareddata/xcschemes/\(scheme).xcscheme").carthage_path
				return FileManager.`default`.fileExists(atPath: schemePath)
			}
			return (project, containedSchemes)
		}
		.filter { (project: ProjectLocator, schemes: [String]) in
			switch project {
			case .projectFile where !schemes.isEmpty:
				return true

			default:
				return false
			}
		}
		.flatMap(.concat) { project, schemes in
			return .init(values: schemes.map { ($0, project) })
		}
		.collect()
}

/// Represents a platform to build for.
public enum Platform: String {
	/// macOS.
	case macOS = "Mac"

	/// iOS for device and simulator.
	case iOS = "iOS"

	/// Apple Watch device and simulator.
	case watchOS = "watchOS"

	/// Apple TV device and simulator.
	case tvOS = "tvOS"

	/// All supported build platforms.
	public static let supportedPlatforms: [Platform] = [ .macOS, .iOS, .watchOS, .tvOS ]

	/// The relative path at which binaries corresponding to this platform will
	/// be stored.
	public var relativePath: String {
		let subfolderName = rawValue
		return (CarthageBinariesFolderPath as NSString).stringByAppendingPathComponent(subfolderName)
	}

	/// The SDKs that need to be built for this platform.
	public var SDKs: [SDK] {
		switch self {
		case .macOS:
			return [ .macOSX ]

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
	/// macOS.
	case macOSX = "macosx"

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

	public static let allSDKs: Set<SDK> = [.macOSX, .iPhoneOS, .iPhoneSimulator, .watchOS, .watchSimulator, .tvOS, .tvSimulator]

	/// Attempts to parse an SDK name from a string returned from `xcodebuild`.
	public static func fromString(string: String) -> Result<SDK, CarthageError> {
		return Result(self.init(rawValue: string.lowercaseString), failWith: .parseError(description: "unexpected SDK key \"\(string)\""))
	}

	/// Split the given SDKs into simulator ones and device ones.
	private static func splitSDKs<S: SequenceType where S.Generator.Element == SDK>(sdks: S) -> (simulators: [SDK], devices: [SDK]) {
		return (
			simulators: sdks.filter { $0.isSimulator },
			devices: sdks.filter { !$0.isSimulator }
		)
	}

	/// Returns whether this is a simulator SDK.
	public var isSimulator: Bool {
		switch self {
		case .iPhoneSimulator, .watchSimulator, .tvSimulator:
			return true

		case _:
			return false
		}
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

		case .macOSX:
			return .macOS
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

		case .macOSX:
			return "macOS"

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

/// Represents a build setting whether full bitcode should be embedded in the
/// binary.
public enum BitcodeGenerationMode: String {
	/// Only bitcode marker will be embedded.
	case marker = "marker"

	/// Full bitcode will be embedded.
	case bitcode = "bitcode"
}

/// Describes the type of product built by an Xcode target.
public enum ProductType: String {
	/// A framework bundle.
	case framework = "com.apple.product-type.framework"

	/// A static library.
	case staticLibrary = "com.apple.product-type.library.static"

	/// A unit test bundle.
	case testBundle = "com.apple.product-type.bundle.unit-test"

	/// Attempts to parse a product type from a string returned from
	/// `xcodebuild`.
	public static func fromString(string: String) -> Result<ProductType, CarthageError> {
		return Result(self.init(rawValue: string), failWith: .parseError(description: "unexpected product type \"\(string)\""))
	}
}

/// Describes the type of Mach-O files.
/// See https://developer.apple.com/library/mac/documentation/DeveloperTools/Reference/XcodeBuildSettingRef/1-Build_Setting_Reference/build_setting_ref.html#//apple_ref/doc/uid/TP40003931-CH3-SW73.
public enum MachOType: String {
	/// Executable binary.
	case executable = "mh_executable"

	/// Bundle binary.
	case bundle = "mh_bundle"

	/// Relocatable object file.
	case object = "mh_object"

	/// Dynamic library binary.
	case dylib = "mh_dylib"

	/// Static library binary.
	case staticlib = "staticlib"

	/// Attempts to parse a Mach-O type from a string returned from `xcodebuild`.
	public static func fromString(string: String) -> Result<MachOType, CarthageError> {
		return Result(self.init(rawValue: string), failWith: .parseError(description: "unexpected Mach-O type \"\(string)\""))
	}
}

/// Describes the type of frameworks.
private enum FrameworkType {
	/// A dynamic framework.
	case dynamic

	/// A static framework.
	case `static`

	init?(productType: ProductType, machOType: MachOType) {
		switch (productType, machOType) {
		case (.framework, .dylib):
			self = .dynamic

		case (.framework, .staticlib):
			self = .`static`

		case _:
			return nil
		}
	}
}

/// Describes the type of packages, given their CFBundlePackageType.
private enum PackageType: String {
	/// A .framework package.
	case framework = "FMWK"

	/// A .bundle package. Some frameworks might have this package type code
	/// (e.g. https://github.com/ResearchKit/ResearchKit/blob/1.3.0/ResearchKit/Info.plist#L15-L16).
	case bundle = "BNDL"

	/// A .dSYM package.
	case dSYM = "dSYM"
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
		// xcodebuild (in Xcode 8) has a bug where xcodebuild -showBuildSettings
		// can hang indefinitely on projects that contain core data models.
		// rdar://27052195
		// Including the action "clean" works around this issue, which is further
		// discussed here: https://forums.developer.apple.com/thread/50372
		let task = xcodebuildTask(["clean", "-showBuildSettings", "-skipUnavailableActions"], arguments)

		return task.launch()
			.ignoreTaskData()
			.mapError(CarthageError.taskError)
			// xcodebuild has a bug where xcodebuild -showBuildSettings
			// can sometimes hang indefinitely on projects that don't
			// share any schemes, so automatically bail out if it looks
			// like that's happening.
			.timeout(after: 60, raising: .xcodebuildTimeout(arguments.project), on: QueueScheduler(qos: QOS_CLASS_DEFAULT))
			.retry(upTo: 5)
			.map { data in
				return String(data: data, encoding: NSUTF8StringEncoding)!
			}
			.flatMap(.merge) { string -> SignalProducer<BuildSettings, CarthageError> in
				return SignalProducer { observer, disposable in
					var currentSettings: [String: String] = [:]
					var currentTarget: String?

					let flushTarget = { () -> () in
						if let currentTarget = currentTarget {
							let buildSettings = self.init(target: currentTarget, settings: currentSettings)
							observer.send(value: buildSettings)
						}

						currentTarget = nil
						currentSettings = [:]
					}

					string.enumerateLines { line, stop in
						if disposable.isDisposed {
							stop = true
							return
						}

						if let result = self.targetSettingsRegex.firstMatch(in: line, range: NSMakeRange(0, line.utf16.count)) {
							let targetRange = result.rangeAt(1)

							flushTarget()
							currentTarget = (line as NSString).substringWithRange(targetRange)
							return
						}

						let trimSet = CharacterSet.whitespacesAndNewlines
						let components = line.characters
							.split(1) { $0 == "=" }
							.map { String($0).stringByTrimmingCharactersInSet(trimSet) }

						if components.count == 2 {
							currentSettings[components[0]] = components[1]
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
			.take(first: 1)
			.flatMap(.merge) { $0.buildSDKs }
	}

	/// Returns the value for the given build setting, or an error if it could
	/// not be determined.
	public subscript(key: String) -> Result<String, CarthageError> {
		if let value = settings[key] {
			return .success(value)
		} else {
			return .failure(.missingBuildSetting(key))
		}
	}

	/// Attempts to determine the SDKs this scheme builds for.
	public var buildSDKs: SignalProducer<SDK, CarthageError> {
		let supportedPlatforms = self["SUPPORTED_PLATFORMS"]

		if let supportedPlatforms = supportedPlatforms.value {
			let platforms = supportedPlatforms.characters.split { $0 == " " }.map(String.init)
			return SignalProducer<String, CarthageError>(values: platforms)
				.map { platform in SignalProducer(result: SDK.fromString(platform)) }
				.flatten(.merge)
		}

		let firstBuildSDK = self["PLATFORM_NAME"].flatMap(SDK.fromString)
		return SignalProducer(result: firstBuildSDK)
	}

	/// Attempts to determine the ProductType specified in these build settings.
	public var productType: Result<ProductType, CarthageError> {
		return self["PRODUCT_TYPE"].flatMap(ProductType.fromString)
	}

	/// Attempts to determine the MachOType specified in these build settings.
	public var machOType: Result<MachOType, CarthageError> {
		return self["MACH_O_TYPE"].flatMap(MachOType.fromString)
	}

	/// Attempts to determine the FrameworkType identified by these build settings.
	private var frameworkType: Result<FrameworkType?, CarthageError> {
		return (productType &&& machOType).map(FrameworkType.init)
	}

	/// Attempts to determine the URL to the built products directory.
	public var builtProductsDirectoryURL: Result<URL, CarthageError> {
		return self["BUILT_PRODUCTS_DIR"].map { productsDir in
			return URL(fileURLWithPath: productsDir, isDirectory: true)
		}
	}

	/// Attempts to determine the relative path (from the build folder) to the
	/// built executable.
	public var executablePath: Result<String, CarthageError> {
		return self["EXECUTABLE_PATH"]
	}

	/// Attempts to determine the URL to the built executable.
	public var executableURL: Result<URL, CarthageError> {
		return builtProductsDirectoryURL.flatMap { builtProductsURL in
			return self.executablePath.map { executablePath in
				return builtProductsURL.appendingPathComponent(executablePath)
			}
		}
	}

	/// Attempts to determine the name of the built product's wrapper bundle.
	public var wrapperName: Result<String, CarthageError> {
		return self["WRAPPER_NAME"]
	}

	/// Attempts to determine the URL to the built product's wrapper.
	public var wrapperURL: Result<URL, CarthageError> {
		return builtProductsDirectoryURL.flatMap { builtProductsURL in
			return self.wrapperName.map { wrapperName in
				return builtProductsURL.appendingPathComponent(wrapperName)
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
			return .success(nil)
		}
	}

	/// Attempts to determine the code signing identity.
	public var codeSigningIdentity: Result<String, CarthageError> {
		return self["CODE_SIGN_IDENTITY"]
	}

	/// Attempts to determine if ad hoc code signing is allowed.
	public var adHocCodeSigningAllowed: Result<Bool, CarthageError> {
		return self["AD_HOC_CODE_SIGNING_ALLOWED"].map { $0 == "YES" }
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
private func copyBuildProductIntoDirectory(directoryURL: URL, _ settings: BuildSettings) -> SignalProducer<URL, CarthageError> {
	let target = settings.wrapperName.map(directoryURL.appendingPathComponent)
	return SignalProducer(result: target &&& settings.wrapperURL)
		.flatMap(.merge) { (target, source) in
			return copyProduct(source, target)
		}
		.flatMap(.merge) { url in
			return copyBCSymbolMapsForBuildProductIntoDirectory(directoryURL, settings)
				.then(SignalProducer(value: url))
		}
}

/// Finds any *.bcsymbolmap files for the built product and copies them into
/// the given folder. Does nothing if bitcode is disabled.
///
/// Returns a signal that will send the URL after copying for each file.
private func copyBCSymbolMapsForBuildProductIntoDirectory(directoryURL: URL, _ settings: BuildSettings) -> SignalProducer<URL, CarthageError> {
	if settings.bitcodeEnabled.value == true {
		return SignalProducer(result: settings.wrapperURL)
			.flatMap(.merge) { wrapperURL in BCSymbolMapsForFramework(wrapperURL) }
			.copyFileURLsIntoDirectory(directoryURL)
	} else {
		return .empty
	}
}

/// Attempts to merge the given executables into one fat binary, written to
/// the specified URL.
private func mergeExecutables(executableURLs: [URL], _ outputURL: URL) -> SignalProducer<(), CarthageError> {
	precondition(outputURL.isFileURL)

	return SignalProducer<URL, CarthageError>(values: executableURLs)
		.attemptMap { url -> Result<String, CarthageError> in
			if url.isFileURL {
				return .success(url.carthage_path)
			} else {
				return .failure(.parseError(description: "expected file URL to built executable, got \(url)"))
			}
		}
		.collect()
		.flatMap(.merge) { executablePaths -> SignalProducer<TaskEvent<Data>, CarthageError> in
			let lipoTask = Task("/usr/bin/xcrun", arguments: [ "lipo", "-create" ] + executablePaths + [ "-output", outputURL.carthage_path ])

			return lipoTask.launch()
				.mapError(CarthageError.taskError)
		}
		.then(.empty)
}

/// If the given source URL represents an LLVM module, copies its contents into
/// the destination module.
///
/// Sends the URL to each file after copying.
private func mergeModuleIntoModule(sourceModuleDirectoryURL: URL, _ destinationModuleDirectoryURL: URL) -> SignalProducer<URL, CarthageError> {
	precondition(sourceModuleDirectoryURL.isFileURL)
	precondition(destinationModuleDirectoryURL.isFileURL)

	return FileManager.`default`.carthage_enumerator(at: sourceModuleDirectoryURL, includingPropertiesForKeys: [], options: [ .SkipsSubdirectoryDescendants, .SkipsHiddenFiles ], catchErrors: true)
		.attemptMap { _, url -> Result<URL, CarthageError> in
			let lastComponent: String = url.carthage_lastPathComponent
			let destinationURL = destinationModuleDirectoryURL.appendingPathComponent(lastComponent).resolvingSymlinksInPath()

			do {
				try FileManager.`default`.copyItem(at: url, to: destinationURL)
				return .success(destinationURL)
			} catch let error as NSError {
				return .failure(.writeFailed(destinationURL, error))
			}
		}
}

/// Determines whether the specified framework type should be built automatically.
private func shouldBuildFrameworkType(frameworkType: FrameworkType?) -> Bool {
	return frameworkType == .dynamic
}

/// Determines whether the given scheme should be built automatically.
private func shouldBuildScheme(buildArguments: BuildArguments, _ forPlatforms: Set<Platform>) -> SignalProducer<Bool, CarthageError> {
	precondition(buildArguments.scheme != nil)

	return BuildSettings.loadWithArguments(buildArguments)
		.flatMap(.concat) { settings -> SignalProducer<FrameworkType?, CarthageError> in
			let frameworkType = SignalProducer(result: settings.frameworkType)

			if forPlatforms.isEmpty {
				return frameworkType
					.flatMapError { _ in .empty }
			} else {
				return settings.buildSDKs
					.filter { forPlatforms.contains($0.platform) }
					.flatMap(.merge) { _ in frameworkType }
					.flatMapError { _ in .empty }
			}
		}
		.filter(shouldBuildFrameworkType)
		// If we find any dynamic framework target, we should indeed build this scheme.
		.map { _ in true }
		// Otherwise, nope.
		.concat(value: false)
		.take(first: 1)
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
						observer.send(value: transformedEvent)
					}

				case let .Failed(error):
					observer.send(error: error)

				case .Completed:
					observer.send(value: .success(settings))
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
private func mergeBuildProductsIntoDirectory(firstProductSettings: BuildSettings, _ secondProductSettings: BuildSettings, _ destinationFolderURL: URL) -> SignalProducer<URL, CarthageError> {
	return copyBuildProductIntoDirectory(destinationFolderURL, firstProductSettings)
		.flatMap(.merge) { productURL -> SignalProducer<URL, CarthageError> in
			let executableURLs = (firstProductSettings.executableURL &&& secondProductSettings.executableURL).map { [ $0, $1 ] }
			let outputURL = firstProductSettings.executablePath.map(destinationFolderURL.appendingPathComponent)

			let mergeProductBinaries = SignalProducer(result: executableURLs &&& outputURL)
				.flatMap(.concat) { (executableURLs: [URL], outputURL: URL) -> SignalProducer<(), CarthageError> in
					return mergeExecutables(executableURLs, outputURL.resolvingSymlinksInPath())
				}

			let sourceModulesURL = SignalProducer(result: secondProductSettings.relativeModulesPath &&& secondProductSettings.builtProductsDirectoryURL)
				.filter { $0.0 != nil }
				.map { (modulesPath, productsURL) -> URL in
					return productsURL.appendingPathComponent(modulesPath!)
				}

			let destinationModulesURL = SignalProducer(result: firstProductSettings.relativeModulesPath)
				.filter { $0 != nil }
				.map { modulesPath -> URL in
					return destinationFolderURL.appendingPathComponent(modulesPath!)
				}

			let mergeProductModules = SignalProducer.zip(sourceModulesURL, destinationModulesURL)
				.flatMap(.merge) { (source: URL, destination: URL) -> SignalProducer<URL, CarthageError> in
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
public func buildScheme(scheme: String, withConfiguration configuration: String, inProject project: ProjectLocator, workingDirectoryURL: URL, derivedDataPath: String?, toolchain: String?, cachedBinariesPath: URL?, sdkFilter: SDKFilterCallback = { .success($0.0) }) -> SignalProducer<TaskEvent<URL>, CarthageError> {
	precondition(workingDirectoryURL.isFileURL)

	let buildArgs = BuildArguments(project: project, scheme: scheme, configuration: configuration, derivedDataPath: derivedDataPath, toolchain: toolchain)

	let buildSDK = { (sdk: SDK) -> SignalProducer<TaskEvent<BuildSettings>, CarthageError> in
		var argsForLoading = buildArgs
		argsForLoading.sdk = sdk

		var argsForBuilding = argsForLoading
		argsForBuilding.onlyActiveArchitecture = false

		// If SDK is the iOS simulator, then also find and set a valid destination.
		// This fixes problems when the project deployment version is lower than
		// the target's one and includes simulators unsupported by the target.
		//
		// Example: Target is at 8.0, project at 7.0, xcodebuild chooses the first
		// simulator on the list, iPad 2 7.1, which is invalid for the target.
		//
		// See https://github.com/Carthage/Carthage/issues/417.
		func fetchDestination() -> SignalProducer<String?, CarthageError> {
			// Specifying destination seems to be required for building with
			// simulator SDKs since Xcode 7.2.
			if sdk.isSimulator {
				let destinationLookup = Task("/usr/bin/xcrun", arguments: [ "simctl", "list", "devices" ])
				return destinationLookup.launch()
					.ignoreTaskData()
					.map { data in
						let string = String(data: data, encoding: NSUTF8StringEncoding)!
						// The output as of Xcode 6.4 is structured text so we
						// parse it using regex. The destination will be omitted
						// altogether if parsing fails. Xcode 7.0 beta 4 added a
						// JSON output option as `xcrun simctl list devices --json`
						// so this can be switched once 7.0 becomes a requirement.
						let platformName = sdk.platform.rawValue
						let regex = try! NSRegularExpression(pattern: "-- \(platformName) [0-9.]+ --\\n.*?\\(([0-9A-Z]{8}-([0-9A-Z]{4}-){3}[0-9A-Z]{12})\\)", options: [])
						let lastDeviceResult = regex.matches(in: string, range: NSRange(location: 0, length: string.utf16.count)).last
						return lastDeviceResult.map { result in
							// We use the ID here instead of the name as it's guaranteed to be unique, the name isn't.
							let deviceID = (string as NSString).substringWithRange(result.rangeAt(1))
							return "platform=\(platformName) Simulator,id=\(deviceID)"
						}
					}
					.mapError(CarthageError.taskError)
			}
			return SignalProducer(value: nil)
		}

		return fetchDestination()
			.flatMap(.concat) { destination -> SignalProducer<TaskEvent<BuildSettings>, CarthageError> in
				if let destination = destination {
					argsForBuilding.destination = destination
					// Also set the destination lookup timeout. Since we're building
					// for the simulator the lookup shouldn't take more than a
					// fraction of a second, but we set to 3 just to be safe.
					argsForBuilding.destinationTimeout = 3
				}

				return BuildSettings.loadWithArguments(argsForLoading)
					.filter { settings in
						// Only copy build products for the framework type we care about.
						if let frameworkType = settings.frameworkType.value {
							return shouldBuildFrameworkType(frameworkType)
						} else {
							return false
						}
					}
					.collect()
					.flatMap(.concat) { settings -> SignalProducer<TaskEvent<BuildSettings>, CarthageError> in
						let bitcodeEnabled = settings.reduce(true) { $0 && ($1.bitcodeEnabled.value ?? false) }
						if bitcodeEnabled {
							argsForBuilding.bitcodeGenerationMode = .bitcode
						}

						var buildScheme = xcodebuildTask(["clean", "build"], argsForBuilding)
						buildScheme.workingDirectoryPath = workingDirectoryURL.carthage_path

						return buildScheme.launch()
							.flatMapTaskEvents(.concat) { _ in SignalProducer(values: settings) }
							.mapError(CarthageError.taskError)
					}
			}
	}

	return BuildSettings.SDKsForScheme(scheme, inProject: project)
		.flatMap(.concat) { sdk -> SignalProducer<SDK, CarthageError> in
			var argsForLoading = buildArgs
			argsForLoading.sdk = sdk

			return BuildSettings
				.loadWithArguments(argsForLoading)
				.filter { settings in
					// Filter out SDKs that require bitcode when bitcode is disabled in
					// project settings. This is necessary for testing frameworks, which
					// must add a User-Defined setting of ENABLE_BITCODE=NO.
					return settings.bitcodeEnabled.value == true || ![.tvOS, .watchOS].contains(sdk)
				}
				.map { _ in sdk }
		}
		.reduce([:]) { (sdksByPlatform: [Platform: Set<SDK>], sdk: SDK) in
			var sdksByPlatform = sdksByPlatform
			let platform = sdk.platform

			if var sdks = sdksByPlatform[platform] {
				sdks.insert(sdk)
				sdksByPlatform.updateValue(sdks, forKey: platform)
			} else {
				sdksByPlatform[platform] = Set(arrayLiteral: sdk)
			}

			return sdksByPlatform
		}
		.flatMap(.concat) { sdksByPlatform -> SignalProducer<(Platform, [SDK]), CarthageError> in
			if sdksByPlatform.isEmpty {
				fatalError("No SDKs found for scheme \(scheme)")
			}

			let values = sdksByPlatform.map { ($0, Array($1)) }
			return SignalProducer(values: values)
		}
		.flatMap(.concat) { platform, sdks -> SignalProducer<(Platform, [SDK]), CarthageError> in
			let filterResult = sdkFilter(sdks: sdks, scheme: scheme, configuration: configuration, project: project)
			return SignalProducer(result: filterResult.map { (platform, $0) })
		}
		.filter { _, sdks in
			return !sdks.isEmpty
		}
		.flatMap(.concat) { platform, sdks -> SignalProducer<TaskEvent<URL>, CarthageError> in
			let folderURL = workingDirectoryURL.appendingPathComponent(platform.relativePath, isDirectory: true).resolvingSymlinksInPath()

			// TODO: Generalize this further?
			switch sdks.count {
			case 1:
				return buildSDK(sdks[0])
					.flatMapTaskEvents(.merge) { settings in
						return copyBuildProductIntoDirectory(folderURL, settings).flatMap(.merge, transform: { (url) -> SignalProducer<NSURL, CarthageError> in

							if let cachedBinariesPath = cachedBinariesPath {
								let folderURL = cachedBinariesPath.appendingPathComponent(platform.relativePath, isDirectory: true).URLByResolvingSymlinksInPath!
								return copyBuildProductIntoDirectory(folderURL, settings)
							}
							
							return SignalProducer(value: url)
						})
					}

			case 2:
				let (simulatorSDKs, deviceSDKs) = SDK.splitSDKs(sdks)
				guard let deviceSDK = deviceSDKs.first else { fatalError("Could not find device SDK in \(sdks)") }
				guard let simulatorSDK = simulatorSDKs.first else { fatalError("Could not find simulator SDK in \(sdks)") }

				return settingsByTarget(buildSDK(deviceSDK))
					.flatMap(.concat) { settingsEvent -> SignalProducer<TaskEvent<(BuildSettings, BuildSettings)>, CarthageError> in
						switch settingsEvent {
						case let .Launch(task):
							return SignalProducer(value: .Launch(task))

						case let .StandardOutput(data):
							return SignalProducer(value: .StandardOutput(data))

						case let .StandardError(data):
							return SignalProducer(value: .StandardError(data))

						case let .Success(deviceSettingsByTarget):
							return settingsByTarget(buildSDK(simulatorSDK))
								.flatMapTaskEvents(.concat) { (simulatorSettingsByTarget: [String: BuildSettings]) -> SignalProducer<(BuildSettings, BuildSettings), CarthageError> in
									assert(deviceSettingsByTarget.count == simulatorSettingsByTarget.count, "Number of targets built for \(deviceSDK) (\(deviceSettingsByTarget.count)) does not match number of targets built for \(simulatorSDK) (\(simulatorSettingsByTarget.count))")

									return SignalProducer { observer, disposable in
										for (target, deviceSettings) in deviceSettingsByTarget {
											if disposable.isDisposed {
												break
											}

											let simulatorSettings = simulatorSettingsByTarget[target]
											assert(simulatorSettings != nil, "No \(simulatorSDK) build settings found for target \"\(target)\"")

											observer.send(value: (deviceSettings, simulatorSettings!))
										}

										observer.sendCompleted()
									}
								}
						}
					}
					.flatMapTaskEvents(.concat) { (deviceSettings, simulatorSettings) in
						return mergeBuildProductsIntoDirectory(deviceSettings, simulatorSettings, folderURL).flatMap(.merge, transform: { (url) -> SignalProducer<NSURL, CarthageError> in
							
							if let cachedBinariesPath = cachedBinariesPath {
								let folderURL = cachedBinariesPath.appendingPathComponent(platform.relativePath, isDirectory: true).URLByResolvingSymlinksInPath!
								return mergeBuildProductsIntoDirectory(deviceSettings, simulatorSettings, folderURL)
							}
							
							return SignalProducer(value: url)
						})

					}

			default:
				fatalError("SDK count \(sdks.count) in scheme \(scheme) is not supported")
			}
		}
		.flatMapTaskEvents(.concat) { builtProductURL -> SignalProducer<URL, CarthageError> in
			return createDebugInformation(builtProductURL)
				.then(SignalProducer(value: builtProductURL))
		}
}

public func createDebugInformation(builtProductURL: URL) -> SignalProducer<TaskEvent<URL>, CarthageError> {
	let dSYMURL = builtProductURL.appendingPathExtension("dSYM")

	let executableName = builtProductURL.deletingPathExtension().carthage_lastPathComponent
	if !executableName.isEmpty {
		let executable = builtProductURL.appendingPathComponent(executableName).carthage_path
		let dSYM = dSYMURL.carthage_path
		let dsymutilTask = Task("/usr/bin/xcrun", arguments: ["dsymutil", executable, "-o", dSYM])

		return dsymutilTask.launch()
			.mapError(CarthageError.taskError)
			.flatMapTaskEvents(.concat) { _ in SignalProducer(value: dSYMURL) }
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
public func buildDependencyProject(dependency: ProjectIdentifier, _ rootDirectoryURL: URL, withOptions options: BuildOptions, cachedBinariesPath: URL?, sdkFilter: SDKFilterCallback = { .success($0.0) }) -> SignalProducer<BuildSchemeProducer, CarthageError> {
	let rawDependencyURL = rootDirectoryURL.appendingPathComponent(dependency.relativePath, isDirectory: true)
	let dependencyURL = rawDependencyURL.resolvingSymlinksInPath()

	return symlinkBuildPathForDependencyProject(dependency, rootDirectoryURL: rootDirectoryURL)
		.flatMap(.merge) { _ -> SignalProducer<BuildSchemeProducer, CarthageError> in
			return buildInDirectory(dependencyURL, withOptions: options, cachedBinariesPath: cachedBinariesPath, sdkFilter: sdkFilter)
				.mapError { error in
					switch (dependency, error) {
					case let (_, .noSharedFrameworkSchemes(_, platforms)):
						return .noSharedFrameworkSchemes(dependency, platforms)

					case let (.gitHub(repo), .noSharedSchemes(project, _)):
						return .noSharedSchemes(project, repo)

					default:
						return error
					}
				}
		}
}

/// Creates symlink between the dependency build folder and the root build folder
///
/// Returns a signal indicating success
private func symlinkBuildPathForDependencyProject(dependency: ProjectIdentifier, rootDirectoryURL: URL) -> SignalProducer<(), CarthageError> {
	return SignalProducer.attempt {
		let rootBinariesURL = rootDirectoryURL.appendingPathComponent(CarthageBinariesFolderPath, isDirectory: true).resolvingSymlinksInPath()
		let rawDependencyURL = rootDirectoryURL.appendingPathComponent(dependency.relativePath, isDirectory: true)
		let dependencyURL = rawDependencyURL.resolvingSymlinksInPath()
		let fileManager = FileManager.`default`

		do {
			try fileManager.createDirectory(at: rootBinariesURL, withIntermediateDirectories: true)
		} catch let error as NSError {
			return .failure(.writeFailed(rootBinariesURL, error))
		}

		// Link this dependency's Carthage/Build folder to that of the root
		// project, so it can see all products built already, and so we can
		// automatically drop this dependency's product in the right place.
		let dependencyBinariesURL = dependencyURL.appendingPathComponent(CarthageBinariesFolderPath, isDirectory: true)

		do {
			try fileManager.removeItem(at: dependencyBinariesURL)
		} catch {
			let dependencyParentURL = dependencyBinariesURL.deletingLastPathComponent()

			do {
				try fileManager.createDirectory(at: dependencyParentURL, withIntermediateDirectories: true)
			} catch let error as NSError {
				return .failure(.writeFailed(dependencyParentURL, error))
			}
		}

		var isSymlink: Bool?
		do {
			isSymlink = try rawDependencyURL.resourceValues(forKeys: [ .isSymbolicLinkKey ]).isSymbolicLink
		} catch let error as NSError {
			return .failure(.readFailed(rawDependencyURL, error))
		}

		if isSymlink == true {
			// Since this dependency is itself a symlink, we'll create an
			// absolute link back to the project's Build folder.
			do {
				try fileManager.createSymbolicLink(at: dependencyBinariesURL, withDestinationURL: rootBinariesURL)
			} catch let error as NSError {
				return .failure(.writeFailed(dependencyBinariesURL, error))
			}
		} else {
			let linkDestinationPath = relativeLinkDestinationForDependencyProject(dependency, subdirectory: CarthageBinariesFolderPath)
			do {
				try fileManager.createSymbolicLink(atPath: dependencyBinariesURL.carthage_path, withDestinationPath: linkDestinationPath)
			} catch let error as NSError {
				return .failure(.writeFailed(dependencyBinariesURL, error))
			}
		}
		return .success()
	}
}

/// Builds the any shared framework schemes found within the given directory.
///
/// Returns a signal of all standard output from `xcodebuild`, and a
/// signal-of-signals representing each scheme being built.
public func buildInDirectory(directoryURL: URL, withOptions options: BuildOptions, cachedBinariesPath: URL?, sdkFilter: SDKFilterCallback = { .success($0.0) }) -> SignalProducer<BuildSchemeProducer, CarthageError> {
	precondition(directoryURL.isFileURL)

	return SignalProducer { observer, disposable in
		// Use SignalProducer.replayLazily to avoid enumerating the given directory
		// multiple times.
		let locator = buildableSchemesInDirectory(directoryURL, withConfiguration: options.configuration, forPlatforms: options.platforms)
			.replayLazily(Int.max)

		locator
			.collect()
			// Allow dependencies which have no projects, not to error out with
			// `.noSharedFrameworkSchemes`.
			.filter { projects in !projects.isEmpty }
			.flatMap(.merge) { (projects: [(ProjectLocator, [String])]) -> SignalProducer<(String, ProjectLocator), CarthageError> in
				return schemesInProjects(projects)
					.flatMap(.merge) { (schemes: [(String, ProjectLocator)]) -> SignalProducer<(String, ProjectLocator), CarthageError> in
						if !schemes.isEmpty {
							return .init(values: schemes)
						} else {
							return .init(error: .noSharedFrameworkSchemes(.git(GitURL(directoryURL.carthage_path)), options.platforms))
						}
					}
			}
			.flatMap(.merge) { scheme, project -> SignalProducer<(String, ProjectLocator), CarthageError> in
				return locator
					// This scheduler hop is required to avoid disallowed recursive signals.
					// See https://github.com/ReactiveCocoa/ReactiveCocoa/pull/2042.
					.start(on: QueueScheduler(qos: QOS_CLASS_DEFAULT, name: "org.carthage.CarthageKit.Xcode.buildInDirectory"))
					// Pick up the first workspace which can build the scheme.
					.filter { project, schemes in
						switch project {
						case .workspace where schemes.contains(scheme):
							return true

						default:
							return false
						}
					}
					// If there is no appropriate workspace, use the project in
					// which the scheme is defined instead.
					.concat(SignalProducer(value: (project, [])))
					.take(first: 1)
					.map { project, _ in (scheme, project) }
			}
			.map { (scheme: String, project: ProjectLocator) -> BuildSchemeProducer in
				let initialValue = (project, scheme)

				let wrappedSDKFilter: SDKFilterCallback = { sdks, scheme, configuration, project in
					let filteredSDKs: [SDK]
					if options.platforms.isEmpty {
						filteredSDKs = sdks
					} else {
						filteredSDKs = sdks.filter { options.platforms.contains($0.platform) }
					}

					return sdkFilter(sdks: filteredSDKs, scheme: scheme, configuration: configuration, project: project)
				}

				let buildProgress = buildScheme(scheme, withConfiguration: options.configuration, inProject: project, workingDirectoryURL: directoryURL, derivedDataPath: options.derivedDataPath, toolchain: options.toolchain, cachedBinariesPath: cachedBinariesPath, sdkFilter: wrappedSDKFilter)
					// Discard any existing Success values, since we want to
					// use our initial value instead of waiting for
					// completion.
					.map { taskEvent in
						return taskEvent.map { _ in initialValue }
					}
					.filter { taskEvent in taskEvent.value == nil }

				return BuildSchemeProducer(value: .success(initialValue))
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
public func stripFramework(frameworkURL: URL, keepingArchitectures: [String], codesigningIdentity: String? = nil) -> SignalProducer<(), CarthageError> {
	let stripArchitectures = stripBinary(frameworkURL, keepingArchitectures: keepingArchitectures)

	// Xcode doesn't copy `Headers`, `PrivateHeaders` and `Modules` directory at
	// all.
	let stripHeaders = stripHeadersDirectory(frameworkURL)
	let stripPrivateHeaders = stripPrivateHeadersDirectory(frameworkURL)
	let stripModules = stripModulesDirectory(frameworkURL)

	let sign = codesigningIdentity.map { codesign(frameworkURL, $0) } ?? .empty

	return stripArchitectures
		.concat(stripHeaders)
		.concat(stripPrivateHeaders)
		.concat(stripModules)
		.concat(sign)
}

/// Strips a dSYM from unexpected architectures.
public func stripDSYM(dSYMURL: URL, keepingArchitectures: [String]) -> SignalProducer<(), CarthageError> {
	return stripBinary(dSYMURL, keepingArchitectures: keepingArchitectures)
}

/// Strips a universal file from unexpected architectures.
private func stripBinary(binaryURL: URL, keepingArchitectures: [String]) -> SignalProducer<(), CarthageError> {
	return architecturesInPackage(binaryURL)
		.filter { !keepingArchitectures.contains($0) }
		.flatMap(.concat) { stripArchitecture(binaryURL, $0) }
}

/// Copies a product into the given folder. The folder will be created if it
/// does not already exist, and any pre-existing version of the product in the
/// destination folder will be deleted before the copy of the new version.
///
/// If the `from` URL has the same path as the `to` URL, and there is a resource
/// at the given path, no operation is needed and the returned signal will just
/// send `.success`.
///
/// Returns a signal that will send the URL after copying upon .success.
public func copyProduct(from: URL, _ to: URL) -> SignalProducer<URL, CarthageError> {
	return SignalProducer<URL, CarthageError>.attempt {
		let manager = FileManager.`default`

		// This signal deletes `to` before it copies `from` over it.
		// If `from` and `to` point to the same resource, there's no need to perform a copy at all
		// and deleting `to` will also result in deleting the original resource without copying it.
		// When `from` and `to` are the same, we can just return success immediately.
		//
		// See https://github.com/Carthage/Carthage/pull/1160
		if manager.fileExists(atPath: to.carthage_path) && from.absoluteURL == to.absoluteURL {
			return .success(to)
		}

		do {
			try manager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
		} catch let error as NSError {
			// Although the method's documentation says: “YES if createIntermediates
			// is set and the directory already exists)”, it seems to rarely
			// returns NO and NSFileWriteFileExistsError error. So we should
			// ignore that specific error.
			//
			// See https://github.com/Carthage/Carthage/issues/591
			if error.code != NSFileWriteFileExistsError {
				return .failure(.writeFailed(to.deletingLastPathComponent(), error))
			}
		}

		do {
			try manager.removeItem(at: to)
		} catch let error as NSError {
			if error.code != NSFileNoSuchFileError {
				return .failure(.writeFailed(to, error))
			}
		}

		do {
			try manager.copyItem(at: from, to: to)
			return .success(to)
		} catch let error as NSError {
			return .failure(.writeFailed(to, error))
		}
	}
}

extension SignalProducerProtocol where Value == URL, Error == CarthageError {
	/// Copies existing files sent from the producer into the given directory.
	///
	/// Returns a producer that will send locations where the copied files are.
	public func copyFileURLsIntoDirectory(directoryURL: URL) -> SignalProducer<URL, CarthageError> {
		return producer
			.filter { fileURL in fileURL.checkResourceIsReachableAndReturnError(nil) }
			.flatMap(.merge) { fileURL -> SignalProducer<URL, CarthageError> in
				let fileName = fileURL.carthage_lastPathComponent
				let destinationURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
				let resolvedDestinationURL = destinationURL.resolvingSymlinksInPath()

				return copyProduct(fileURL, resolvedDestinationURL)
			}
	}
}

/// Strips the given architecture from a framework.
private func stripArchitecture(frameworkURL: URL, _ architecture: String) -> SignalProducer<(), CarthageError> {
	return SignalProducer.attempt { () -> Result<URL, CarthageError> in
			return binaryURL(frameworkURL)
		}
		.flatMap(.merge) { binaryURL -> SignalProducer<TaskEvent<Data>, CarthageError> in
			let lipoTask = Task("/usr/bin/xcrun", arguments: [ "lipo", "-remove", architecture, "-output", binaryURL.carthage_path , binaryURL.carthage_path])
			return lipoTask.launch()
				.mapError(CarthageError.taskError)
		}
		.then(.empty)
}

/// Returns a signal of all architectures present in a given package.
public func architecturesInPackage(packageURL: URL) -> SignalProducer<String, CarthageError> {
	return SignalProducer.attempt { () -> Result<URL, CarthageError> in
			return binaryURL(packageURL)
		}
		.flatMap(.merge) { binaryURL -> SignalProducer<String, CarthageError> in
			let lipoTask = Task("/usr/bin/xcrun", arguments: [ "lipo", "-info", binaryURL.carthage_path])

			return lipoTask.launch()
				.ignoreTaskData()
				.mapError(CarthageError.taskError)
				.map { String(data: $0, encoding: NSUTF8StringEncoding) ?? "" }
				.flatMap(.merge) { output -> SignalProducer<String, CarthageError> in
					let characterSet = NSMutableCharacterSet.alphanumeric()
					characterSet.addCharacters(in: " _-")

					let scanner = Scanner(string: output)

					if scanner.scanString("Architectures in the fat file:", into: nil) {
						// The output of "lipo -info PathToBinary" for fat files
						// looks roughly like so:
						//
						//     Architectures in the fat file: PathToBinary are: armv7 arm64
						//
						var architectures: NSString?

						scanner.scanString(binaryURL.carthage_path, into: nil)
						scanner.scanString("are:", into: nil)
						scanner.scanCharacters(from: characterSet, into: &architectures)

						let components = architectures?
							.componentsSeparatedByString(" ")
							.filter { !$0.isEmpty }

						if let components = components {
							return SignalProducer(values: components)
						}
					}

					if scanner.scanString("Non-fat file:", into: nil) {
						// The output of "lipo -info PathToBinary" for thin
						// files looks roughly like so:
						//
						//     Non-fat file: PathToBinary is architecture: x86_64
						//
						var architecture: NSString?

						scanner.scanString(binaryURL.carthage_path, into: nil)
						scanner.scanString("is architecture:", into: nil)
						scanner.scanCharacters(from: characterSet, into: &architecture)

						if let architecture = architecture {
							return SignalProducer(value: architecture as String)
						}
					}

					return SignalProducer(error: .invalidArchitectures(description: "Could not read architectures from \(packageURL.carthage_path)"))
				}
		}
}

/// Strips `Headers` directory from the given framework.
public func stripHeadersDirectory(frameworkURL: URL) -> SignalProducer<(), CarthageError> {
	return stripDirectory(named: "Headers", of: frameworkURL)
}

/// Strips `PrivateHeaders` directory from the given framework.
public func stripPrivateHeadersDirectory(frameworkURL: URL) -> SignalProducer<(), CarthageError> {
	return stripDirectory(named: "PrivateHeaders", of: frameworkURL)
}

/// Strips `Modules` directory from the given framework.
public func stripModulesDirectory(frameworkURL: URL) -> SignalProducer<(), CarthageError> {
	return stripDirectory(named: "Modules", of: frameworkURL)
}

private func stripDirectory(named directory: String, of frameworkURL: URL) -> SignalProducer<(), CarthageError> {
	return SignalProducer.attempt {
		let directoryURLToStrip = frameworkURL.appendingPathComponent(directory, isDirectory: true)

		var isDirectory: ObjCBool = false
		if !FileManager.`default`.fileExists(atPath: directoryURLToStrip.carthage_path, isDirectory: &isDirectory) || !isDirectory {
			return .success(())
		}

		do {
			try FileManager.`default`.removeItem(at: directoryURLToStrip)
		} catch let error as NSError {
			return .failure(.writeFailed(directoryURLToStrip, error))
		}

		return .success(())
	}
}

/// Sends a set of UUIDs for each architecture present in the given framework.
public func UUIDsForFramework(frameworkURL: URL) -> SignalProducer<Set<UUID>, CarthageError> {
	return SignalProducer.attempt { () -> Result<URL, CarthageError> in
			return binaryURL(frameworkURL)
		}
		.flatMap(.merge, transform: UUIDsFromDwarfdump)
}

/// Sends a set of UUIDs for each architecture present in the given dSYM.
public func UUIDsForDSYM(dSYMURL: URL) -> SignalProducer<Set<UUID>, CarthageError> {
	return UUIDsFromDwarfdump(dSYMURL)
}

/// Sends an URL for each bcsymbolmap file for the given framework.
/// The files do not necessarily exist on disk.
///
/// The returned URLs are relative to the parent directory of the framework.
public func BCSymbolMapsForFramework(frameworkURL: URL) -> SignalProducer<URL, CarthageError> {
	let directoryURL = frameworkURL.deletingLastPathComponent()
	return UUIDsForFramework(frameworkURL)
		.flatMap(.merge) { uuids in SignalProducer<UUID, CarthageError>(values: uuids) }
		.map { uuid in
			return directoryURL.appendingPathComponent(uuid.uuidString, isDirectory: false).appendingPathExtension("bcsymbolmap")
		}
}

/// Sends a set of UUIDs for each architecture present in the given URL.
private func UUIDsFromDwarfdump(url: URL) -> SignalProducer<Set<UUID>, CarthageError> {
	let dwarfdumpTask = Task("/usr/bin/xcrun", arguments: [ "dwarfdump", "--uuid", url.carthage_path ])

	return dwarfdumpTask.launch()
		.ignoreTaskData()
		.mapError(CarthageError.taskError)
		.map { String(data: $0, encoding: NSUTF8StringEncoding) ?? "" }
		.flatMap(.merge) { output -> SignalProducer<Set<UUID>, CarthageError> in
			// UUIDs are letters, decimals, or hyphens.
			let uuidCharacterSet = NSMutableCharacterSet()
			uuidCharacterSet.formUnion(with: .letters)
			uuidCharacterSet.formUnion(with: .decimalDigits)
			uuidCharacterSet.formUnion(with: CharacterSet(charactersIn: "-"))

			let scanner = Scanner(string: output)
			var uuids = Set<UUID>()

			// The output of dwarfdump is a series of lines formatted as follows
			// for each architecture:
			//
			//     UUID: <UUID> (<Architecture>) <PathToBinary>
			//
			while !scanner.isAtEnd {
				scanner.scanString("UUID: ", into: nil)

				var uuidString: NSString?
				scanner.scanCharacters(from: uuidCharacterSet, into: &uuidString)

				if let uuidString = uuidString as? String, let uuid = UUID(uuidString: uuidString) {
					uuids.insert(uuid)
				}

				// Scan until a newline or end of file.
				scanner.scanUpToCharacters(from: .newlines, into: nil)
			}

			if !uuids.isEmpty {
				return SignalProducer(value: uuids)
			} else {
				return SignalProducer(error: .invalidUUIDs(description: "Could not parse UUIDs using dwarfdump from \(url.carthage_path)"))
			}
		}
}

/// Returns the URL of a binary inside a given package.
private func binaryURL(packageURL: URL) -> Result<URL, CarthageError> {
	let bundle = Bundle(path: packageURL.carthage_path)
	let packageType = (bundle?.object(forInfoDictionaryKey: "CFBundlePackageType") as? String).flatMap(PackageType.init)

	switch packageType {
	case .framework?, .bundle?:
		if let binaryName = bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String {
			return .success(packageURL.appendingPathComponent(binaryName))
		}

	case .dSYM?:
		let binaryName = packageURL.deletingPathExtension().deletingPathExtension().carthage_lastPathComponent
		if !binaryName.isEmpty {
			let binaryURL = packageURL.appendingPathComponent("Contents/Resources/DWARF/\(binaryName)")
			return .success(binaryURL)
		}

	default:
		break
	}

	return .failure(.readFailed(packageURL, nil))
}

/// Signs a framework with the given codesigning identity.
private func codesign(frameworkURL: URL, _ expandedIdentity: String) -> SignalProducer<(), CarthageError> {
	let codesignTask = Task("/usr/bin/xcrun", arguments: [ "codesign", "--force", "--sign", expandedIdentity, "--preserve-metadata=identifier,entitlements", frameworkURL.carthage_path ])

	return codesignTask.launch()
		.mapError(CarthageError.taskError)
		.then(.empty)
}
