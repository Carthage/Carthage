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
	public let function = "Copies the frameworks, striping symbols as necesssary."

	public func run(mode: CommandMode) -> Result<()> {
		let files = getEnvironmentVariable("SCRIPT_INPUT_FILE_COUNT")
			.map { $0.toInt()! }
			.flatMap { count -> Result<[String]> in
				var files = [] as [String]

				for i in 0..<count {
					let file = getEnvironmentVariable("SCRIPT_INPUT_FILE_\(i)")

					if let file = file.value() {
						files.append(file)
					} else {
						return failure(file.error()!)
					}
				}

				return success(files)
			}

		return ColdSignal.fromResult(files)
			.map { files -> ColdSignal<()> in
				let signals = files.map { frameworkPath -> ColdSignal<()> in
					let frameworkName = frameworkPath.lastPathComponent

					let source = NSURL(fileURLWithPath: frameworkPath, isDirectory: true)!
					let target = frameworksFolder().map({ $0.URLByAppendingPathComponent(frameworkName, isDirectory: true) })

					return ColdSignal.single(source)
						.combineLatestWith(.fromResult(target))
						.map { (source, target) -> ColdSignal<()> in
							let stripArchitectures = architecturesInFramework(target)
								.combineLatestWith(.fromResult(validArchitectures()))
								.map { (existingArchitectures, validArchitectures) -> ColdSignal<()> in
									let tasks = existingArchitectures.filter {
											!contains(validArchitectures, $0)
										}
										.map { architecture -> ColdSignal<()> in
											return stripArchitecture(target, architecture)
										}

									return concat(tasks)
								}
								.merge(identity)

							let codeSign = ColdSignal<()>.lazy {
								if !codeSigningAllowed() { return .empty() }

								return ColdSignal.fromResult(getEnvironmentVariable("EXPANDED_CODE_SIGN_IDENTITY"))
									.map({ codesign(target, $0) })
									.merge(identity)
							}

							return copyFramework(source, target)
								.concat(stripArchitectures)
								.concat(codeSign)
								.then(.empty())
						}
						.merge(identity)
				}

				return concat(signals)
			}
			.merge(identity)
			.wait()
	}
}

private func concat<T>(signals: [ColdSignal<T>]) -> ColdSignal<T> {
	return reduce(signals, ColdSignal<T>.empty(), { $0.concat($1) })
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
	return getEnvironmentVariable("VALID_ARCHS").map({ return split($0, { $0 == " " }) })
}

private func getEnvironmentVariable(variable: String) -> Result<String> {
	let environment = NSProcessInfo.processInfo().environment

	if let value = environment[variable] as String? {
		return success(value)
	} else {
		return failure(CarthageError.MissingEnvironmentVariableError(variable: variable).error)
	}
}
