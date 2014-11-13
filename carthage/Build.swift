//
//  Build.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-11.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import LlamaKit
import ReactiveCocoa

public struct BuildCommand: CommandType {
	public let verb = "build"
	public let function = "Build the project in the current directory"

	public func run(mode: CommandMode) -> Result<()> {
		return ColdSignal.fromResult(BuildOptions.evaluate(mode))
			.map { options -> ColdSignal<()> in
				return self.openTemporaryLogFile()
					.map { (stdoutHandle, temporaryURL) -> ColdSignal<()> in
						let directoryURL = NSURL.fileURLWithPath(NSFileManager.defaultManager().currentDirectoryPath)!

						let (stdoutSignal, buildSignal) = self.buildProjectInDirectoryURL(directoryURL, options: options)
						let disposable = stdoutSignal.observe { data in
							stdoutHandle.writeData(data)
						}

						return buildSignal.on(subscribed: {
							println("*** xcodebuild output can be found in \(temporaryURL.path!)")
						}, disposed: {
							disposable.dispose()
						})
					}
					.merge(identity)
			}
			.merge(identity)
			.wait()
	}

	/// Builds the project in the given directory, using the given options.
	///
	/// Returns a hot signal of `stdout` from `xcodebuild`, and a cold signal
	/// that will actually begin the work (and indicate success or failure upon
	/// termination).
	private func buildProjectInDirectoryURL(directoryURL: NSURL, options: BuildOptions) -> (HotSignal<NSData>, ColdSignal<()>) {
		if (options.skipCurrent) {
			let (stdoutSignal, buildSignal) = buildDependenciesInDirectory(directoryURL, withConfiguration: options.configuration)
			return (stdoutSignal, buildSignal.then(.empty()))
		} else {
			let (stdoutSignal, buildSignal) = buildInDirectory(directoryURL, withConfiguration: options.configuration)
			return (stdoutSignal, buildSignal.then(.empty()))
		}
	}

	/// Opens a temporary file for logging, returning the handle and the URL to
	/// the file on disk.
	private func openTemporaryLogFile() -> ColdSignal<(NSFileHandle, NSURL)> {
		return ColdSignal.lazy {
			var temporaryDirectoryTemplate: ContiguousArray<CChar> = NSTemporaryDirectory().stringByAppendingPathComponent("carthage-xcodebuild.XXXXXX.log").nulTerminatedUTF8.map { CChar($0) }
			let logFD = temporaryDirectoryTemplate.withUnsafeMutableBufferPointer { (inout template: UnsafeMutableBufferPointer<CChar>) -> Int32 in
				return mkstemps(template.baseAddress, 4)
			}

			if logFD < 0 {
				return .error(NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil))
			}

			let temporaryPath = temporaryDirectoryTemplate.withUnsafeBufferPointer { (ptr: UnsafeBufferPointer<CChar>) -> String in
				return String.fromCString(ptr.baseAddress)!
			}

			let stdoutHandle = NSFileHandle(fileDescriptor: logFD, closeOnDealloc: true)
			let temporaryURL = NSURL.fileURLWithPath(temporaryPath, isDirectory: false)!
			return .single((stdoutHandle, temporaryURL))
		}
	}
}

private struct BuildOptions: OptionsType {
	let configuration: String
	let skipCurrent: Bool

	static func create(configuration: String)(skipCurrent: Bool) -> BuildOptions {
		return self(configuration: configuration, skipCurrent: skipCurrent)
	}

	static func evaluate(m: CommandMode) -> Result<BuildOptions> {
		return create
			<*> m <| Option(key: "configuration", defaultValue: "Release", usage: "the Xcode configuration to build")
			<*> m <| Option(key: "skip-current", defaultValue: true, usage: "whether to skip the project in the current directory, and only build its dependencies")
	}
}
