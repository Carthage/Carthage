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
	@available(*, unavailable, renamed="url(in:)")
	public static func urlInDirectory(directoryURL: URL) -> URL { fatalError() }

	@available(*, unavailable, renamed="from(string:)")
	public static func fromString(string: String) -> Result<Cartfile, CarthageError> { fatalError() }

	@available(*, unavailable, renamed="from(file:)")
	public static func fromFile(cartfileURL: URL) -> Result<Cartfile, CarthageError> { fatalError() }
}

extension ResolvedCartfile {
	@available(*, unavailable, renamed="url(in:)")
	public static func urlInDirectory(directoryURL: URL) -> URL { fatalError() }

	@available(*, unavailable, renamed="from(string:)")
	public static func fromString(string: String) -> Result<ResolvedCartfile, CarthageError> { fatalError() }

	@available(*, unavailable, renamed="append(_:)")
	public mutating func appendCartfile(cartfile: Cartfile) { fatalError() }
}

@available(*, unavailable, renamed="duplicateProjectsIn(_:_:)")
public func duplicateProjectsInCartfiles(cartfile1: Cartfile, _ cartfile2: Cartfile) -> [ProjectIdentifier] { fatalError() }

// MARK: - Git.swift

@available(*, unavailable, renamed="cloneRepository(_:_:isBare:)")
public func cloneRepository(cloneURL: GitURL, _ destinationURL: URL, bare: Bool = true) -> SignalProducer<String, CarthageError> { fatalError() }

// MARK: - ProductType.swift

extension ProductType {
	@available(*, unavailable, renamed="from(string:)")
	public static func fromString(string: String) -> Result<ProductType, CarthageError> { fatalError() }
}

// MARK: - Version.swift

extension VersionSpecifier {
	@available(*, unavailable, renamed="isSatisfied(by:)")
	public func satisfiedBy(version: PinnedVersion) -> Bool { fatalError() }
}
