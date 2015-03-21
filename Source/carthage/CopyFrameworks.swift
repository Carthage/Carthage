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
import LlamaKit
import ReactiveCocoa


public struct CopyFrameworksCommand: CommandType {
	public let verb = "copy-frameworks"
	public let function = "In a Run Script build phase, copies each framework specified by a SCRIPT_INPUT_FILE environment variable into the built app bundle"

	public func run(mode: CommandMode) -> Result<(), CommandantError> {
		switch mode {
		case .Arguments:
			return inputFiles()
				.map { frameworkPath -> ColdSignal<()> in
					let frameworkName = frameworkPath.lastPathComponent

					let source = NSURL(fileURLWithPath: frameworkPath, isDirectory: true)!
					let target = frameworksFolder().map { $0.URLByAppendingPathComponent(frameworkName, isDirectory: true) }

					return combineLatest(ColdSignal.fromResult(target), .fromResult(validArchitectures()))
						.mergeMap { (target, validArchitectures) -> ColdSignal<()> in
							return combineLatest(copyFramework(source, target), codeSigningIdentity())
								.mergeMap { (url, codesigningIdentity) -> ColdSignal<()> in
									return stripFramework(target, keepingArchitectures: validArchitectures, codesigningIdentity: codesigningIdentity)
								}
						}
				}
				.concat(identity)
				.wait()

		case .Usage:
			return success(())
		}
	}
}

private func codeSigningIdentity() -> ColdSignal<String?> {
	return ColdSignal.lazy {
		if codeSigningAllowed() {
			switch getEnvironmentVariable("EXPANDED_CODE_SIGN_IDENTITY") {
			case let .Success(value):
				return .single(value.unbox)

			case let .Failure(error):
				return .error(error)
			}
		} else {
			return .single(nil)
		}
	}
}

private func codeSigningAllowed() -> Bool {
	return getEnvironmentVariable("CODE_SIGNING_ALLOWED")
		.map { $0 == "YES" }
		.value() ?? false
}

private func frameworksFolder() -> Result<NSURL, CarthageError> {
	return getEnvironmentVariable("BUILT_PRODUCTS_DIR")
		.map { NSURL(fileURLWithPath: $0, isDirectory: true)! }
		.flatMap { url -> Result<NSURL> in
			getEnvironmentVariable("FRAMEWORKS_FOLDER_PATH")
				.map { url.URLByAppendingPathComponent($0, isDirectory: true) }
		}
}

private func validArchitectures() -> Result<[String], CarthageError> {
	return getEnvironmentVariable("VALID_ARCHS").map { architectures in
		split(architectures, { $0 == " " })
	}
}

private func inputFiles() -> ColdSignal<String> {
	return ColdSignal.fromResult(getEnvironmentVariable("SCRIPT_INPUT_FILE_COUNT"))
		.tryMap { (count, error) -> Int? in
			return count.toInt()
		}
		.mergeMap { count -> ColdSignal<String> in
			let variables = (0..<count).map { index -> ColdSignal<String> in
				return .fromResult(getEnvironmentVariable("SCRIPT_INPUT_FILE_\(index)"))
			}

			return ColdSignal.fromValues(variables).concat(identity)
		}
}
