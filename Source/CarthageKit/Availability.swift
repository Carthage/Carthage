#if swift(>=3)
#else
	import Foundation
	import ReactiveCocoa

	// MARK: - Archive.swift

	@available(*, unavailable, renamed="zip(paths:into:workingDirectory:)")
	public func zipIntoArchive(destinationArchiveURL: NSURL, workingDirectory: String, inputPaths: [String]) -> SignalProducer<(), CarthageError> { fatalError() }

	@available(*, unavailable, renamed="unzip(archive:to:)")
	public func unzipArchiveToDirectory(fileURL: NSURL, _ destinationDirectoryURL: NSURL) -> SignalProducer<(), CarthageError> { fatalError() }

	@available(*, unavailable, renamed="unzip(archive:)")
	public func unzipArchiveToTemporaryDirectory(fileURL: NSURL) -> SignalProducer<NSURL, CarthageError> { fatalError() }
#endif
