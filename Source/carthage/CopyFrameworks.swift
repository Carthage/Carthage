//
//  CopyFramework.swift
//  Carthage
//
//  Created by Robert Böhnke on 10/12/14.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Commandant
import Foundation
import Result
import ReactiveCocoa


public struct CopyFrameworksCommand: CommandType {
	public let verb = "copy-frameworks"
	public let function = "In a Run Script build phase, copies each framework specified by a SCRIPT_INPUT_FILE environment variable into the built app bundle"

	public func run(options: NoOptions<CarthageError>) -> Result<(), CarthageError> {
		return inputFiles()
			.flatMap(.Concat) { frameworkPath -> SignalProducer<(), CarthageError> in
				let frameworkName = (frameworkPath as NSString).lastPathComponent

				let source = Result(NSURL(fileURLWithPath: frameworkPath, isDirectory: true), failWith: CarthageError.InvalidArgument(description: "Could not find framework \"\(frameworkName)\" at path \(frameworkPath). Ensure that the given path is appropriately entered and that your \"Input Files\" have been entered correctly."))
				let target = frameworksFolder().map { $0.appendingPathComponent(frameworkName, isDirectory: true) }

				return combineLatest(SignalProducer(result: source), SignalProducer(result: target), SignalProducer(result: validArchitectures()))
					.flatMap(.Merge) { (source, target, validArchitectures) -> SignalProducer<(), CarthageError> in
						return shouldIgnoreFramework(source, validArchitectures: validArchitectures)
							.flatMap(.Concat) { shouldIgnore -> SignalProducer<(), CarthageError> in
								if shouldIgnore {
									carthage.println("warning: Ignoring \(frameworkName) because it does not support the current architecture\n")
									return .empty
								} else {
									let copyFrameworks = copyFramework(source, target: target, validArchitectures: validArchitectures)
									let copydSYMs = copyDebugSymbolsForFramework(source, validArchitectures: validArchitectures)
									return combineLatest(copyFrameworks, copydSYMs)
										.then(.empty)
								}
						}
				}
			}
			.waitOnCommand()
	}
}

private func copyFramework(source: NSURL, target: NSURL, validArchitectures: [String]) -> SignalProducer<(), CarthageError> {
	return combineLatest(copyProduct(source, target), codeSigningIdentity())
		.flatMap(.Merge) { (url, codesigningIdentity) -> SignalProducer<(), CarthageError> in
			let strip = stripFramework(url, keepingArchitectures: validArchitectures, codesigningIdentity: codesigningIdentity)
			if buildActionIsArchiveOrInstall() {
				return strip
					.then(copyBCSymbolMapsForFramework(url, fromDirectory: source.URLByDeletingLastPathComponent!))
					.then(.empty)
			} else {
				return strip
			}
	}
}

private func shouldIgnoreFramework(framework: NSURL, validArchitectures: [String]) -> SignalProducer<Bool, CarthageError> {
	return architecturesInPackage(framework)
		.collect()
		.map { architectures in
			// Return all the architectures, present in the framework, that are valid.
			validArchitectures.filter(architectures.contains)
		}
		.map { remainingArchitectures in
			// If removing the useless architectures results in an empty fat file, wat means that the framework does not have a binary for the given architecture, ignore the framework.
			remainingArchitectures.isEmpty
		}
}

private func copyDebugSymbolsForFramework(source: NSURL, validArchitectures: [String]) -> SignalProducer<(), CarthageError> {
	return SignalProducer(result: appropriateDestinationFolder())
		.flatMap(.Merge) { destinationURL in
			return SignalProducer(value: source)
				.map { return $0.appendingPathExtension("dSYM") }
				.copyFileURLsIntoDirectory(destinationURL)
				.flatMap(.Merge) { dSYMURL in
					return stripDSYM(dSYMURL, keepingArchitectures: validArchitectures)
				}
	    }

}

private func copyBCSymbolMapsForFramework(frameworkURL: NSURL, fromDirectory directoryURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	// This should be called only when `buildActionIsArchiveOrInstall()` is true.
	return SignalProducer(result: builtProductsFolder())
		.flatMap(.Merge) { builtProductsURL in
			return BCSymbolMapsForFramework(frameworkURL)
				.map { URL in directoryURL.appendingPathComponent(URL.lastPathComponent!, isDirectory: false) }
				.copyFileURLsIntoDirectory(builtProductsURL)
		}
}

private func codeSigningIdentity() -> SignalProducer<String?, CarthageError> {
	return SignalProducer.attempt {
		if codeSigningAllowed() {
			return getEnvironmentVariable("EXPANDED_CODE_SIGN_IDENTITY").map { $0.isEmpty ? nil : $0 }
		} else {
			return .Success(nil)
		}
	}
}

private func codeSigningAllowed() -> Bool {
	return getEnvironmentVariable("CODE_SIGNING_ALLOWED")
		.map { $0 == "YES" }.value ?? false
}

// The fix for https://github.com/Carthage/Carthage/issues/1259
private func appropriateDestinationFolder() -> Result<NSURL, CarthageError> {
	if buildActionIsArchiveOrInstall() {
		return builtProductsFolder()
	} else {
		return targetBuildFolder()
	}
}

private func builtProductsFolder() -> Result<NSURL, CarthageError> {
	return getEnvironmentVariable("BUILT_PRODUCTS_DIR")
		.map { NSURL(fileURLWithPath: $0, isDirectory: true) }
}

private func targetBuildFolder() -> Result<NSURL, CarthageError> {
	return getEnvironmentVariable("TARGET_BUILD_DIR")
		.map { NSURL(fileURLWithPath: $0, isDirectory: true) }
}

private func frameworksFolder() -> Result<NSURL, CarthageError> {
	return appropriateDestinationFolder()
		.flatMap { url -> Result<NSURL, CarthageError> in
			getEnvironmentVariable("FRAMEWORKS_FOLDER_PATH")
				.map { url.appendingPathComponent($0, isDirectory: true) }
		}
}

private func validArchitectures() -> Result<[String], CarthageError> {
	return getEnvironmentVariable("VALID_ARCHS").map { architectures -> [String] in
		architectures.componentsSeparatedByString(" ")
	}
}

private func buildActionIsArchiveOrInstall() -> Bool {
	// archives use ACTION=install
	return getEnvironmentVariable("ACTION").value == "install"
}

private func inputFiles() -> SignalProducer<String, CarthageError> {
	let count: Result<Int, CarthageError> = getEnvironmentVariable("SCRIPT_INPUT_FILE_COUNT").flatMap { count in
		if let i = Int(count) {
			return .Success(i)
		} else {
			return .Failure(.InvalidArgument(description: "SCRIPT_INPUT_FILE_COUNT did not specify a number"))
		}
	}

	return SignalProducer(result: count)
		.flatMap(.Merge) { count -> SignalProducer<String, CarthageError> in
			let variables = (0..<count).map { index -> SignalProducer<String, CarthageError> in
				return SignalProducer(result: getEnvironmentVariable("SCRIPT_INPUT_FILE_\(index)"))
			}

			return SignalProducer<SignalProducer<String, CarthageError>, CarthageError>(values: variables)
				.flatten(.Concat)
		}
}
