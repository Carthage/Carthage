//
//  Extensions.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-26.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

// This file contains extensions to anything that's not appropriate for
// CarthageKit.

import Box
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
		Swift.println()
	}
}

/// A thread-safe version of Swift's standard println().
internal func println<T>(object: T) {
	dispatch_async(outputQueue) {
		Swift.println(object)
	}
}

/// A thread-safe version of Swift's standard print().
internal func print<T>(object: T) {
	dispatch_async(outputQueue) {
		Swift.print(object)
	}
}

/// Wraps CommandantError and adds ErrorType conformance.
public struct CommandError {
	public let error: CommandantError<CarthageError>

	public init(_ error: CommandantError<CarthageError>) {
		self.error = error
	}
}

extension CommandError: Printable {
	public var description: String {
		return error.description
	}
}

extension CommandError: ErrorType {
	public var nsError: NSError {
		switch error {
		case let .UsageError(description):
			return NSError(domain: "org.carthage.Carthage", code: 0, userInfo: [
				NSLocalizedDescriptionKey: description
			])

		case let .CommandError(commandError):
			return commandError.value.nsError
		}
	}
}

/// Transforms the error type in a Result.
internal func mapError<T, E, F>(result: Result<T, E>, transform: E -> F) -> Result<T, F> {
	switch result {
	case let .Success(value):
		return .Success(value)

	case let .Failure(error):
		return .Failure(Box(transform(error.value)))
	}
}

/// Promotes CarthageErrors into CommandErrors.
internal func promoteErrors<T>(signal: Signal<T, CarthageError>) -> Signal<T, CommandError> {
	return signal |> mapError { (error: CarthageError) -> CommandError in
		let commandantError = CommandantError.CommandError(Box(error))
		return CommandError(commandantError)
	}
}

/// Lifts the Result of options parsing into a SignalProducer.
internal func producerWithOptions<T>(result: Result<T, CommandantError<CarthageError>>) -> SignalProducer<T, CommandError> {
	let mappedResult = mapError(result) { CommandError($0) }
	return SignalProducer(result: mappedResult)
}

/// Waits on a SignalProducer that implements the behavior of a CommandType.
internal func waitOnCommand<T>(producer: SignalProducer<T, CommandError>) -> Result<(), CommandantError<CarthageError>> {
	let result = producer
		|> then(SignalProducer<(), CommandError>.empty)
		|> wait
	
	TaskDescription.waitForAllTaskTermination()
	return mapError(result) { $0.error }
}

extension GitURL: ArgumentType {
	public static let name = "URL"

	public static func fromString(string: String) -> GitURL? {
		return self(string)
	}
}

/// Logs project events put into the sink.
internal struct ProjectEventSink: SinkType {
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
			carthage.println(formatting.bullets + "Downloading " + formatting.projectName(string: project.name) + " at " + formatting.quote(release))
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
				if fileManager.fileExistsAtPath(directoryPath.stringByAppendingPathComponent(oldName)) {
					let producer = SignalProducer(value: migrationMessage)
						|> concat(moveItemInPossibleRepository(self.directoryURL, fromPath: oldName, toPath: newName)
							|> then(.empty))

					sendNext(observer, producer)
				}
			}

			checkFile(cartfileLock, CarthageProjectResolvedCartfilePath)
			checkFile(carthageBuild, CarthageBinariesFolderPath)

			// Carthage.checkout has to be handled specially, because if it
			// includes submodules, we need to move them one-by-one to ensure
			// that .gitmodules is properly updated.
			if fileManager.fileExistsAtPath(directoryPath.stringByAppendingPathComponent(carthageCheckout)) {
				let oldCheckoutsURL = self.directoryURL.URLByAppendingPathComponent(carthageCheckout)

				var error: NSError?
				if let contents = fileManager.contentsOfDirectoryAtURL(oldCheckoutsURL, includingPropertiesForKeys: nil, options: NSDirectoryEnumerationOptions.SkipsSubdirectoryDescendants | NSDirectoryEnumerationOptions.SkipsPackageDescendants | NSDirectoryEnumerationOptions.SkipsHiddenFiles, error: &error) {
					let trashProducer = SignalProducer<(), CarthageError>.try {
						var error: NSError?
						if fileManager.trashItemAtURL(oldCheckoutsURL, resultingItemURL: nil, error: &error) {
							return .success(())
						} else {
							return .failure(CarthageError.WriteFailed(oldCheckoutsURL, error))
						}
					}

					let moveProducer: SignalProducer<(), CarthageError> = SignalProducer(values: contents)
						|> map { (object: AnyObject) in object as! NSURL }
						|> flatMap(.Concat) { (URL: NSURL) -> SignalProducer<NSURL, CarthageError> in
							let lastPathComponent: String! = URL.lastPathComponent
							return moveItemInPossibleRepository(self.directoryURL, fromPath: carthageCheckout.stringByAppendingPathComponent(lastPathComponent), toPath: CarthageProjectCheckoutsPath.stringByAppendingPathComponent(lastPathComponent))
						}
						|> then(trashProducer)
						|> then(.empty)

					let producer = SignalProducer<String, CarthageError>(value: migrationMessage)
						|> concat(moveProducer
							|> then(.empty))

					sendNext(observer, producer)
				} else {
					sendError(observer, CarthageError.ReadFailed(oldCheckoutsURL, error))
					return
				}
			}

			sendCompleted(observer)
		}

		return producers
			|> flatten(.Concat)
			|> takeLast(1)
	}
}
