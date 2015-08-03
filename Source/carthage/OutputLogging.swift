//
//  OutputLogging.swift
//  Carthage
//
//  Created by Dov Frankel on 8/3/15.
//  Copyright (c) 2015 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import ReactiveCocoa

/**
Opens a file handle for logging, returning the handle and the URL to any
temporary file on disk.

:param: verbose  If true, log to standard output. Otherwise, capture output in a log file
:param: toolName The name of the tool it's logging output for (e.g. "xcodebuild", "git")

:returns: Returns a tuple of the file handle, and the URL of the temp file (or nil, if writing to stdout)
*/
public func openLoggingHandle(verbose: Bool, toolName: String) -> SignalProducer<(NSFileHandle, NSURL?), CarthageError> {
	if verbose {
		let out: (NSFileHandle, NSURL?) = (NSFileHandle.fileHandleWithStandardOutput(), nil)
		return SignalProducer(value: out)
	} else {
		return openTemporaryFile(toolName)
			|> map { handle, URL in (handle, .Some(URL)) }
			|> mapError { error in
				let temporaryDirectoryURL = NSURL.fileURLWithPath(NSTemporaryDirectory(), isDirectory: true)!
				return .WriteFailed(temporaryDirectoryURL, error)
		}
	}
}

/**
Opens a temporary file on disk, returning a handle and the URL to the file.

:param: toolName The name of the tool it's logging output for (e.g. "xcodebuild", "git")

:returns: Returns a tuple of the file handle and URL to the temporary file
*/
public func openTemporaryFile(toolName: String) -> SignalProducer<(NSFileHandle, NSURL), NSError> {
	return SignalProducer.try {
		var temporaryDirectoryTemplate: ContiguousArray<CChar> = NSTemporaryDirectory().stringByAppendingPathComponent("carthage-\(toolName).XXXXXX.log").nulTerminatedUTF8.map { CChar($0) }
		let logFD = temporaryDirectoryTemplate.withUnsafeMutableBufferPointer { (inout template: UnsafeMutableBufferPointer<CChar>) -> Int32 in
			return mkstemps(template.baseAddress, 4)
		}
		
		if logFD < 0 {
			return .failure(NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil))
		}
		
		let temporaryPath = temporaryDirectoryTemplate.withUnsafeBufferPointer { (ptr: UnsafeBufferPointer<CChar>) -> String in
			return String.fromCString(ptr.baseAddress)!
		}
		
		let handle = NSFileHandle(fileDescriptor: logFD, closeOnDealloc: true)
		let fileURL = NSURL.fileURLWithPath(temporaryPath, isDirectory: false)!
		return .success((handle, fileURL))
	}
}