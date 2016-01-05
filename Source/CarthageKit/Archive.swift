//
//  Archive.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-12-26.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import Result
import ReactiveCocoa
import ReactiveTask

/// Zips the given input items (recursively) into an archive that will be
/// located at the given URL.
public func zipIntoArchive(destinationArchiveURL: NSURL, _ inputPaths: [String]) -> SignalProducer<(), CarthageError> {
	precondition(destinationArchiveURL.fileURL)
	precondition(!inputPaths.isEmpty)

	let task = Task("/usr/bin/env", arguments: [ "zip", "-q", "-r", "--symlinks", destinationArchiveURL.path! ] + inputPaths)
	return launchTask(task)
		.mapError(CarthageError.TaskError)
		.then(.empty)
}

/// Unzips the archive at the given file URL, extracting into the given
/// directory URL (which must already exist).
public func unzipArchiveToDirectory(fileURL: NSURL, _ destinationDirectoryURL: NSURL) -> SignalProducer<(), CarthageError> {
	precondition(fileURL.fileURL)
	precondition(destinationDirectoryURL.fileURL)

	let task = Task("/usr/bin/env", arguments: [ "unzip", "-qq", "-d", destinationDirectoryURL.path!, fileURL.path! ])
	return launchTask(task)
		.mapError(CarthageError.TaskError)
		.then(.empty)
}

/// Unzips the archive at the given file URL into a temporary directory, then
/// sends the file URL to that directory.
public func unzipArchiveToTemporaryDirectory(fileURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	return SignalProducer.attempt {
			var temporaryDirectoryTemplate: [CChar] = (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent("carthage-archive.XXXXXX").nulTerminatedUTF8.map { CChar($0) }
			let result = temporaryDirectoryTemplate.withUnsafeMutableBufferPointer { (inout template: UnsafeMutableBufferPointer<CChar>) -> UnsafeMutablePointer<CChar> in
				return mkdtemp(template.baseAddress)
			}

			if result == nil {
				return .Failure(.TaskError(.POSIXError(errno)))
			}

			let temporaryPath = temporaryDirectoryTemplate.withUnsafeBufferPointer { (ptr: UnsafeBufferPointer<CChar>) -> String in
				return String.fromCString(ptr.baseAddress)!
			}

			return .Success(temporaryPath)
		}
		.map { NSURL.fileURLWithPath($0, isDirectory: true) }
		.flatMap(.Merge) { directoryURL in
			return unzipArchiveToDirectory(fileURL, directoryURL)
				.then(SignalProducer(value: directoryURL))
		}
}
