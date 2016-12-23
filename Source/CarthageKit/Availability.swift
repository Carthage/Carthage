import Foundation
import ReactiveCocoa
import Result

// MARK: - Archive.swift

@available(*, unavailable, renamed="zip(paths:into:workingDirectory:)")
public func zipIntoArchive(destinationArchiveURL: URL, workingDirectory: String, inputPaths: [String]) -> SignalProducer<(), CarthageError> { fatalError() }

@available(*, unavailable, renamed="unzip(archive:to:)")
public func unzipArchiveToDirectory(fileURL: URL, _ destinationDirectoryURL: URL) -> SignalProducer<(), CarthageError> { fatalError() }

@available(*, unavailable, renamed="unzip(archive:)")
public func unzipArchiveToTemporaryDirectory(fileURL: URL) -> SignalProducer<URL, CarthageError> { fatalError() }

// MARK: - Cartfile.swift

extension Cartfile {
	@available(*, unavailable, renamed="from(string:)")
	public static func fromString(string: String) -> Result<Cartfile, CarthageError> { fatalError() }
}

extension ResolvedCartfile {
	@available(*, unavailable, renamed="from(string:)")
	public static func fromString(string: String) -> Result<ResolvedCartfile, CarthageError> { fatalError() }
}

// MARK: - Git.swift

@available(*, unavailable, renamed="cloneRepository(_:_:isBare:)")
public func cloneRepository(cloneURL: GitURL, _ destinationURL: URL, bare: Bool = true) -> SignalProducer<String, CarthageError> { fatalError() }

// MARK: - Version.swift

extension VersionSpecifier {
	@available(*, unavailable, renamed="isSatisfied(by:)")
	public func satisfiedBy(version: PinnedVersion) -> Bool { fatalError() }
}
