//
//  Task.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
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

/// A private class used to encapsulate a Unix pipe.
private final class Pipe {
	/// The file descriptor for reading data.
	let readFD: Int32

	/// The file descriptor for writing data.
	let writeFD: Int32

	/// Creates an NSFileHandle corresponding to the `readFD`. The file handle
	/// will not automatically close the descriptor.
	var readHandle: NSFileHandle {
		return NSFileHandle(fileDescriptor: readFD, closeOnDealloc: false)
	}

	/// Creates an NSFileHandle corresponding to the `writeFD`. The file handle
	/// will not automatically close the descriptor.
	var writeHandle: NSFileHandle {
		return NSFileHandle(fileDescriptor: writeFD, closeOnDealloc: false)
	}

	/// Initializes a pipe object using existing file descriptors.
	init(readFD: Int32, writeFD: Int32) {
		precondition(readFD >= 0)
		precondition(writeFD >= 0)

		self.readFD = readFD
		self.writeFD = writeFD
	}

	/// Instantiates a new descriptor pair.
	class func create() -> Result<Pipe> {
		var fildes: [Int32] = [ 0, 0 ]
		if pipe(&fildes) == 0 {
			return success(self(readFD: fildes[0], writeFD: fildes[1]))
		} else {
			let nsError = NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
			return failure(nsError)
		}
	}

	/// Closes both file descriptors of the receiver.
	func closePipe() {
		close(readFD)
		close(writeFD)
	}

	/// Creates a signal that will take ownership of the `readFD` using
	/// dispatch_io, then read it to completion.
	///
	/// After subscribing to the returned signal, `readFD` should not be used
	/// anywhere else, as it may close unexpectedly.
	func transferReadsToSignal() -> ColdSignal<dispatch_data_t> {
		let queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)

		return ColdSignal { subscriber in
			let channel = dispatch_io_create(DISPATCH_IO_STREAM, self.readFD, queue) { error in
				if error == 0 {
					subscriber.put(.Completed)
				} else {
					let nsError = NSError(domain: NSPOSIXErrorDomain, code: Int(error), userInfo: nil)
					subscriber.put(.Error(nsError))
				}

				close(self.readFD)
			}

			dispatch_io_set_low_water(channel, 1)
			dispatch_io_read(channel, 0, UInt.max, queue) { (done, data, error) in
				if let data = data {
					subscriber.put(.Next(Box(data)))
				}

				if error != 0 {
					let nsError = NSError(domain: NSPOSIXErrorDomain, code: Int(error), userInfo: nil)
					subscriber.put(.Error(nsError))
				}

				if done {
					dispatch_io_close(channel, 0)
				}
			}

			subscriber.disposable.addDisposable {
				dispatch_io_close(channel, DISPATCH_IO_STOP)
			}
		}
	}

	/// Creates a dispatch_io channel for writing all data that arrives on
	/// `signal` into `writeFD`, then closes `writeFD` when the input signal
	/// terminates.
	///
	/// After subscribing to the returned signal, `writeFD` should not be used
	/// anywhere else, as it may close unexpectedly.
	///
	/// Returns a signal that will complete or error.
	func writeDataFromSignal(signal: ColdSignal<NSData>) -> ColdSignal<()> {
		let queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)

		return ColdSignal { subscriber in
			let channel = dispatch_io_create(DISPATCH_IO_STREAM, self.writeFD, queue) { error in
				if error == 0 {
					subscriber.put(.Completed)
				} else {
					let nsError = NSError(domain: NSPOSIXErrorDomain, code: Int(error), userInfo: nil)
					subscriber.put(.Error(nsError))
				}

				close(self.writeFD)
			}

			let disposable = signal.start(next: { data in
				let dispatchData = dispatch_data_create(data.bytes, UInt(data.length), queue, nil)

				dispatch_io_write(channel, 0, dispatchData, queue) { (done, data, error) in
					if error != 0 {
						let nsError = NSError(domain: NSPOSIXErrorDomain, code: Int(error), userInfo: nil)
						subscriber.put(.Error(nsError))
					}
				}
			}, error: { error in
				subscriber.put(.Error(error))
			}, completed: {
				dispatch_io_close(channel, 0)
			})

			subscriber.disposable.addDisposable {
				disposable.dispose()
				dispatch_io_close(channel, DISPATCH_IO_STOP)
			}
		}
	}
}

/// Takes ownership of the read handle from the given pipe, then aggregates all
/// data into one `NSData` object, which is then sent upon the returned signal.
///
/// If `forwardingSink` is non-nil, each incremental piece of data will be sent
/// to it as data is received.
private func aggregateDataReadFromPipe(pipe: Pipe, forwardingSink: SinkOf<NSData>?) -> ColdSignal<NSData> {
	return pipe.transferReadsToSignal()
		.on(next: { (data: dispatch_data_t) in
			forwardingSink?.put(data as NSData)
			return ()
		})
		.reduce(initial: nil) { (buffer: dispatch_data_t?, data: dispatch_data_t) in
			if let buffer = buffer {
				return dispatch_data_create_concat(buffer, data)
			} else {
				return data
			}
		}
		.map { (data: dispatch_data_t?) -> NSData in
			if let data = data {
				return data as NSData
			} else {
				return NSData()
			}
		}
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

		var stdinSignal: ColdSignal<()> = .empty()

		if let input = taskDescription.standardInput {
			switch Pipe.create() {
			case let .Success(pipe):
				task.standardInput = pipe.unbox.readHandle

				stdinSignal = ColdSignal.lazy {
					close(pipe.unbox.readFD)
					return pipe.unbox.writeDataFromSignal(input)
				}

			case let .Failure(error):
				subscriber.put(.Error(error))
				return
			}
		}

		let taskDisposable = ColdSignal.fromResult(Pipe.create())
			// TODO: This should be a zip.
			.combineLatestWith(ColdSignal.fromResult(Pipe.create()))
			.map { (stdoutPipe, stderrPipe) in
				let stdoutSignal = aggregateDataReadFromPipe(stdoutPipe, standardOutput)
				let stderrSignal = aggregateDataReadFromPipe(stderrPipe, standardError)

				let terminationStatusSignal = ColdSignal<Int32> { subscriber in
					task.terminationHandler = { task in
						subscriber.put(.Next(Box(task.terminationStatus)))
						subscriber.put(.Completed)
					}

					task.standardOutput = stdoutPipe.writeHandle
					task.standardError = stderrPipe.writeHandle

					if subscriber.disposable.disposed {
						stdoutPipe.closePipe()
						stderrPipe.closePipe()
						return
					}

					task.launch()
					close(stdoutPipe.writeFD)
					close(stderrPipe.writeFD)

					let stdinDisposable = stdinSignal.start(error: { error in
						subscriber.put(.Error(error))
					})

					subscriber.disposable.addDisposable {
						task.terminate()
						stdinDisposable.dispose()
					}
				}

				return stdoutSignal
					.combineLatestWith(stderrSignal)
					.combineLatestWith(terminationStatusSignal)
					.map { (datas, terminationStatus) -> (NSData, NSData, Int32) in
						return (datas.0, datas.1, terminationStatus)
					}
					.tryMap { (stdoutData, stderrData, terminationStatus) -> Result<NSData> in
						if terminationStatus == EXIT_SUCCESS {
							return success(stdoutData)
						} else {
							let errorString = (stderrData.length > 0 ? NSString(data: stderrData, encoding: NSUTF8StringEncoding) as String? : nil)
							let error = CarthageError.ShellTaskFailed(exitCode: Int(terminationStatus), standardError: errorString).error
							return failure(error)
						}
					}
			}
			.merge(identity)
			.start(subscriber)

		subscriber.disposable.addDisposable(taskDisposable)
	}
}
