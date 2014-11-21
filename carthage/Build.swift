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
	public let function = "Build the project's dependencies"

	public func run(mode: CommandMode) -> Result<()> {
		return ColdSignal.fromResult(BuildOptions.evaluate(mode))
			.map { self.buildWithOptions($0) }
			.merge(identity)
			.wait()
	}

	/// Builds a project with the given options.
	public func buildWithOptions(options: BuildOptions) -> ColdSignal<()> {
		return self.openTemporaryLogFile()
			.map { (stdoutHandle, temporaryURL) -> ColdSignal<()> in
				let directoryURL = NSURL.fileURLWithPath(options.directoryPath, isDirectory: true)!

				let (stdoutSignal, schemeSignals) = self.buildProjectInDirectoryURL(directoryURL, options: options)
				let disposable = stdoutSignal.observe { data in
					stdoutHandle.writeData(data)
				}

				return schemeSignals
					.concat(identity)
					.on(subscribed: {
						println("*** xcodebuild output can be found in \(temporaryURL.path!)")
					}, next: { (project, scheme) in
						println("*** Building scheme \"\(scheme)\" in \(project)")
					}, disposed: {
						disposable.dispose()
					})
					.then(.empty())
			}
			.merge(identity)
	}

	/// Builds the project in the given directory, using the given options.
	///
	/// Returns a hot signal of `stdout` from `xcodebuild`, and a cold signal of
	/// cold signals representing each scheme being built.
	private func buildProjectInDirectoryURL(directoryURL: NSURL, options: BuildOptions) -> (HotSignal<NSData>, ColdSignal<BuildSchemeSignal>) {
		let (stdoutSignal, stdoutSink) = HotSignal<NSData>.pipe()

		var buildSignal = ColdSignal<Project>.lazy {
				return .fromResult(Project.loadFromDirectory(directoryURL))
			}
			.catch { error in
				if options.skipCurrent {
					return .error(error)
				} else {
					// Ignore Cartfile loading failures. Assume the user just
					// wants to build the enclosing project.
					return .empty()
				}
			}
			.map { project -> ColdSignal<BuildSchemeSignal> in
				let (dependenciesOutput, dependenciesSignals) = project.buildCheckedOutDependencies(options.configuration)

				return ColdSignal.lazy {
					let dependenciesDisposable = dependenciesOutput.observe(stdoutSink)

					return dependenciesSignals
						.on(disposed: {
							dependenciesDisposable.dispose()
						})
				}
			}
			.merge(identity)

		if !options.skipCurrent {
			let (currentOutput, currentSignals) = buildInDirectory(directoryURL, withConfiguration: options.configuration)
			let dependenciesSignal = buildSignal

			buildSignal = ColdSignal.lazy {
				let currentDisposable = currentOutput.observe(stdoutSink)

				return dependenciesSignal
					.then(currentSignals)
					.on(disposed: {
						currentDisposable.dispose()
					})
			}
		}

		return (stdoutSignal, buildSignal)
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

public struct BuildOptions: OptionsType {
	public let configuration: String
	public let skipCurrent: Bool
	public let directoryPath: String

	public static func create(configuration: String)(skipCurrent: Bool)(directoryPath: String) -> BuildOptions {
		return self(configuration: configuration, skipCurrent: skipCurrent, directoryPath: directoryPath)
	}

	public static func evaluate(m: CommandMode) -> Result<BuildOptions> {
		return create
			<*> m <| Option(key: "configuration", defaultValue: "Release", usage: "the Xcode configuration to build")
			<*> m <| Option(key: "skip-current", defaultValue: true, usage: "don't skip building the Carthage project (in addition to its dependencies)")
			<*> m <| Option(defaultValue: NSFileManager.defaultManager().currentDirectoryPath, usage: "the directory containing the Carthage project")
	}
}
