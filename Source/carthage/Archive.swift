import CarthageKit
import Commandant
import Foundation
import Result
import ReactiveSwift
import XCDBLD
import Curry

/// Type that encapsulates the configuration and evaluation of the `archive` subcommand.
public struct ArchiveCommand: CommandProtocol {
	public struct Options: OptionsProtocol {
		public let outputPath: String?
		public let directoryPath: String
		public let colorOptions: ColorOptions
		public let frameworkNames: [String]

		public static func evaluate(_ mode: CommandMode) -> Result<Options, CommandantError<CarthageError>> {
			let argumentUsage = "the names of the built frameworks to archive without any extension "
				+ "(or blank to pick up the frameworks in the current project built by `--no-skip-current`)"

			return curry(self.init)
				<*> mode <| Option(
					key: "output",
					defaultValue: nil,
					usage: "the path at which to create the zip file (or blank to infer it from the first one of the framework names)"
				)
				<*> mode <| Option(
					key: "project-directory",
					defaultValue: FileManager.default.currentDirectoryPath,
					usage: "the directory containing the Carthage project"
				)
				<*> ColorOptions.evaluate(mode)
				<*> mode <| Argument(defaultValue: [], usage: argumentUsage, usageParameter: "framework names")
		}
	}

	public let verb = "archive"
	public let function = "Archives built frameworks into a zip that Carthage can use"

	// swiftlint:disable:next function_body_length
	public func run(_ options: Options) -> Result<(), CarthageError> {
		return archiveWithOptions(options)
			.waitOnCommand()
	}

	// swiftlint:disable:next function_body_length
	public func archiveWithOptions(_ options: Options) -> SignalProducer<(), CarthageError> {
		let formatting = options.colorOptions.formatting

		let frameworks: SignalProducer<[String], CarthageError>
		if !options.frameworkNames.isEmpty {
			frameworks = .init(value: options.frameworkNames.map {
				return ($0 as NSString).appendingPathExtension("framework")!
			})
		} else {
			let directoryURL = URL(fileURLWithPath: options.directoryPath, isDirectory: true)
			frameworks = buildableSchemesInDirectory(directoryURL, withConfiguration: "Release")
				.flatMap(.merge) { scheme, project -> SignalProducer<BuildSettings, CarthageError> in
					let buildArguments = BuildArguments(project: project, scheme: scheme, configuration: "Release")
					return BuildSettings.load(with: buildArguments)
				}
				.flatMap(.concat) { settings -> SignalProducer<String, CarthageError> in
					if let wrapperName = settings.wrapperName.value, settings.productType.value == .framework {
						return .init(value: wrapperName)
					} else {
						return .empty
					}
				}
				.collect()
				.map { Array(Set($0)).sorted() }
		}

		return frameworks.flatMap(.merge) { frameworks -> SignalProducer<(), CarthageError> in
			return SignalProducer<Platform, CarthageError>(Platform.supportedPlatforms)
				.flatMap(.merge) { platform -> SignalProducer<String, CarthageError> in
					return SignalProducer(frameworks).map { framework in
						return (platform.relativePath as NSString).appendingPathComponent(framework)
					}
				}
				.map { relativePath -> (relativePath: String, absolutePath: String) in
					let absolutePath = (options.directoryPath as NSString).appendingPathComponent(relativePath)
					return (relativePath, absolutePath)
				}
				.filter { filePath in FileManager.default.fileExists(atPath: filePath.absolutePath) }
				.flatMap(.merge) { framework -> SignalProducer<String, CarthageError> in
					let dSYM = (framework.relativePath as NSString).appendingPathExtension("dSYM")!
					let bcsymbolmapsProducer = BCSymbolMapsForFramework(URL(fileURLWithPath: framework.absolutePath))
						// generate relative paths for the bcsymbolmaps so they print nicely
						.map { url in ((framework.relativePath as NSString).deletingLastPathComponent as NSString).appendingPathComponent(url.lastPathComponent) }
					let extraFilesProducer = SignalProducer(value: dSYM)
						.concat(bcsymbolmapsProducer)
						.filter { _ in FileManager.default.fileExists(atPath: framework.absolutePath) }
					return SignalProducer(value: framework.relativePath)
						.concat(extraFilesProducer)
				}
				.on(value: { path in
					carthage.println(formatting.bullets + "Found " + formatting.path(path))
				})
				.collect()
				.flatMap(.merge) { paths -> SignalProducer<(), CarthageError> in

					let foundFrameworks = paths
						.lazy
						.map { ($0 as NSString).lastPathComponent }
						.filter { $0.hasSuffix(".framework") }

					if Set(foundFrameworks) != Set(frameworks) {
						let error = CarthageError.invalidArgument(
							description: "Could not find any copies of \(frameworks.joined(separator: ", ")). "
								+ "Make sure you're in the project's root and that the frameworks have already been built using 'carthage build --no-skip-current'."
						)
						return SignalProducer(error: error)
					}

					let outputPath = outputPathWithOptions(options, frameworks: frameworks)
					let outputURL = URL(fileURLWithPath: outputPath, isDirectory: false)

					_ = try? FileManager
						.default
						.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

					return zip(paths: paths, into: outputURL, workingDirectory: options.directoryPath).on(completed: {
						carthage.println(formatting.bullets + "Created " + formatting.path(outputPath))
					})
			}
		}
	}
}

/// Returns an appropriate output file path for the resulting zip file using
/// the given option and frameworks.
private func outputPathWithOptions(_ options: ArchiveCommand.Options, frameworks: [String]) -> String {
	let defaultOutputPath = "\(frameworks.first!).zip"

	return options.outputPath.map { path -> String in
		if path.hasSuffix("/") {
			// The given path should be a directory.
			return path + defaultOutputPath
		}

		var isDirectory: ObjCBool = false
		if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue {
			// If the given path is an existing directory, output a zip file
			// into that directory.
			return (path as NSString).appendingPathComponent(defaultOutputPath)
		} else {
			// Use the given path as the final output.
			return path
		}
	} ?? defaultOutputPath
}
