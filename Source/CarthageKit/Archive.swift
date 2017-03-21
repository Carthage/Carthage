//
//  Archive.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-12-26.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import Result
import ReactiveSwift
import ReactiveTask

/// Zips the given input paths (recursively) into an archive that will be
/// located at the given URL.
public func zip(paths: [String], into archiveURL: URL, workingDirectory: String) -> SignalProducer<(), CarthageError> {
	precondition(!paths.isEmpty)
	precondition(archiveURL.isFileURL)

	let task = Task("/usr/bin/env", arguments: [ "zip", "-q", "-r", "--symlinks", archiveURL.path ] + paths, workingDirectoryPath: workingDirectory)
	
	return task.launch()
		.mapError(CarthageError.taskError)
		.then(SignalProducer<(), CarthageError>.empty)
}

/// Unarchives the given file URL into a temporary directory, using its
/// extension to detect archive type, then sends the file URL to that directory.
public func unarchive(archive fileURL: URL) -> SignalProducer<URL, CarthageError> {
	if fileURL.pathExtension == "gz" {
		return untargz(archive: fileURL)
	} else {
		return unzip(archive: fileURL)
	}
}

/// Unzips the archive at the given file URL, extracting into the given
/// directory URL (which must already exist).
private func unzip(archive fileURL: URL, to destinationDirectoryURL: URL) -> SignalProducer<(), CarthageError> {
	precondition(fileURL.isFileURL)
	precondition(destinationDirectoryURL.isFileURL)

	let task = Task("/usr/bin/env", arguments: [ "unzip", "-qq", "-d", destinationDirectoryURL.path, fileURL.path ])
	return task.launch()
		.mapError(CarthageError.taskError)
		.then(SignalProducer<(), CarthageError>.empty)
}

/// Untars the gzipped archive at the given file URL, extracting into the given
/// directory URL (which must already exist).
private func untargz(archive fileURL: URL, to destinationDirectoryURL: URL) -> SignalProducer<(), CarthageError> {
	precondition(fileURL.isFileURL)
	precondition(destinationDirectoryURL.isFileURL)

	let task = Task("/usr/bin/env", arguments: [ "tar", "-xzf", fileURL.path, "-C", destinationDirectoryURL.path ])
	return task.launch()
		.mapError(CarthageError.taskError)
		.then(SignalProducer<(), CarthageError>.empty)
}

/// Unzips the archive at the given file URL into a temporary directory, then
/// sends the file URL to that directory.
private func unzip(archive fileURL: URL) -> SignalProducer<URL, CarthageError> {
	return createTemporaryDirectory()
		.flatMap(.merge) { directoryURL in
			return unzip(archive: fileURL, to: directoryURL)
				.then(SignalProducer<URL, CarthageError>(value: directoryURL))
		}
}

/// Untars the gzipped archive at the given file URL into a temporary directory, 
/// then sends the file URL to that directory.
private func untargz(archive fileURL: URL) -> SignalProducer<URL, CarthageError> {
	return createTemporaryDirectory()
		.flatMap(.merge) { directoryURL in
			return untargz(archive: fileURL, to: directoryURL)
				.then(SignalProducer<URL, CarthageError>(value: directoryURL))
		}
}

private func createTemporaryDirectory() -> SignalProducer<URL, CarthageError> {
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
}
