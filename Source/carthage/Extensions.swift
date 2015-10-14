//
//  Extensions.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-26.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

// This file contains extensions to anything that's not appropriate for
// CarthageKit.

import CarthageKit
import Commandant
import Foundation
import Result
import ReactiveCocoa
import ReactiveTask

private let outputQueue = { () -> dispatch_queue_t in
	let queue = dispatch_queue_create("org.carthage.carthage.outputQueue", DISPATCH_QUEUE_SERIAL)
	dispatch_set_target_queue(queue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0))

	atexit_b {
		dispatch_barrier_sync(queue) {}
	}

	return queue
}()

/// A thread-safe version of Swift's standard println().
internal func println() {
	dispatch_async(outputQueue) {
		Swift.print()
	}
}

/// A thread-safe version of Swift's standard println().
internal func println<T>(object: T) {
	dispatch_async(outputQueue) {
		Swift.print(object)
	}
}

/// A thread-safe version of Swift's standard print().
internal func print<T>(object: T) {
	dispatch_async(outputQueue) {
		Swift.print(object, terminator: "")
	}
}

/// Wraps CommandantError and adds ErrorType conformance.
public struct CommandError: ErrorType {
	public let error: CommandantError<CarthageError>

	public init(_ error: CommandantError<CarthageError>) {
		self.error = error
	}
}

extension CommandError: CustomStringConvertible {
	public var description: String {
		return error.description
	}
}

/// Transforms the error type in a Result.
extension Result {
	internal func mapError<F>(transform: Error -> F) -> Result<Value, F> {
		switch self {
		case let .Success(value):
			return .Success(value)

		case let .Failure(error):
			return .Failure(transform(error))
		}
	}
}

extension SignalType where E == CarthageError {
	/// Promotes CarthageErrors into CommandErrors.
	internal func promoteErrors() -> Signal<T, CommandError> {
		return signal.mapError { (error: CarthageError) -> CommandError in
			let commandantError = CommandantError.CommandError(error)
			return CommandError(commandantError)
		}
	}
}

extension SignalProducerType where E == CarthageError {
	/// Promotes CarthageErrors into CommandErrors.
	internal func promoteErrors() -> SignalProducer<T, CommandError> {
		return lift { $0.promoteErrors() }
	}
}

/// Lifts the Result of options parsing into a SignalProducer.
internal func producerWithOptions<T>(result: Result<T, CommandantError<CarthageError>>) -> SignalProducer<T, CommandError> {
	let mappedResult = result.mapError { CommandError($0) }
	return SignalProducer(result: mappedResult)
}

extension SignalProducerType where E == CommandError {
	/// Waits on a SignalProducer that implements the behavior of a CommandType.
	internal func waitOnCommand() -> Result<(), CommandantError<CarthageError>> {
		let result = producer
			.then(SignalProducer<(), CommandError>.empty)
			.wait()
		
		TaskDescription.waitForAllTaskTermination()
		return result.mapError { $0.error }
	}
}

extension GitURL: ArgumentType {
	public static let name = "URL"

	public static func fromString(string: String) -> GitURL? {
		return self.init(string)
	}
}

/// Logs project events put into the sink.
internal struct ProjectEventSink {
	private let colorOptions: ColorOptions
	
	init(colorOptions: ColorOptions) {
		self.colorOptions = colorOptions
	}
	
	mutating func put(event: ProjectEvent) {
		let formatting = colorOptions.formatting
		
		switch event {
		case let .Cloning(project):
			carthage.println(formatting.bullets + "Cloning " + formatting.projectName(string: project.name))

		case let .Fetching(project):
			carthage.println(formatting.bullets + "Fetching " + formatting.projectName(string: project.name))

		case let .CheckingOut(project, revision):
			carthage.println(formatting.bullets + "Checking out " + formatting.projectName(string: project.name) + " at " + formatting.quote(revision))

		case let .DownloadingBinaries(project, release):
			carthage.println(formatting.bullets + "Downloading " + formatting.projectName(string: project.name) + ".framework binary at " + formatting.quote(release))

		case let .SkippedDownloadingBinaries(project, message):
			carthage.println(formatting.bullets + "Skipped downloading " + formatting.projectName(string: project.name) + ".framework binary due to the error:\n\t" + formatting.quote(message))

		case let .SkippedBuilding(project, message):
			carthage.println(formatting.bullets + "Skipped building " + formatting.projectName(string: project.name) + " due to the error:\n" + message)
		}
	}
}

extension Project {
	/// Determines whether the project needs to be migrated from an older
	/// Carthage version, then performs the work if so.
	///
	/// If migration is necessary, sends one or more output lines describing the
	/// process to the user.
	internal func migrateIfNecessary(colorOptions: ColorOptions) -> SignalProducer<String, CarthageError> {
		let directoryPath = directoryURL.path!
		let fileManager = NSFileManager.defaultManager()

		// These don't need to be declared more globally, since they're only for
		// migration. We shouldn't need these names anywhere else.
		let cartfileLock = "Cartfile.lock"
		let carthageBuild = "Carthage.build"
		let carthageCheckout = "Carthage.checkout"
		
		let formatting = colorOptions.formatting
		let migrationMessage = formatting.bulletinTitle("MIGRATION WARNING") + "\n\nThis project appears to be set up for an older (pre-0.4) version of Carthage. Unfortunately, the directory structure for Carthage projects has since changed, so this project will be migrated automatically.\n\nSpecifically, the following renames will occur:\n\n  \(cartfileLock) -> \(CarthageProjectResolvedCartfilePath)\n  \(carthageBuild) -> \(CarthageBinariesFolderPath)\n  \(carthageCheckout) -> \(CarthageProjectCheckoutsPath)\n\nFor more information, see " + formatting.URL(string: "https://github.com/Carthage/Carthage/pull/224") + ".\n"

		let producers = SignalProducer<SignalProducer<String, CarthageError>, CarthageError> { observer, disposable in
			let checkFile: (String, String) -> () = { oldName, newName in
				if fileManager.fileExistsAtPath((directoryPath as NSString).stringByAppendingPathComponent(oldName)) {
					let producer = SignalProducer(value: migrationMessage)
						.concat(moveItemInPossibleRepository(self.directoryURL, fromPath: oldName, toPath: newName)
							.then(.empty))

					sendNext(observer, producer)
				}
			}

			checkFile(cartfileLock, CarthageProjectResolvedCartfilePath)
			checkFile(carthageBuild, CarthageBinariesFolderPath)

			// Carthage.checkout has to be handled specially, because if it
			// includes submodules, we need to move them one-by-one to ensure
			// that .gitmodules is properly updated.
			if fileManager.fileExistsAtPath((directoryPath as NSString).stringByAppendingPathComponent(carthageCheckout)) {
				let oldCheckoutsURL = self.directoryURL.URLByAppendingPathComponent(carthageCheckout)

				do {
					let contents = try fileManager.contentsOfDirectoryAtURL(oldCheckoutsURL, includingPropertiesForKeys: nil, options: [ .SkipsSubdirectoryDescendants, .SkipsPackageDescendants, .SkipsHiddenFiles ])
					let trashProducer = SignalProducer<(), CarthageError>.attempt {
						do {
							try fileManager.trashItemAtURL(oldCheckoutsURL, resultingItemURL: nil)
							return .Success(())
						} catch let error as NSError {
							return .Failure(CarthageError.WriteFailed(oldCheckoutsURL, error))
						}
					}

					let moveProducer: SignalProducer<(), CarthageError> = SignalProducer(values: contents)
						.map { (object: AnyObject) in object as! NSURL }
						.flatMap(.Concat) { (URL: NSURL) -> SignalProducer<NSURL, CarthageError> in
							let lastPathComponent: String! = URL.lastPathComponent
							return moveItemInPossibleRepository(self.directoryURL, fromPath: (carthageCheckout as NSString).stringByAppendingPathComponent(lastPathComponent), toPath: (CarthageProjectCheckoutsPath as NSString).stringByAppendingPathComponent(lastPathComponent))
						}
						.then(trashProducer)
						.then(.empty)

					let producer = SignalProducer<String, CarthageError>(value: migrationMessage)
						.concat(moveProducer
							.then(.empty))

					sendNext(observer, producer)
				} catch let error as NSError {
					sendError(observer, CarthageError.ReadFailed(oldCheckoutsURL, error))
					return
				}
			}

			sendCompleted(observer)
		}

		return producers
			.flatten(.Concat)
			.takeLast(1)
	}
}
