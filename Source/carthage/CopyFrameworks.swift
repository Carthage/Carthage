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

	public func run(mode: CommandMode) -> Result<(), CommandantError<CarthageError>> {
		switch mode {
		case .Arguments:
			return inputFiles()
				|> flatMap(.Concat) { frameworkPath -> SignalProducer<(), CarthageError> in
					let frameworkName = frameworkPath.lastPathComponent

					let source = Result(NSURL(fileURLWithPath: frameworkPath, isDirectory: true), failWith: CarthageError.InvalidArgument(description: "Could not find framework \"\(frameworkName)\" at path \(frameworkPath). Ensure that the given path is appropriately entered and that your \"Input Files\" have been entered correctly."))
					let target = frameworksFolder().map { $0.URLByAppendingPathComponent(frameworkName, isDirectory: true) }

					return combineLatest(SignalProducer(result: source), SignalProducer(result: target), SignalProducer(result: validArchitectures()))
						|> flatMap(.Merge) { (source, target, validArchitectures) -> SignalProducer<(), CarthageError> in
							return combineLatest(copyProduct(source, target), codeSigningIdentity())
								|> flatMap(.Merge) { (url, codesigningIdentity) -> SignalProducer<(), CarthageError> in
									let strip = stripFramework(url, keepingArchitectures: validArchitectures, codesigningIdentity: codesigningIdentity)
									if buildActionIsArchiveOrInstall() {
										return strip
											|> then(copyBCSymbolMapsForFramework(url, fromDirectory: source.URLByDeletingLastPathComponent!))
											|> then(.empty)
									} else {
										return strip
									}
								}
						}
				}
				|> promoteErrors
				|> waitOnCommand
		case .Usage:
			return .success(())
		}
	}
}

private func copyBCSymbolMapsForFramework(frameworkURL: NSURL, fromDirectory directoryURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	return SignalProducer(result: builtProductsFolder())
		|> flatMap(.Merge) { builtProductsURL in
			let bcsymbolmapsProducer = BCSymbolMapsForFramework(frameworkURL)
				|> map { URL in directoryURL.URLByAppendingPathComponent(URL.lastPathComponent!, isDirectory: false) }
			return copyFileURLsFromProducer(bcsymbolmapsProducer, intoDirectory: builtProductsURL)
		}
}

private func codeSigningIdentity() -> SignalProducer<String?, CarthageError> {
	return SignalProducer.try {
		if codeSigningAllowed() {
			return getEnvironmentVariable("EXPANDED_CODE_SIGN_IDENTITY").map { $0.isEmpty ? nil : $0 }
		} else {
			return .success(nil)
		}
	}
}

private func codeSigningAllowed() -> Bool {
	return getEnvironmentVariable("CODE_SIGNING_ALLOWED")
		.map { $0 == "YES" }.value ?? false
}

private func builtProductsFolder() -> Result<NSURL, CarthageError> {
	return getEnvironmentVariable("BUILT_PRODUCTS_DIR")
		.map { NSURL(fileURLWithPath: $0, isDirectory: true)! }
}

private func frameworksFolder() -> Result<NSURL, CarthageError> {
	return builtProductsFolder()
		.flatMap { url -> Result<NSURL, CarthageError> in
			getEnvironmentVariable("FRAMEWORKS_FOLDER_PATH")
				.map { url.URLByAppendingPathComponent($0, isDirectory: true) }
		}
}

private func validArchitectures() -> Result<[String], CarthageError> {
	return getEnvironmentVariable("VALID_ARCHS").map { architectures in
		split(architectures) { $0 == " " }
	}
}

private func buildActionIsArchiveOrInstall() -> Bool {
	// archives use ACTION=install
	return getEnvironmentVariable("ACTION").value == "install"
}

private func inputFiles() -> SignalProducer<String, CarthageError> {
	let count: Result<Int, CarthageError> = getEnvironmentVariable("SCRIPT_INPUT_FILE_COUNT").flatMap { count in
		if let i = count.toInt() {
			return .success(i)
		} else {
			return .failure(.InvalidArgument(description: "SCRIPT_INPUT_FILE_COUNT did not specify a number"))
		}
	}

	return SignalProducer(result: count)
		|> flatMap(.Merge) { count -> SignalProducer<String, CarthageError> in
			let variables = (0..<count).map { index -> SignalProducer<String, CarthageError> in
				return SignalProducer(result: getEnvironmentVariable("SCRIPT_INPUT_FILE_\(index)"))
			}

			return SignalProducer(values: variables)
				|> flatten(.Concat)
		}
}
