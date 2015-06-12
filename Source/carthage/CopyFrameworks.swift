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

					let source = NSURL(fileURLWithPath: frameworkPath, isDirectory: true)!
					let target = frameworksFolder().map { $0.URLByAppendingPathComponent(frameworkName, isDirectory: true) }

					return SignalProducer(result: target &&& validArchitectures())
						|> flatMap(.Merge) { (target, validArchitectures) -> SignalProducer<(), CarthageError> in
							return combineLatest(copyFramework(source, target), codeSigningIdentity())
								|> flatMap(.Merge) { (url, codesigningIdentity) -> SignalProducer<(), CarthageError> in
									return stripFramework(target, keepingArchitectures: validArchitectures, codesigningIdentity: codesigningIdentity)
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

private func codeSigningIdentity() -> SignalProducer<String?, CarthageError> {
	return SignalProducer.try {
		if codeSigningAllowed() {
			return getEnvironmentVariable("EXPANDED_CODE_SIGN_IDENTITY").map { $0 }
		} else {
			return .success(nil)
		}
	}
}

private func codeSigningAllowed() -> Bool {
	return getEnvironmentVariable("CODE_SIGNING_ALLOWED")
		.map { $0 == "YES" }.value ?? false
}

private func frameworksFolder() -> Result<NSURL, CarthageError> {
	return getEnvironmentVariable("BUILT_PRODUCTS_DIR")
		.map { NSURL(fileURLWithPath: $0, isDirectory: true)! }
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

private func inputFiles() -> SignalProducer<String, CarthageError> {
	return SignalProducer(result: getEnvironmentVariable("SCRIPT_INPUT_FILE_COUNT"))
		|> tryMap { count -> Result<Int, CarthageError> in
			if let i = count.toInt() {
				return .success(i)
			} else {
				return .failure(.InvalidArgument(description: "SCRIPT_INPUT_FILE_COUNT did not specify a number"))
			}
		}
		|> flatMap(.Merge) { count -> SignalProducer<String, CarthageError> in
			let variables = (0..<count).map { index -> SignalProducer<String, CarthageError> in
				return SignalProducer(result: getEnvironmentVariable("SCRIPT_INPUT_FILE_\(index)"))
			}

			return SignalProducer(values: variables)
				|> flatten(.Concat)
		}
}
