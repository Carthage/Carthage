//
//  Archive.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-12-26.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import Result
#if swift(>=3)
import ReactiveSwift
#else
import ReactiveCocoa
#endif
import ReactiveTask

/// Zips the given input paths (recursively) into an archive that will be
/// located at the given URL.
public func zip(paths: [String], into archiveURL: URL, workingDirectory: String) -> SignalProducer<(), CarthageError> {
	precondition(!paths.isEmpty)
	precondition(archiveURL.isFileURL)

	let task = Task("/usr/bin/env", arguments: [ "zip", "-q", "-r", "--symlinks", archiveURL.carthage_path ] + paths, workingDirectoryPath: workingDirectory)
	
	return task.launch()
		.mapError(CarthageError.taskError)
		.then(SignalProducer<(), CarthageError>.empty)
}

/// Unzips the archive at the given file URL, extracting into the given
/// directory URL (which must already exist).
public func unzip(archive fileURL: URL, to destinationDirectoryURL: URL) -> SignalProducer<(), CarthageError> {
	precondition(fileURL.isFileURL)
	precondition(destinationDirectoryURL.isFileURL)

	let task = Task("/usr/bin/env", arguments: [ "unzip", "-qq", "-d", destinationDirectoryURL.carthage_path, fileURL.carthage_path ])
	return task.launch()
		.mapError(CarthageError.taskError)
		.then(SignalProducer<(), CarthageError>.empty)
}

/// Unzips the archive at the given file URL into a temporary directory, then
/// sends the file URL to that directory.
public func unzip(archive fileURL: URL) -> SignalProducer<URL, CarthageError> {
	return SignalProducer.attempt { () -> Result<String, CarthageError> in
			var temporaryDirectoryTemplate: ContiguousArray<CChar> = (NSTemporaryDirectory() as NSString).appendingPathComponent("carthage-archive.XXXXXX").utf8CString
			let result: UnsafeMutablePointer<Int8>? = temporaryDirectoryTemplate.withUnsafeMutableBufferPointer { (template: inout UnsafeMutableBufferPointer<CChar>) -> UnsafeMutablePointer<CChar> in
				return mkdtemp(template.baseAddress)
			}

			if result == nil {
				return .failure(.taskError(.posixError(errno)))
			}

			let temporaryPath = temporaryDirectoryTemplate.withUnsafeBufferPointer { (ptr: UnsafeBufferPointer<CChar>) -> String in
				return String(validatingUTF8: ptr.baseAddress!)!
			}

			return .success(temporaryPath)
		}
		.map { URL(fileURLWithPath: $0, isDirectory: true) }
		.flatMap(.merge) { directoryURL in
			return unzip(archive: fileURL, to: directoryURL)
				.then(SignalProducer<URL, CarthageError>(value: directoryURL))
		}
}
