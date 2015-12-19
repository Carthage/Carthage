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

extension String {
	/// Split the string into substrings separated by the given separators.
	internal func split(allowEmptySlices: Bool = false, separators: [Character] = [ ",", " " ]) -> [String] {
		return characters
			.split(allowEmptySlices: allowEmptySlices, isSeparator: separators.contains)
			.map(String.init)
	}
}

extension SignalProducerType where Error == CarthageError {
	/// Waits on a SignalProducer that implements the behavior of a CommandType.
	internal func waitOnCommand() -> Result<(), CarthageError> {
		let result = producer
			.then(SignalProducer<(), CarthageError>.empty)
			.wait()
		
		Task.waitForAllTaskTermination()
		return result
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
