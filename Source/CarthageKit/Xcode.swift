// swiftlint:disable file_length

import Foundation
import Result
import ReactiveSwift
import ReactiveTask
import XCDBLD

/// Emits the currect Swift version
internal func swiftVersion(usingToolchain toolchain: String? = nil) -> SignalProducer<String, SwiftVersionError> {
	return determineSwiftVersion(usingToolchain: toolchain).replayLazily(upTo: 1)
}

/// Attempts to determine the local version of swift
private func determineSwiftVersion(usingToolchain toolchain: String?) -> SignalProducer<String, SwiftVersionError> {
	let taskDescription = Task("/usr/bin/env", arguments: compilerVersionArguments(usingToolchain: toolchain))

	return taskDescription.launch(standardInput: nil)
		.ignoreTaskData()
		.mapError { _ in SwiftVersionError.unknownLocalSwiftVersion }
		.map { data -> String? in
			return parseSwiftVersionCommand(output: String(data: data, encoding: .utf8))
		}
		.attemptMap { Result($0, failWith: SwiftVersionError.unknownLocalSwiftVersion) }
}

private func compilerVersionArguments(usingToolchain toolchain: String?) -> [String] {
	if let toolchain = toolchain {
		return ["xcrun", "--toolchain", toolchain, "swift", "--version"]
	} else {
		return ["xcrun", "swift", "--version"]
	}
}

/// Parses output of `swift --version` for the version string.
private func parseSwiftVersionCommand(output: String?) -> String? {
	guard
		let output = output,
		let regex = try? NSRegularExpression(pattern: "Apple Swift version ([^\\s]+) .*\\((.+)\\)", options: []),
		let match = regex.firstMatch(in: output, options: [], range: NSRange(output.startIndex..., in: output))
		else
	{
		return nil
	}

	guard match.numberOfRanges == 3 else { return nil }

	let first = output[Range(match.range(at: 1), in: output)!]
	let second = output[Range(match.range(at: 2), in: output)!]
	return "\(first) (\(second))"
}

/// Determines the Swift version of a framework at a given `URL`.
internal func frameworkSwiftVersion(_ frameworkURL: URL) -> SignalProducer<String, SwiftVersionError> {
	guard
		let swiftHeaderURL = frameworkURL.swiftHeaderURL(),
		let data = try? Data(contentsOf: swiftHeaderURL),
		let contents = String(data: data, encoding: .utf8),
		let swiftVersion = parseSwiftVersionCommand(output: contents)
		else {
			return SignalProducer(error: .unknownFrameworkSwiftVersion)
	}

	return SignalProducer(value: swiftVersion)
}

/// Determines whether a framework was built with Swift
internal func isSwiftFramework(_ frameworkURL: URL) -> Bool {
	return frameworkURL.swiftmoduleURL() != nil
}

/// Emits the framework URL if it matches the local Swift version and errors if not.
internal func checkSwiftFrameworkCompatibility(_ frameworkURL: URL, usingToolchain toolchain: String?) -> SignalProducer<URL, SwiftVersionError> {
	return SignalProducer.combineLatest(swiftVersion(usingToolchain: toolchain), frameworkSwiftVersion(frameworkURL))
		.attemptMap { localSwiftVersion, frameworkSwiftVersion in
			return localSwiftVersion == frameworkSwiftVersion
				? .success(frameworkURL)
				: .failure(.incompatibleFrameworkSwiftVersions(local: localSwiftVersion, framework: frameworkSwiftVersion))
		}
}

/// Emits the framework URL if it is compatible with the build environment and errors if not.
internal func checkFrameworkCompatibility(_ frameworkURL: URL, usingToolchain toolchain: String?) -> SignalProducer<URL, SwiftVersionError> {
	if isSwiftFramework(frameworkURL) {
		return checkSwiftFrameworkCompatibility(frameworkURL, usingToolchain: toolchain)
	} else {
		return SignalProducer(value: frameworkURL)
	}
}

/// Creates a task description for executing `xcodebuild` with the given
/// arguments.
public func xcodebuildTask(_ tasks: [String], _ buildArguments: BuildArguments) -> Task {
	return Task("/usr/bin/xcrun", arguments: buildArguments.arguments + tasks)
}

/// Creates a task description for executing `xcodebuild` with the given
/// arguments.
public func xcodebuildTask(_ task: String, _ buildArguments: BuildArguments) -> Task {
	return xcodebuildTask([task], buildArguments)
}

/// Finds schemes of projects or workspaces, which Carthage should build, found
/// within the given directory.
public func buildableSchemesInDirectory(
	_ directoryURL: URL,
	withConfiguration configuration: String,
	forPlatforms platforms: Set<Platform> = []
) -> SignalProducer<(ProjectLocator, [Scheme]), CarthageError> {
	precondition(directoryURL.isFileURL)

	return ProjectLocator
		.locate(in: directoryURL)
		.flatMap(.concat) { project -> SignalProducer<(ProjectLocator, [Scheme]), CarthageError> in
			return project
				.schemes()
				.flatMap(.concurrent(limit: 4)) { scheme -> SignalProducer<Scheme, CarthageError> in
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
public func schemesInProjects(_ projects: [(ProjectLocator, [Scheme])]) -> SignalProducer<[(Scheme, ProjectLocator)], CarthageError> {
	return SignalProducer<(ProjectLocator, [Scheme]), CarthageError>(projects)
		.map { (project: ProjectLocator, schemes: [Scheme]) in
			// Only look for schemes that actually reside in the project
			let containedSchemes = schemes.filter { scheme -> Bool in
				let schemePath = project.fileURL.appendingPathComponent("xcshareddata/xcschemes/\(scheme).xcscheme").path
				return FileManager.default.fileExists(atPath: schemePath)
			}
			return (project, containedSchemes)
		}
		.filter { (project: ProjectLocator, schemes: [Scheme]) in
			switch project {
			case .projectFile where !schemes.isEmpty:
				return true

			default:
				return false
			}
		}
		.flatMap(.concat) { project, schemes in
			return SignalProducer<(Scheme, ProjectLocator), CarthageError>(schemes.map { ($0, project) })
		}
		.collect()
}

/// Describes the type of frameworks.
internal enum FrameworkType {
	/// A dynamic framework.
	case dynamic

	/// A static framework.
	case `static`

	init?(productType: ProductType, machOType: MachOType) {
		switch (productType, machOType) {
		case (.framework, .dylib):
			self = .dynamic

		case (.framework, .staticlib):
			self = .static

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

/// Finds the built product for the given settings, then copies it (preserving
/// its name) into the given folder. The folder will be created if it does not
/// already exist.
///
/// If this built product has any *.bcsymbolmap files they will also be copied.
///
/// Returns a signal that will send the URL after copying upon .success.
private func copyBuildProductIntoDirectory(_ directoryURL: URL, _ settings: BuildSettings) -> SignalProducer<URL, CarthageError> {
	let target = settings.wrapperName.map(directoryURL.appendingPathComponent)
	return SignalProducer(result: target.fanout(settings.wrapperURL))
		.flatMap(.merge) { target, source in
			return copyProduct(source.resolvingSymlinksInPath(), target)
		}
		.flatMap(.merge) { url in
			return copyBCSymbolMapsForBuildProductIntoDirectory(directoryURL, settings)
				.then(SignalProducer<URL, CarthageError>(value: url))
		}
}

/// Finds any *.bcsymbolmap files for the built product and copies them into
/// the given folder. Does nothing if bitcode is disabled.
///
/// Returns a signal that will send the URL after copying for each file.
private func copyBCSymbolMapsForBuildProductIntoDirectory(_ directoryURL: URL, _ settings: BuildSettings) -> SignalProducer<URL, CarthageError> {
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
private func mergeExecutables(_ executableURLs: [URL], _ outputURL: URL) -> SignalProducer<(), CarthageError> {
	precondition(outputURL.isFileURL)

	return SignalProducer<URL, CarthageError>(executableURLs)
		.attemptMap { url -> Result<String, CarthageError> in
			if url.isFileURL {
				return .success(url.path)
			} else {
				return .failure(.parseError(description: "expected file URL to built executable, got \(url)"))
			}
		}
		.collect()
		.flatMap(.merge) { executablePaths -> SignalProducer<TaskEvent<Data>, CarthageError> in
			let lipoTask = Task("/usr/bin/xcrun", arguments: [ "lipo", "-create" ] + executablePaths + [ "-output", outputURL.path ])

			return lipoTask.launch()
				.mapError(CarthageError.taskError)
		}
		.then(SignalProducer<(), CarthageError>.empty)
}

/// If the given source URL represents an LLVM module, copies its contents into
/// the destination module.
///
/// Sends the URL to each file after copying.
private func mergeModuleIntoModule(_ sourceModuleDirectoryURL: URL, _ destinationModuleDirectoryURL: URL) -> SignalProducer<URL, CarthageError> {
	precondition(sourceModuleDirectoryURL.isFileURL)
	precondition(destinationModuleDirectoryURL.isFileURL)

	return FileManager.default.reactive
		.enumerator(at: sourceModuleDirectoryURL, includingPropertiesForKeys: [], options: [ .skipsSubdirectoryDescendants, .skipsHiddenFiles ], catchErrors: true)
		.attemptMap { _, url -> Result<URL, CarthageError> in
			let lastComponent = url.lastPathComponent
			let destinationURL = destinationModuleDirectoryURL.appendingPathComponent(lastComponent).resolvingSymlinksInPath()

			return Result(at: destinationURL, attempt: {
				try FileManager.default.copyItem(at: url, to: $0, avoiding·rdar·32984063: true)
				return $0
			})
		}
}

/// Determines whether the specified framework type should be built automatically.
private func shouldBuildFrameworkType(_ frameworkType: FrameworkType?) -> Bool {
	return frameworkType == .dynamic
}

/// Determines whether the given scheme should be built automatically.
private func shouldBuildScheme(_ buildArguments: BuildArguments, _ forPlatforms: Set<Platform>) -> SignalProducer<Bool, CarthageError> {
	precondition(buildArguments.scheme != nil)

	return BuildSettings.load(with: buildArguments)
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
private func settingsByTarget<Error>(_ producer: SignalProducer<TaskEvent<BuildSettings>, Error>) -> SignalProducer<TaskEvent<[String: BuildSettings]>, Error> {
	return SignalProducer { observer, lifetime in
		var settings: [String: BuildSettings] = [:]

		producer.startWithSignal { signal, signalDisposable in
			lifetime += signalDisposable

			signal.observe { event in
				switch event {
				case let .value(settingsEvent):
					let transformedEvent = settingsEvent.map { settings in [ settings.target: settings ] }

					if let transformed = transformedEvent.value {
						settings.merge(transformed) { _, new in new }
					} else {
						observer.send(value: transformedEvent)
					}

				case let .failed(error):
					observer.send(error: error)

				case .completed:
					observer.send(value: .success(settings))
					observer.sendCompleted()

				case .interrupted:
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
private func mergeBuildProducts(
	deviceBuildSettings: BuildSettings,
	simulatorBuildSettings: BuildSettings,
	into destinationFolderURL: URL
) -> SignalProducer<URL, CarthageError> {
	return copyBuildProductIntoDirectory(destinationFolderURL, deviceBuildSettings)
		.flatMap(.merge) { productURL -> SignalProducer<URL, CarthageError> in
			let executableURLs = (deviceBuildSettings.executableURL.fanout(simulatorBuildSettings.executableURL)).map { [ $0, $1 ] }
			let outputURL = deviceBuildSettings.executablePath.map(destinationFolderURL.appendingPathComponent)

			let mergeProductBinaries = SignalProducer(result: executableURLs.fanout(outputURL))
				.flatMap(.concat) { (executableURLs: [URL], outputURL: URL) -> SignalProducer<(), CarthageError> in
					return mergeExecutables(
						executableURLs.map { $0.resolvingSymlinksInPath() },
						outputURL.resolvingSymlinksInPath()
					)
				}

			let sourceModulesURL = SignalProducer(result: simulatorBuildSettings.relativeModulesPath.fanout(simulatorBuildSettings.builtProductsDirectoryURL))
				.filter { $0.0 != nil }
				.map { modulesPath, productsURL in
					return productsURL.appendingPathComponent(modulesPath!)
				}

			let destinationModulesURL = SignalProducer(result: deviceBuildSettings.relativeModulesPath)
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
				.then(copyBCSymbolMapsForBuildProductIntoDirectory(destinationFolderURL, simulatorBuildSettings))
				.then(SignalProducer<URL, CarthageError>(value: productURL))
		}
}

/// A callback function used to determine whether or not an SDK should be built
public typealias SDKFilterCallback = (_ sdks: [SDK], _ scheme: Scheme, _ configuration: String, _ project: ProjectLocator) -> Result<[SDK], CarthageError>

/// Builds one scheme of the given project, for all supported SDKs.
///
/// Returns a signal of all standard output from `xcodebuild`, and a signal
/// which will send the URL to each product successfully built.
public func buildScheme( // swiftlint:disable:this function_body_length cyclomatic_complexity
	_ scheme: Scheme,
	withOptions options: BuildOptions,
	inProject project: ProjectLocator,
	workingDirectoryURL: URL,
	sdkFilter: @escaping SDKFilterCallback = { sdks, _, _, _ in .success(sdks) }
) -> SignalProducer<TaskEvent<URL>, CarthageError> {
	precondition(workingDirectoryURL.isFileURL)

	let buildArgs = BuildArguments(
		project: project,
		scheme: scheme,
		configuration: options.configuration,
		derivedDataPath: options.derivedDataPath,
		toolchain: options.toolchain
	)

	return BuildSettings.SDKsForScheme(scheme, inProject: project)
		.flatMap(.concat) { sdk -> SignalProducer<SDK, CarthageError> in
			var argsForLoading = buildArgs
			argsForLoading.sdk = sdk

			return BuildSettings
				.load(with: argsForLoading)
				.filter { settings in
					// Filter out SDKs that require bitcode when bitcode is disabled in
					// project settings. This is necessary for testing frameworks, which
					// must add a User-Defined setting of ENABLE_BITCODE=NO.
					return settings.bitcodeEnabled.value == true || ![.tvOS, .watchOS].contains(sdk)
				}
				.map { _ in sdk }
		}
		.reduce(into: [:]) { (sdksByPlatform: inout [Platform: Set<SDK>], sdk: SDK) in
			let platform = sdk.platform

			if var sdks = sdksByPlatform[platform] {
				sdks.insert(sdk)
				sdksByPlatform.updateValue(sdks, forKey: platform)
			} else {
				sdksByPlatform[platform] = [sdk]
			}
		}
		.flatMap(.concat) { sdksByPlatform -> SignalProducer<(Platform, [SDK]), CarthageError> in
			if sdksByPlatform.isEmpty {
				fatalError("No SDKs found for scheme \(scheme)")
			}

			let values = sdksByPlatform.map { ($0, Array($1)) }
			return SignalProducer(values)
		}
		.flatMap(.concat) { platform, sdks -> SignalProducer<(Platform, [SDK]), CarthageError> in
			let filterResult = sdkFilter(sdks, scheme, options.configuration, project)
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
				return build(sdk: sdks[0], with: buildArgs, in: workingDirectoryURL)
					.flatMapTaskEvents(.merge) { settings in
						return copyBuildProductIntoDirectory(folderURL, settings)
					}

			case 2:
				let (simulatorSDKs, deviceSDKs) = SDK.splitSDKs(sdks)
				guard let deviceSDK = deviceSDKs.first else {
					fatalError("Could not find device SDK in \(sdks)")
				}
				guard let simulatorSDK = simulatorSDKs.first else {
					fatalError("Could not find simulator SDK in \(sdks)")
				}

				return settingsByTarget(build(sdk: deviceSDK, with: buildArgs, in: workingDirectoryURL))
					.flatMap(.concat) { settingsEvent -> SignalProducer<TaskEvent<(BuildSettings, BuildSettings)>, CarthageError> in
						switch settingsEvent {
						case let .launch(task):
							return SignalProducer(value: .launch(task))

						case let .standardOutput(data):
							return SignalProducer(value: .standardOutput(data))

						case let .standardError(data):
							return SignalProducer(value: .standardError(data))

						case let .success(deviceSettingsByTarget):
							return settingsByTarget(build(sdk: simulatorSDK, with: buildArgs, in: workingDirectoryURL))
								.flatMapTaskEvents(.concat) { (simulatorSettingsByTarget: [String: BuildSettings]) -> SignalProducer<(BuildSettings, BuildSettings), CarthageError> in
									assert(
										deviceSettingsByTarget.count == simulatorSettingsByTarget.count,
										"Number of targets built for \(deviceSDK) (\(deviceSettingsByTarget.count)) does not match "
											+ "number of targets built for \(simulatorSDK) (\(simulatorSettingsByTarget.count))"
									)

									return SignalProducer { observer, lifetime in
										for (target, deviceSettings) in deviceSettingsByTarget {
											if lifetime.hasEnded {
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
					.flatMapTaskEvents(.concat) { deviceSettings, simulatorSettings in
						return mergeBuildProducts(
							deviceBuildSettings: deviceSettings,
							simulatorBuildSettings: simulatorSettings,
							into: folderURL
						)
					}

			default:
				fatalError("SDK count \(sdks.count) in scheme \(scheme) is not supported")
			}
		}
		.flatMapTaskEvents(.concat) { builtProductURL -> SignalProducer<URL, CarthageError> in
			return UUIDsForFramework(builtProductURL)
				.collect()
				.flatMap(.concat) { uuids -> SignalProducer<TaskEvent<URL>, CarthageError> in
					// Only attempt to create debug info if there is at least 
					// one dSYM architecture UUID in the framework. This can 
					// occur if the framework is a static framework packaged 
					// like a dynamic framework.
					if uuids.isEmpty {
						return .empty
					}

					return createDebugInformation(builtProductURL)
				}
				.then(SignalProducer<URL, CarthageError>(value: builtProductURL))
		}
}

/// Runs the build for a given sdk and build arguments, optionally performing a clean first
private func build(sdk: SDK, with buildArgs: BuildArguments, in workingDirectoryURL: URL) -> SignalProducer<TaskEvent<BuildSettings>, CarthageError> {
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
					let string = String(data: data, encoding: .utf8)!
					// The output as of Xcode 6.4 is structured text so we
					// parse it using regex. The destination will be omitted
					// altogether if parsing fails. Xcode 7.0 beta 4 added a
					// JSON output option as `xcrun simctl list devices --json`
					// so this can be switched once 7.0 becomes a requirement.
					let platformName = sdk.platform.rawValue
					let regex = try! NSRegularExpression( // swiftlint:disable:this force_try
						pattern: "-- \(platformName) [0-9.]+ --\\n.*?\\(([0-9A-Z]{8}-([0-9A-Z]{4}-){3}[0-9A-Z]{12})\\)",
						options: []
					)
					let lastDeviceResult = regex.matches(in: string, range: NSRange(string.startIndex..., in: string)).last
					return lastDeviceResult.map { result in
						// We use the ID here instead of the name as it's guaranteed to be unique, the name isn't.
						let deviceID = string[Range(result.range(at: 1), in: string)!]
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

			// Use `archive` action when building device SDKs to disable LLVM Instrumentation.
			//
			// See https://github.com/Carthage/Carthage/issues/2056
			// and https://developer.apple.com/library/content/qa/qa1964/_index.html.
			let xcodebuildAction: BuildArguments.Action = sdk.isDevice ? .archive : .build
			return BuildSettings.load(with: argsForLoading, for: xcodebuildAction)
				.filter { settings in
					// Only copy build products that are dynamic frameworks
					guard let frameworkType = settings.frameworkType.value, shouldBuildFrameworkType(frameworkType), let projectPath = settings.projectPath.value else {
						return false
					}

					// Do not copy build products that originate from the current project's own carthage dependencies
					let projectURL = URL(fileURLWithPath: projectPath)
					let dependencyCheckoutDir = workingDirectoryURL.appendingPathComponent(carthageProjectCheckoutsPath, isDirectory: true)
					return !dependencyCheckoutDir.hasSubdirectory(projectURL)
				}
				.collect()
				.flatMap(.concat) { settings -> SignalProducer<TaskEvent<BuildSettings>, CarthageError> in
					let bitcodeEnabled = settings.reduce(true) { $0 && ($1.bitcodeEnabled.value ?? false) }
					if bitcodeEnabled {
						argsForBuilding.bitcodeGenerationMode = .bitcode
					}

					let actions: [String] = {
						var result: [String] = [xcodebuildAction.rawValue]

						if xcodebuildAction == .archive {
							result += [
								// Prevent generating unnecessary empty `.xcarchive`
								// directories.
								"-archivePath", (NSTemporaryDirectory() as NSString).appendingPathComponent(workingDirectoryURL.lastPathComponent),

								// Disable installing when running `archive` action
								// to prevent built frameworks from being deleted
								// from derived data folder.
								"SKIP_INSTALL=YES",

								// Disable the “Instrument Program Flow” build
								// setting for both GCC and LLVM as noted in
								// https://developer.apple.com/library/content/qa/qa1964/_index.html.
								"GCC_INSTRUMENT_PROGRAM_FLOW_ARCS=NO",

								// Disable the “Generate Test Coverage Files” build
								// setting for GCC as noted in
								// https://developer.apple.com/library/content/qa/qa1964/_index.html.
								"CLANG_ENABLE_CODE_COVERAGE=NO",
							]
						}

						return result
					}()

					var buildScheme = xcodebuildTask(actions, argsForBuilding)
					buildScheme.workingDirectoryPath = workingDirectoryURL.path

					return buildScheme.launch()
						.flatMapTaskEvents(.concat) { _ in SignalProducer(settings) }
						.mapError(CarthageError.taskError)
				}
		}
}

/// Creates a dSYM for the provided dynamic framework.
public func createDebugInformation(_ builtProductURL: URL) -> SignalProducer<TaskEvent<URL>, CarthageError> {
	let dSYMURL = builtProductURL.appendingPathExtension("dSYM")

	let executableName = builtProductURL.deletingPathExtension().lastPathComponent
	if !executableName.isEmpty {
		let executable = builtProductURL.appendingPathComponent(executableName).path
		let dSYM = dSYMURL.path
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
public typealias BuildSchemeProducer = SignalProducer<TaskEvent<(ProjectLocator, Scheme)>, CarthageError>

/// Attempts to build the dependency, then places its build product into the
/// root directory given.
///
/// Returns producers in the same format as buildInDirectory().
public func build(
	dependency: Dependency,
	version: PinnedVersion,
	_ rootDirectoryURL: URL,
	withOptions options: BuildOptions,
	sdkFilter: @escaping SDKFilterCallback = { sdks, _, _, _ in .success(sdks) }
) -> SignalProducer<BuildSchemeProducer, CarthageError> {
	let rawDependencyURL = rootDirectoryURL.appendingPathComponent(dependency.relativePath, isDirectory: true)
	let dependencyURL = rawDependencyURL.resolvingSymlinksInPath()

	return symlinkBuildPath(for: dependency, rootDirectoryURL: rootDirectoryURL)
		.map { _ -> BuildSchemeProducer in
			return buildInDirectory(dependencyURL, withOptions: options, dependency: (dependency, version), rootDirectoryURL: rootDirectoryURL, sdkFilter: sdkFilter)
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
private func symlinkBuildPath(for dependency: Dependency, rootDirectoryURL: URL) -> SignalProducer<(), CarthageError> {
	return SignalProducer { () -> Result<(), CarthageError> in
		let rootBinariesURL = rootDirectoryURL.appendingPathComponent(Constants.binariesFolderPath, isDirectory: true).resolvingSymlinksInPath()
		let rawDependencyURL = rootDirectoryURL.appendingPathComponent(dependency.relativePath, isDirectory: true)
		let dependencyURL = rawDependencyURL.resolvingSymlinksInPath()
		let fileManager = FileManager.default

		// Link this dependency's Carthage/Build folder to that of the root
		// project, so it can see all products built already, and so we can
		// automatically drop this dependency's product in the right place.
		let dependencyBinariesURL = dependencyURL.appendingPathComponent(Constants.binariesFolderPath, isDirectory: true)

		let createDirectory = { try fileManager.createDirectory(at: $0, withIntermediateDirectories: true) }
		return Result(at: rootBinariesURL, attempt: createDirectory)
			.flatMap { _ in
				Result(at: dependencyBinariesURL, attempt: fileManager.removeItem(at:))
					.recover(with: Result(at: dependencyBinariesURL.deletingLastPathComponent(), attempt: createDirectory))
			}
			.flatMap { _ in
				Result(at: rawDependencyURL, carthageError: CarthageError.readFailed, attempt: {
						try $0.resourceValues(forKeys: [ .isSymbolicLinkKey ]).isSymbolicLink
					})
					.flatMap { isSymlink in
						Result(at: dependencyBinariesURL, attempt: {
							if isSymlink == true {
								return try fileManager.createSymbolicLink(at: $0, withDestinationURL: rootBinariesURL)
							} else {
								let linkDestinationPath = relativeLinkDestination(for: dependency, subdirectory: Constants.binariesFolderPath)
								return try fileManager.createSymbolicLink(atPath: $0.path, withDestinationPath: linkDestinationPath)
							}
						})
					}
			}
	}
}

/// Builds the any shared framework schemes found within the given directory.
///
/// Returns a signal of all standard output from `xcodebuild`, and each scheme being built.
public func buildInDirectory(
	_ directoryURL: URL,
	withOptions options: BuildOptions,
	dependency: (dependency: Dependency, version: PinnedVersion)? = nil,
	rootDirectoryURL: URL? = nil,
	sdkFilter: @escaping SDKFilterCallback = { sdks, _, _, _ in .success(sdks) }
) -> BuildSchemeProducer {
	precondition(directoryURL.isFileURL)

	return BuildSchemeProducer { observer, lifetime in
		// Use SignalProducer.replayLazily to avoid enumerating the given directory
		// multiple times.
		let locator = buildableSchemesInDirectory(directoryURL, withConfiguration: options.configuration, forPlatforms: options.platforms)
			.replayLazily(upTo: Int.max)

		locator
			.collect()
			// Allow dependencies which have no projects, not to error out with
			// `.noSharedFrameworkSchemes`.
			.filter { projects in !projects.isEmpty }
			.flatMap(.merge) { (projects: [(ProjectLocator, [Scheme])]) -> SignalProducer<(Scheme, ProjectLocator), CarthageError> in
				return schemesInProjects(projects)
					.flatMap(.merge) { (schemes: [(Scheme, ProjectLocator)]) -> SignalProducer<(Scheme, ProjectLocator), CarthageError> in
						if !schemes.isEmpty {
							return .init(schemes)
						} else {
							return .init(error: .noSharedFrameworkSchemes(.git(GitURL(directoryURL.path)), options.platforms))
						}
					}
			}
			.flatMap(.merge) { scheme, project -> SignalProducer<(Scheme, ProjectLocator), CarthageError> in
				return locator
					// This scheduler hop is required to avoid disallowed recursive signals.
					// See https://github.com/ReactiveCocoa/ReactiveCocoa/pull/2042.
					.start(on: QueueScheduler(qos: .default, name: "org.carthage.CarthageKit.Xcode.buildInDirectory"))
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
					.concat(value: (project, []))
					.take(first: 1)
					.map { project, _ in (scheme, project) }
			}
			.flatMap(.concat) { (scheme: Scheme, project: ProjectLocator) -> SignalProducer<TaskEvent<URL>, CarthageError> in
				let initialValue = (project, scheme)

				let wrappedSDKFilter: SDKFilterCallback = { sdks, scheme, configuration, project in
					let filteredSDKs: [SDK]
					if options.platforms.isEmpty {
						filteredSDKs = sdks
					} else {
						filteredSDKs = sdks.filter { options.platforms.contains($0.platform) }
					}
					return sdkFilter(filteredSDKs, scheme, configuration, project)
				}

				return buildScheme(scheme, withOptions: options, inProject: project, workingDirectoryURL: directoryURL, sdkFilter: wrappedSDKFilter)
					.mapError { error -> CarthageError in
						if case let .taskError(taskError) = error {
							return .buildFailed(taskError, log: nil)
						} else {
							return error
						}
					}
					.on(started: {
						observer.send(value: .success(initialValue))
					})
			}
			.collectTaskEvents()
			.flatMapTaskEvents(.concat) { (urls: [URL]) -> SignalProducer<(), CarthageError> in
				guard let dependency = dependency, let rootDirectoryURL = rootDirectoryURL else {
					return .empty
				}

				return createVersionFile(
					for: dependency.dependency, version: dependency.version,
					platforms: options.platforms, buildProducts: urls, rootDirectoryURL: rootDirectoryURL
				)
				.flatMapError { _ in .empty }
			}
			// Discard any Success values, since we want to
			// use our initial value instead of waiting for
			// completion.
			.map { taskEvent -> TaskEvent<(ProjectLocator, Scheme)> in
				let ignoredValue = (ProjectLocator.workspace(URL(string: ".")!), Scheme(""))
				return taskEvent.map { _ in ignoredValue }
			}
			.filter { taskEvent in
				taskEvent.value == nil
			}
			.startWithSignal({ signal, signalDisposable in
				lifetime += signalDisposable
				signal.observe(observer)
			})
	}
}

/// Strips a framework from unexpected architectures, optionally codesigning the
/// result.
public func stripFramework(_ frameworkURL: URL, keepingArchitectures: [String], codesigningIdentity: String? = nil) -> SignalProducer<(), CarthageError> {
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
public func stripDSYM(_ dSYMURL: URL, keepingArchitectures: [String]) -> SignalProducer<(), CarthageError> {
	return stripBinary(dSYMURL, keepingArchitectures: keepingArchitectures)
}

/// Strips a universal file from unexpected architectures.
private func stripBinary(_ binaryURL: URL, keepingArchitectures: [String]) -> SignalProducer<(), CarthageError> {
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
public func copyProduct(_ from: URL, _ to: URL) -> SignalProducer<URL, CarthageError> { // swiftlint:disable:this identifier_name
	return SignalProducer<URL, CarthageError> { () -> Result<URL, CarthageError> in
		let manager = FileManager.default

		// This signal deletes `to` before it copies `from` over it.
		// If `from` and `to` point to the same resource, there's no need to perform a copy at all
		// and deleting `to` will also result in deleting the original resource without copying it.
		// When `from` and `to` are the same, we can just return success immediately.
		//
		// See https://github.com/Carthage/Carthage/pull/1160
		if manager.fileExists(atPath: to.path) && from.absoluteURL == to.absoluteURL {
			return .success(to)
		}

		// Although some methods’ documentation say: “YES if createIntermediates
		// is set and the directory already exists)”, it seems to rarely
		// returns NO and NSFileWriteFileExistsError error. So we should
		// ignore that specific error.
		// See: https://developer.apple.com/documentation/foundation/filemanager/1415371-createdirectory
		func result(allowingErrorCode code: Int, _ result: Result<(), CarthageError>) -> Result<(), CarthageError> {
			if case .failure(.writeFailed(_, let error?)) = result, error.code == code {
				return .success(())
			}
			return result
		}

		let createDirectory = { try manager.createDirectory(at: $0, withIntermediateDirectories: true) }
		return result(allowingErrorCode: NSFileWriteFileExistsError, Result(at: to.deletingLastPathComponent(), attempt: createDirectory))
			.flatMap { _ in
				result(allowingErrorCode: NSFileNoSuchFileError, Result(at: to, attempt: manager.removeItem(at:)))
			}
			.flatMap { _ in
				Result(at: to, attempt: { destination /* to */ in
					try manager.copyItem(at: from, to: destination, avoiding·rdar·32984063: true)
					return destination
				})
			}
	}
}

extension SignalProducer where Value == URL, Error == CarthageError {
	/// Copies existing files sent from the producer into the given directory.
	///
	/// Returns a producer that will send locations where the copied files are.
	public func copyFileURLsIntoDirectory(_ directoryURL: URL) -> SignalProducer<URL, CarthageError> {
		return producer
			.filter { fileURL in (try? fileURL.checkResourceIsReachable()) ?? false }
			.flatMap(.merge) { fileURL -> SignalProducer<URL, CarthageError> in
				let fileName = fileURL.lastPathComponent
				let destinationURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
				let resolvedDestinationURL = destinationURL.resolvingSymlinksInPath()

				return copyProduct(fileURL, resolvedDestinationURL)
			}
	}
}

extension SignalProducer where Value: TaskEventType {
	/// Collect all TaskEvent success values and then send as a single array and complete.
	/// standard output and standard error data events are still sent as they are received.
	fileprivate func collectTaskEvents() -> SignalProducer<TaskEvent<[Value.T]>, Error> {
		return lift { $0.collectTaskEvents() }
	}
}

extension Signal where Value: TaskEventType {
	/// Collect all TaskEvent success values and then send as a single array and complete.
	/// standard output and standard error data events are still sent as they are received.
	fileprivate func collectTaskEvents() -> Signal<TaskEvent<[Value.T]>, Error> {
		var taskValues: [Value.T] = []

		return Signal<TaskEvent<[Value.T]>, Error> { observer, lifetime in
			lifetime += self.observe { event in
				switch event {
				case let .value(value):
					if let taskValue = value.value {
						taskValues.append(taskValue)
					} else {
						observer.send(value: value.map { [$0] })
					}

				case .completed:
					observer.send(value: .success(taskValues))
					observer.sendCompleted()

				case let .failed(error):
					observer.send(error: error)

				case .interrupted:
					observer.sendInterrupted()
				}
			}
		}
	}
}

/// Strips the given architecture from a framework.
private func stripArchitecture(_ frameworkURL: URL, _ architecture: String) -> SignalProducer<(), CarthageError> {
	return SignalProducer<URL, CarthageError> { () -> Result<URL, CarthageError> in binaryURL(frameworkURL) }
		.flatMap(.merge) { binaryURL -> SignalProducer<TaskEvent<Data>, CarthageError> in
			let lipoTask = Task("/usr/bin/xcrun", arguments: [ "lipo", "-remove", architecture, "-output", binaryURL.path, binaryURL.path])
			return lipoTask.launch()
				.mapError(CarthageError.taskError)
		}
		.then(SignalProducer<(), CarthageError>.empty)
}

/// Returns a signal of all architectures present in a given package.
public func architecturesInPackage(_ packageURL: URL) -> SignalProducer<String, CarthageError> {
	return SignalProducer<URL, CarthageError> { () -> Result<URL, CarthageError> in binaryURL(packageURL) }
		.flatMap(.merge) { binaryURL -> SignalProducer<String, CarthageError> in
			let lipoTask = Task("/usr/bin/xcrun", arguments: [ "lipo", "-info", binaryURL.path])

			return lipoTask.launch()
				.ignoreTaskData()
				.mapError(CarthageError.taskError)
				.map { String(data: $0, encoding: .utf8) ?? "" }
				.flatMap(.merge) { output -> SignalProducer<String, CarthageError> in
					var characterSet = CharacterSet.alphanumerics
					characterSet.insert(charactersIn: " _-")

					let scanner = Scanner(string: output)

					if scanner.scanString("Architectures in the fat file:", into: nil) {
						// The output of "lipo -info PathToBinary" for fat files
						// looks roughly like so:
						//
						//     Architectures in the fat file: PathToBinary are: armv7 arm64
						//
						var architectures: NSString?

						scanner.scanString(binaryURL.path, into: nil)
						scanner.scanString("are:", into: nil)
						scanner.scanCharacters(from: characterSet, into: &architectures)

						let components = architectures?
							.components(separatedBy: " ")
							.filter { !$0.isEmpty }

						if let components = components {
							return SignalProducer(components)
						}
					}

					if scanner.scanString("Non-fat file:", into: nil) {
						// The output of "lipo -info PathToBinary" for thin
						// files looks roughly like so:
						//
						//     Non-fat file: PathToBinary is architecture: x86_64
						//
						var architecture: NSString?

						scanner.scanString(binaryURL.path, into: nil)
						scanner.scanString("is architecture:", into: nil)
						scanner.scanCharacters(from: characterSet, into: &architecture)

						if let architecture = architecture {
							return SignalProducer(value: architecture as String)
						}
					}

					return SignalProducer(error: .invalidArchitectures(description: "Could not read architectures from \(packageURL.path)"))
				}
		}
}

/// Strips `Headers` directory from the given framework.
public func stripHeadersDirectory(_ frameworkURL: URL) -> SignalProducer<(), CarthageError> {
	return stripDirectory(named: "Headers", of: frameworkURL)
}

/// Strips `PrivateHeaders` directory from the given framework.
public func stripPrivateHeadersDirectory(_ frameworkURL: URL) -> SignalProducer<(), CarthageError> {
	return stripDirectory(named: "PrivateHeaders", of: frameworkURL)
}

/// Strips `Modules` directory from the given framework.
public func stripModulesDirectory(_ frameworkURL: URL) -> SignalProducer<(), CarthageError> {
	return stripDirectory(named: "Modules", of: frameworkURL)
}

private func stripDirectory(named directory: String, of frameworkURL: URL) -> SignalProducer<(), CarthageError> {
	return SignalProducer { () -> Result<(), CarthageError> in
		let directoryURLToStrip = frameworkURL.appendingPathComponent(directory, isDirectory: true)

		return Result(at: directoryURLToStrip, attempt: {
			var isDirectory: ObjCBool = false
			guard FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory), isDirectory.boolValue else {
				return
			}

			try FileManager.default.removeItem(at: $0)
		})
	}
}

/// Sends a set of UUIDs for each architecture present in the given framework.
public func UUIDsForFramework(_ frameworkURL: URL) -> SignalProducer<Set<UUID>, CarthageError> {
	return SignalProducer { () -> Result<URL, CarthageError> in binaryURL(frameworkURL) }
		.flatMap(.merge, UUIDsFromDwarfdump)
}

/// Sends a set of UUIDs for each architecture present in the given dSYM.
public func UUIDsForDSYM(_ dSYMURL: URL) -> SignalProducer<Set<UUID>, CarthageError> {
	return UUIDsFromDwarfdump(dSYMURL)
}

/// Sends an URL for each bcsymbolmap file for the given framework.
/// The files do not necessarily exist on disk.
///
/// The returned URLs are relative to the parent directory of the framework.
public func BCSymbolMapsForFramework(_ frameworkURL: URL) -> SignalProducer<URL, CarthageError> {
	let directoryURL = frameworkURL.deletingLastPathComponent()
	return UUIDsForFramework(frameworkURL)
		.flatMap(.merge) { uuids in SignalProducer<UUID, CarthageError>(uuids) }
		.map { uuid in
			return directoryURL.appendingPathComponent(uuid.uuidString, isDirectory: false).appendingPathExtension("bcsymbolmap")
		}
}

/// Sends a set of UUIDs for each architecture present in the given URL.
private func UUIDsFromDwarfdump(_ url: URL) -> SignalProducer<Set<UUID>, CarthageError> {
	let dwarfdumpTask = Task("/usr/bin/xcrun", arguments: [ "dwarfdump", "--uuid", url.path ])

	return dwarfdumpTask.launch()
		.ignoreTaskData()
		.mapError(CarthageError.taskError)
		.map { String(data: $0, encoding: .utf8) ?? "" }
		// If there are no dSYMs (the output is empty but has a zero exit 
		// status), complete with no values. This can occur if this is a "fake"
		// framework, meaning a static framework packaged like a dynamic 
		// framework.
		.filter { !$0.isEmpty }
		.flatMap(.merge) { output -> SignalProducer<Set<UUID>, CarthageError> in
			// UUIDs are letters, decimals, or hyphens.
			var uuidCharacterSet = CharacterSet()
			uuidCharacterSet.formUnion(.letters)
			uuidCharacterSet.formUnion(.decimalDigits)
			uuidCharacterSet.formUnion(CharacterSet(charactersIn: "-"))

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

				if let uuidString = uuidString as String?, let uuid = UUID(uuidString: uuidString) {
					uuids.insert(uuid)
				}

				// Scan until a newline or end of file.
				scanner.scanUpToCharacters(from: .newlines, into: nil)
			}

			if !uuids.isEmpty {
				return SignalProducer(value: uuids)
			} else {
				return SignalProducer(error: .invalidUUIDs(description: "Could not parse UUIDs using dwarfdump from \(url.path)"))
			}
		}
}

/// Returns the URL of a binary inside a given package.
private func binaryURL(_ packageURL: URL) -> Result<URL, CarthageError> {
	let bundle = Bundle(path: packageURL.path)
	let packageType = (bundle?.object(forInfoDictionaryKey: "CFBundlePackageType") as? String).flatMap(PackageType.init)

	switch packageType {
	case .framework?, .bundle?:
		if let binaryName = bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String {
			return .success(packageURL.appendingPathComponent(binaryName))
		}

	case .dSYM?:
		let binaryName = packageURL.deletingPathExtension().deletingPathExtension().lastPathComponent
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
private func codesign(_ frameworkURL: URL, _ expandedIdentity: String) -> SignalProducer<(), CarthageError> {
	let codesignTask = Task(
		"/usr/bin/xcrun",
		arguments: ["codesign", "--force", "--sign", expandedIdentity, "--preserve-metadata=identifier,entitlements", frameworkURL.path]
	)
	return codesignTask.launch()
		.mapError(CarthageError.taskError)
		.then(SignalProducer<(), CarthageError>.empty)
}
