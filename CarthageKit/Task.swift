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
	public var launchPath: String

	/// Any arguments to provide to the executable.
	public var arguments: [String]

	/// The path to the working directory in which the process should be
	/// launched.
	///
	/// If nil, the launched task will inherit the working directory of its
	/// parent.
	public var workingDirectoryPath: String?

	/// Environment variables to set for the launched process.
	///
	/// If nil, the launched task will inherit the environment of its parent.
	public var environment: [String: String]?

	/// Data to stream to standard input of the launched process.
	///
	/// An error sent along this signal will interrupt the task.
	///
	/// If nil, stdin will be inherited from the parent process.
	public var standardInput: ColdSignal<NSData>?

	public init(launchPath: String, arguments: [String] = [], workingDirectoryPath: String? = nil, environment: [String: String]? = nil, standardInput: ColdSignal<NSData>? = nil) {
		self.launchPath = launchPath
		self.arguments = arguments
		self.workingDirectoryPath = workingDirectoryPath
		self.environment = environment
		self.standardInput = standardInput
	}
}

extension TaskDescription: Printable {
	public var description: String {
		var str = "\(launchPath)"

		for arg in arguments {
			str += " \(arg)"
		}

		return str
	}
}

/// Creates an NSPipe that will aggregate all data sent to it, and eventually
/// replay it upon the returned signal.
///
/// If a sink is given, data received on the pipe will also be forwarded to it
/// as it arrives.
private func pipeForAggregatingData(forwardingSink: SinkOf<NSData>?) -> (NSPipe, ColdSignal<NSData>) {
	let (signal, sink) = HotSignal<NSData>.pipe()
	let pipe = NSPipe()

	pipe.fileHandleForReading.readabilityHandler = { handle in
		let data = handle.availableData
		sink.put(data)
		forwardingSink?.put(data)
	}

	let aggregatedData = signal.scan(initial: NSData()) { (accumulated, data) in
		let buffer = accumulated.mutableCopy() as NSMutableData
		buffer.appendData(data)
		return buffer
	}.replay(1)

	// Start the aggregated data with an initial value.
	sink.put(NSData())

	return (pipe, aggregatedData)
}

/// Launches a new shell task, using the parameters from `taskDescription`.
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

		let (stdoutPipe, stdout) = pipeForAggregatingData(standardOutput)
		task.standardOutput = stdoutPipe

		let (stderrPipe, stderr) = pipeForAggregatingData(standardError)
		task.standardError = stderrPipe

		task.terminationHandler = { task in
			if task.terminationStatus == EXIT_SUCCESS {
				stdout.take(1).start(subscriber)
			} else {
				stderr
					.take(1)
					.map { data -> String? in
						if data.length > 0 {
							return NSString(data: data, encoding: NSUTF8StringEncoding) as String?
						} else {
							return nil
						}
					}
					.start(next: { string in
						let error = CarthageError.ShellTaskFailed(exitCode: Int(task.terminationStatus), standardError: string)
						subscriber.put(.Error(error.error))
					})
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
