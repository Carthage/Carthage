//
//  Task.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import ReactiveCocoa

/// Describes how to execute a shell command.
internal struct TaskDescription {
	/// The path to the executable that should be launched.
	var launchPath: String

	/// Any arguments to provide to the executable.
	var arguments: [String] = []

	/// The path to the working directory in which the process should be
	/// launched.
	///
	/// If nil, the launched task will inherit the working directory of its
	/// parent.
	var workingDirectoryPath: String? = nil

	/// Environment variables to set for the launched process.
	///
	/// If nil, the launched task will inherit the environment of its parent.
	var environment: [String: String]? = nil

	/// Creates an `NSTask` instance, configured according to the properties of
	/// the receiver.
	private func configuredNSTask() -> NSTask {
		let task = NSTask()
		task.launchPath = launchPath
		task.arguments = arguments

		if let cwd = workingDirectoryPath {
			task.currentDirectoryPath = cwd
		}

		if let env = environment {
			task.environment = env
		}

		return task
	}
}

/// Creates a pipe that, when written to, will place data into the given sink.
private func pipeForWritingToSink(sink: SinkOf<NSData>) -> NSPipe {
	let pipe = NSPipe()

	pipe.fileHandleForReading.readabilityHandler = { handle in
		sink.put(handle.availableData)
	}

	return pipe
}

/// Launches a new shell task, using the parameters from `taskDescription`.
///
/// If any of `standardInput`, `standardOutput`, or `standardError` are not
/// specified, the corresponding handle is inherited from the parent process.
///
/// Returns a promise that will launch the task when started, then eventually
/// resolve to the task's exit status.
internal func launchTask(taskDescription: TaskDescription, standardInput: SequenceOf<NSData>? = nil, standardOutput: SinkOf<NSData>? = nil, standardError: SinkOf<NSData>? = nil) -> Promise<Int32> {
	let task = taskDescription.configuredNSTask()

	if let input = standardInput {
		let pipe = NSPipe()
		task.standardInput = pipe

		var generator = input.generate()
		pipe.fileHandleForWriting.writeabilityHandler = { handle in
			if let data = generator.next() {
				handle.writeData(data)
			} else {
				handle.closeFile()
				handle.writeabilityHandler = nil
			}
		}
	}

	if let output = standardOutput {
		task.standardOutput = pipeForWritingToSink(output)
	}

	if let error = standardError {
		task.standardError = pipeForWritingToSink(error)
	}

	return Promise { sink in
		task.terminationHandler = { task in
			sink.put(task.terminationStatus)
		}

		task.launch()
	}
}
