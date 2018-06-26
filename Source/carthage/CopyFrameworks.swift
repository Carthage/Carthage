import CarthageKit
import Commandant
import Foundation
import Result
import ReactiveSwift

/// Type that encapsulates the configuration and evaluation of the `copy-frameworks` subcommand.
public struct CopyFrameworksCommand: CommandProtocol {
	public let verb = "copy-frameworks"
	public let function = "In a Run Script build phase, copies each framework specified by a SCRIPT_INPUT_FILE environment variable into the built app bundle"

	public func run(_ options: NoOptions<CarthageError>) -> Result<(), CarthageError> {
		return inputFiles()
			.flatMap(.merge) { frameworkPath -> SignalProducer<(), CarthageError> in
				let frameworkName = (frameworkPath as NSString).lastPathComponent

				let source = Result(
					URL(fileURLWithPath: frameworkPath, isDirectory: true),
					failWith: CarthageError.invalidArgument(
						description: "Could not find framework \"\(frameworkName)\" at path \(frameworkPath). "
							+ "Ensure that the given path is appropriately entered and that your \"Input Files\" have been entered correctly."
					)
				)
				let target = frameworksFolder().map { $0.appendingPathComponent(frameworkName, isDirectory: true) }

				return SignalProducer.combineLatest(SignalProducer(result: source), SignalProducer(result: target), SignalProducer(result: validArchitectures()))
					.flatMap(.merge) { source, target, validArchitectures -> SignalProducer<(), CarthageError> in
						return shouldIgnoreFramework(source, validArchitectures: validArchitectures)
							.flatMap(.concat) { shouldIgnore -> SignalProducer<(), CarthageError> in
								if shouldIgnore {
									carthage.println("warning: Ignoring \(frameworkName) because it does not support the current architecture\n")
									return .empty
								} else {
									let copyFrameworks = copyFramework(source, target: target, validArchitectures: validArchitectures)
									let copydSYMs = copyDebugSymbolsForFramework(source, validArchitectures: validArchitectures)
									return SignalProducer.combineLatest(copyFrameworks, copydSYMs)
										.then(SignalProducer<(), CarthageError>.empty)
								}
							}
					}
					// Copy as many frameworks as possible in parallel.
					.start(on: QueueScheduler(name: "org.carthage.CarthageKit.CopyFrameworks.copy"))
			}
			.waitOnCommand()
	}
}

private func copyFramework(_ source: URL, target: URL, validArchitectures: [String]) -> SignalProducer<(), CarthageError> {
	return SignalProducer.combineLatest(copyProduct(source, target), codeSigningIdentity())
		.flatMap(.merge) { url, codesigningIdentity -> SignalProducer<(), CarthageError> in
			let strip = stripFramework(
				url,
				keepingArchitectures: validArchitectures,
				strippingDebugSymbols: shouldStripDebugSymbols(),
				codesigningIdentity: codesigningIdentity
			)
			if buildActionIsArchiveOrInstall() {
				return strip
					.then(copyBCSymbolMapsForFramework(url, fromDirectory: source.deletingLastPathComponent()))
					.then(SignalProducer<(), CarthageError>.empty)
			} else {
				return strip
			}
		}
}

private func shouldIgnoreFramework(_ framework: URL, validArchitectures: [String]) -> SignalProducer<Bool, CarthageError> {
	return architecturesInPackage(framework)
		.collect()
		.map { architectures in
			// Return all the architectures, present in the framework, that are valid.
			validArchitectures.filter(architectures.contains)
		}
		.map { remainingArchitectures in
			// If removing the useless architectures results in an empty fat file, 
			// wat means that the framework does not have a binary for the given architecture, ignore the framework.
			remainingArchitectures.isEmpty
		}
}

private func copyDebugSymbolsForFramework(_ source: URL, validArchitectures: [String]) -> SignalProducer<(), CarthageError> {
	return SignalProducer(result: appropriateDestinationFolder())
		.flatMap(.merge) { destinationURL in
			return SignalProducer(value: source)
				.map { $0.appendingPathExtension("dSYM") }
				.copyFileURLsIntoDirectory(destinationURL)
				.flatMap(.merge) { dSYMURL in
					return stripDSYM(dSYMURL, keepingArchitectures: validArchitectures)
				}
		}
}

private func copyBCSymbolMapsForFramework(_ frameworkURL: URL, fromDirectory directoryURL: URL) -> SignalProducer<URL, CarthageError> {
	// This should be called only when `buildActionIsArchiveOrInstall()` is true.
	return SignalProducer(result: builtProductsFolder())
		.flatMap(.merge) { builtProductsURL in
			return BCSymbolMapsForFramework(frameworkURL)
				.map { url in directoryURL.appendingPathComponent(url.lastPathComponent, isDirectory: false) }
				.copyFileURLsIntoDirectory(builtProductsURL)
		}
}

private func codeSigningIdentity() -> SignalProducer<String?, CarthageError> {
	return SignalProducer(codeSigningAllowed)
		.attemptMap { codeSigningAllowed in
			guard codeSigningAllowed == true else { return .success(nil) }

			return getEnvironmentVariable("EXPANDED_CODE_SIGN_IDENTITY")
				.map { $0.isEmpty ? nil : $0 }
				.flatMapError {
					// See https://github.com/Carthage/Carthage/issues/2472#issuecomment-395134166 regarding Xcode 10 betas
					// … or potentially non-beta Xcode releases of major version 10 or later.

					switch getEnvironmentVariable("XCODE_PRODUCT_BUILD_VERSION") {
					case .success(_):
						// See the above issue.
						return .success(nil)
					case .failure(_):
						// For users calling `carthage copy-frameworks` outside of Xcode (admittedly,
						// a small fraction), this error is worthwhile in being a signpost in what’s
						// necessary to add to achieve (for what most is the goal) of ensuring
						// that code signing happens.
						return .failure($0)
					}
				}
		}
}

private func codeSigningAllowed() -> Bool {
	return getEnvironmentVariable("CODE_SIGNING_ALLOWED")
		.map { $0 == "YES" }.value ?? false
}

private func shouldStripDebugSymbols() -> Bool {
	return getEnvironmentVariable("COPY_PHASE_STRIP")
		.map { $0 == "YES" }.value ?? false
}

// The fix for https://github.com/Carthage/Carthage/issues/1259
private func appropriateDestinationFolder() -> Result<URL, CarthageError> {
	if buildActionIsArchiveOrInstall() {
		return builtProductsFolder()
	} else {
		return targetBuildFolder()
	}
}

private func builtProductsFolder() -> Result<URL, CarthageError> {
	return getEnvironmentVariable("BUILT_PRODUCTS_DIR")
		.map { URL(fileURLWithPath: $0, isDirectory: true) }
}

private func targetBuildFolder() -> Result<URL, CarthageError> {
	return getEnvironmentVariable("TARGET_BUILD_DIR")
		.map { URL(fileURLWithPath: $0, isDirectory: true) }
}

private func frameworksFolder() -> Result<URL, CarthageError> {
	return appropriateDestinationFolder()
		.flatMap { url -> Result<URL, CarthageError> in
			getEnvironmentVariable("FRAMEWORKS_FOLDER_PATH")
				.map { url.appendingPathComponent($0, isDirectory: true) }
		}
}

private func validArchitectures() -> Result<[String], CarthageError> {
	return getEnvironmentVariable("VALID_ARCHS").map { architectures -> [String] in
		return architectures.components(separatedBy: " ")
	}
}

private func buildActionIsArchiveOrInstall() -> Bool {
	// archives use ACTION=install
	return getEnvironmentVariable("ACTION").value == "install"
}

private func inputFiles() -> SignalProducer<String, CarthageError> {
	let count: Result<Int, CarthageError> = getEnvironmentVariable("SCRIPT_INPUT_FILE_COUNT").flatMap { count in
		// swiftlint:disable:next identifier_name
		if let i = Int(count) {
			return .success(i)
		} else {
			return .failure(.invalidArgument(description: "SCRIPT_INPUT_FILE_COUNT did not specify a number"))
		}
	}

	return SignalProducer(result: count)
		.flatMap(.merge) { SignalProducer<Int, CarthageError>(0..<$0) }
		.attemptMap { getEnvironmentVariable("SCRIPT_INPUT_FILE_\($0)") }
		.uniqueValues()
}
