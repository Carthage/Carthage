//
//  FileSink.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2015-03-06.
//  Copyright (c) 2015 Carthage. All rights reserved.
//

import Foundation
import ReactiveCocoa

/// Represents anything that can be written directly to a file.
public protocol FileWriteable {
	// TODO: Error handling.
	func writeToFile(filePointer: UnsafeMutablePointer<FILE>)
}

extension NSData: FileWriteable {
	public func writeToFile(filePointer: UnsafeMutablePointer<FILE>) {
		fwrite(bytes, UInt(length), 1, filePointer)
	}
}

extension String: FileWriteable {
	public func writeToFile(filePointer: UnsafeMutablePointer<FILE>) {
		fputs(self, filePointer)
	}
}

/// A sink which streams its events to a file handle.
public final class FileSink<T: FileWriteable>: SinkType {
	private var filePointer: UnsafeMutablePointer<FILE>?
	private let closeWhenDone: Bool

	/// Creates a sink that will take over the given FILE * pointer.
	private init(filePointer: UnsafeMutablePointer<FILE>, closeWhenDone: Bool) {
		setlinebuf(filePointer)

		self.filePointer = filePointer
		self.closeWhenDone = closeWhenDone
	}

	/// Creates a sink that will take over the given file descriptor.
	private class func sinkWithDescriptor(fileDescriptor: Int32, closeWhenDone: Bool) -> ColdSignal<FileSink> {
		return ColdSignal.lazy {
			let pointer = fdopen(fileDescriptor, "a")
			
			if pointer == nil {
				return .error(NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil))
			} else {
				return .single(self(filePointer: pointer, closeWhenDone: closeWhenDone))
			}
		}
	}

	/// Creates a sink that will open and write to a temporary file.
	/// 
	/// Sends the created sink and the URL to the temporary file.
	public class func openTemporaryFile() -> ColdSignal<(FileSink, NSURL)> {
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

			return self.sinkWithDescriptor(logFD, closeWhenDone: true)
				.map { ($0, NSURL.fileURLWithPath(temporaryPath, isDirectory: false)!) }
		}
	}

	/// Creates a sink that will write to `stdout`.
	public class func standardOutputSink() -> FileSink {
		return self(filePointer: stdout, closeWhenDone: false)
	}

	/// Creates a sink that will write to `stderr`.
	public class func standardErrorSink() -> FileSink {
		return self(filePointer: stderr, closeWhenDone: false)
	}

	/// Flushes the file, and closes it if appropriate.
	private func done() {
		if let filePointer = filePointer {
			fflush(filePointer)

			if closeWhenDone {
				fclose(filePointer)
			}
		}

		filePointer = nil
	}

	/// Writes the event data to the file, or the error if one occurred.
	public func put(value: T) {
		if let filePointer = filePointer {
			value.writeToFile(filePointer)

			// TODO:
			// Upon a terminating event, the file will be flushed, and closed if
			// appropriate.
		}
	}

	deinit {
		done()
	}
}
