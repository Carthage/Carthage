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
public struct TaskDescription {
	/// The path to the executable that should be launched.
	var launchPath: String

	/// Any arguments to provide to the executable.
	var arguments: [String]

	/// The path to the working directory in which the process should be
	/// launched.
	///
	/// If nil, the launched task will inherit the working directory of its
	/// parent.
	var workingDirectoryPath: String?

	/// Environment variables to set for the launched process.
	///
	/// If nil, the launched task will inherit the environment of its parent.
	var environment: [String: String]?

	/// Data to stream to standard input of the launched process.
	///
	/// An error sent along this signal will interrupt the task.
	///
	/// If nil, stdin will be inherited from the parent process.
	var standardInput: ColdSignal<NSData>?

	public init(launchPath: String, arguments: [String] = [], workingDirectoryPath: String? = nil, environment: [String: String]? = nil, standardInput: ColdSignal<NSData>? = nil) {
		self.launchPath = launchPath
		self.arguments = arguments
		self.workingDirectoryPath = workingDirectoryPath
		self.environment = environment
		self.standardInput = standardInput
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
/// If `standardError` is not specified, it will be inherited from the parent
/// process.
///
/// Returns a cold signal that will launch the task when started, then send one
/// `NSData` value (representing aggregated data from `stdout`) and complete
/// upon success.
public func launchTask(taskDescription: TaskDescription, standardOutput: SinkOf<NSData>? = nil, standardError: SinkOf<NSData>? = nil) -> ColdSignal<NSData> {
	return ColdSignal { subscriber in
		let task = NSTask()
		task.launchPath = taskDescription.launchPath
		task.arguments = taskDescription.arguments

		if let cwd = taskDescription.workingDirectoryPath {
			task.currentDirectoryPath = cwd
		}

		if let env = taskDescription.environment {
			task.environment = env
		}

		if let input = taskDescription.standardInput {
			let pipe = NSPipe()
			task.standardInput = pipe

			let disposable = input.start(next: { data in
				pipe.fileHandleForWriting.writeData(data)
			}, error: { error in
				task.interrupt()
			}, completed: {
				pipe.fileHandleForWriting.closeFile()
			})

			subscriber.disposable.addDisposable(disposable)
		}

		let (stdout, stdoutSink) = HotSignal<NSData>.pipe()
		task.standardOutput = pipeForWritingToSink(stdoutSink)

		let aggregatedOutput = stdout.scan(initial: NSData()) { (accumulated, data) in
			let buffer = accumulated.mutableCopy() as NSMutableData
			buffer.appendData(data)
			return buffer
		}.replay(1)

		// Start the aggregated output with an initial value.
		stdoutSink.put(NSData())

		// TODO: The memory management here is pretty screwy. We need to keep
		// `stdout` alive, so we'll create an unused observation and retain the
		// disposable.
		subscriber.disposable.addDisposable(stdout.observe { _ in () })

		if let output = standardOutput {
			subscriber.disposable.addDisposable(stdout.observe(output))
		}

		if let error = standardError {
			task.standardError = pipeForWritingToSink(error)
		}

		task.terminationHandler = { task in
			if task.terminationStatus == EXIT_SUCCESS {
				aggregatedOutput.take(1).start(subscriber)
			} else {
				let error = CarthageError.ShellTaskFailed(exitCode: Int(task.terminationStatus))
				subscriber.put(.Error(error.error))
			}
		}

		if subscriber.disposable.disposed {
			return
		}

		task.launch()
		subscriber.disposable.addDisposable {
			task.terminate()
		}
	}
}
