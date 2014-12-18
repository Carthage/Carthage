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
	public let function = "In a Run Script build phase, copies each framework specified by an SCRIPT_INPUT_FILE environment variable into the built app bundle."

	public func run(mode: CommandMode) -> Result<()> {
		return inputFiles()
			.map { frameworkPath -> ColdSignal<()> in
				let frameworkName = frameworkPath.lastPathComponent

				let source = NSURL(fileURLWithPath: frameworkPath, isDirectory: true)!
				let target = frameworksFolder().map { $0.URLByAppendingPathComponent(frameworkName, isDirectory: true) }

				return ColdSignal.single(source)
					.combineLatestWith(.fromResult(target))
					.combineLatestWith(.fromResult(validArchitectures()))
					.map { ($0.0.0, $0.0.1, $0.1) }
					.map { (source, target, validArchitectures) -> ColdSignal<()> in

						return copyFramework(source, target)
							.combineLatestWith(.fromResult(getEnvironmentVariable("EXPANDED_CODE_SIGN_IDENTITY")))
							.map { stripFramework(target, keepingArchitectures: validArchitectures, codesigningIdentity: $0.1) }
							.merge(identity)
							.then(.empty())
					}
					.merge(identity)
			}
			.concat(identity)
			.wait()
	}
}

private func codeSigningAllowed() -> Bool {
	return getEnvironmentVariable("CODE_SIGNING_ALLOWED").map({ $0 == "YES" }).value() ?? false
}

private func frameworksFolder() -> Result<NSURL> {
	let configurationBuildDir = getEnvironmentVariable("CONFIGURATION_BUILD_DIR")
	let frameworksFolderPath = getEnvironmentVariable("FRAMEWORKS_FOLDER_PATH")

	if !configurationBuildDir.isSuccess() || !frameworksFolderPath.isSuccess() {
		return failure(configurationBuildDir.error() ?? frameworksFolderPath.error()!)
	}

	let URL = NSURL(fileURLWithPath: configurationBuildDir.value()!, isDirectory: true)!.URLByAppendingPathComponent(frameworksFolderPath.value()!, isDirectory: true)

	return success(URL)
}

private func validArchitectures() -> Result<[String]> {
	return getEnvironmentVariable("VALID_ARCHS").map { return split($0, { $0 == " " }) }
}

private func inputFiles() -> ColdSignal<String> {
	return ColdSignal.fromResult(getEnvironmentVariable("SCRIPT_INPUT_FILE_COUNT"))
		.map { $0.toInt()! }
		.map { count -> ColdSignal<String> in
			let variables = (0..<count).map { index -> ColdSignal<String> in
				return .fromResult(getEnvironmentVariable("SCRIPT_INPUT_FILE_\(index)"))
			}

			return ColdSignal.fromValues(variables).concat(identity)
		}
		.merge(identity)
}

private func getEnvironmentVariable(variable: String) -> Result<String> {
	let environment = NSProcessInfo.processInfo().environment

	if let value = environment[variable] as String? {
		return success(value)
	} else {
		return failure(CarthageError.MissingEnvironmentVariable(variable: variable).error)
	}
}
