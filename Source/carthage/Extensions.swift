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
import ReactiveSwift
import ReactiveTask

private let outputQueue = { () -> DispatchQueue in
	let queue = DispatchQueue(label: "org.carthage.carthage.outputQueue", target: .global(priority: .high))

	atexit_b {
		queue.sync(flags: .barrier) {}
	}

	return queue
}()

/// A thread-safe version of Swift's standard println().
internal func println() {
	outputQueue.async {
		Swift.print()
	}
}

/// A thread-safe version of Swift's standard println().
internal func println<T>(_ object: T) {
	outputQueue.async {
		Swift.print(object)
	}
}

/// A thread-safe version of Swift's standard print().
internal func print<T>(_ object: T) {
	outputQueue.async {
		Swift.print(object, terminator: "")
	}
}

extension String {
	/// Split the string into substrings separated by the given separators.
	internal func split(maxSplits: Int = .max, omittingEmptySubsequences: Bool = true, separators: [Character] = [ ",", " " ]) -> [String] {
		return characters
			.split(maxSplits: maxSplits, omittingEmptySubsequences: omittingEmptySubsequences, whereSeparator: separators.contains)
			.map(String.init)
	}
}

extension SignalProducerProtocol where Error == CarthageError {
	/// Waits on a SignalProducer that implements the behavior of a CommandProtocol.
	internal func waitOnCommand() -> Result<(), CarthageError> {
		let result = producer
			.then(SignalProducer<(), CarthageError>.empty)
			.wait()
		
		Task.waitForAllTaskTermination()
		return result
	}
}

extension GitURL: ArgumentProtocol {
	public static let name = "URL"

	public static func from(string: String) -> GitURL? {
		return self.init(string)
	}

	#if swift(>=3)
	#else
	public static func fromString(string: String) -> GitURL? {
		return from(string)
	}
	#endif
}

/// Logs project events put into the sink.
internal struct ProjectEventSink {
	private let colorOptions: ColorOptions
	
	init(colorOptions: ColorOptions) {
		self.colorOptions = colorOptions
	}
	
	mutating func put(_ event: ProjectEvent) {
		let formatting = colorOptions.formatting
		
		switch event {
		case let .cloning(project):
			carthage.println(formatting.bullets + "Cloning " + formatting.projectName(project.name))

		case let .fetching(project):
			carthage.println(formatting.bullets + "Fetching " + formatting.projectName(project.name))

		case let .checkingOut(project, revision):
			carthage.println(formatting.bullets + "Checking out " + formatting.projectName(project.name) + " at " + formatting.quote(revision))

		case let .downloadingBinaryFrameworkDefinition(project, url):
			carthage.println(formatting.bullets + "Downloading binary-only framework " + formatting.projectName(project.name) + " at " + formatting.quote(url.absoluteString))

		case let .downloadingBinaries(project, release):
			carthage.println(formatting.bullets + "Downloading " + formatting.projectName(project.name) + ".framework binary at " + formatting.quote(release))

		case let .skippedDownloadingBinaries(project, message):
			carthage.println(formatting.bullets + "Skipped downloading " + formatting.projectName(project.name) + ".framework binary due to the error:\n\t" + formatting.quote(message))

		case let .skippedInstallingBinaries(project, error):
			carthage.println(formatting.bullets + "Skipped installing " + formatting.projectName(project.name) + ".framework binary due to the error:\n\t" + formatting.quote(String(describing: error)))

		case let .skippedBuilding(project, message):
			carthage.println(formatting.bullets + "Skipped building " + formatting.projectName(project.name) + " due to the error:\n" + message)

		case let .skippedBuildingCached(project):
			carthage.println(formatting.bullets + "Valid cache found for " + formatting.projectName(project.name) + ", skipping build")

		case let .rebuildingCached(project):
			carthage.println(formatting.bullets + "Invalid cache found for " + formatting.projectName(project.name) + ", rebuilding with all downstream dependencies")

		case let .buildingUncached(project):
			carthage.println(formatting.bullets + "No cache found for " + formatting.projectName(project.name) + ", building with all downstream dependencies")
		}
	}
}
