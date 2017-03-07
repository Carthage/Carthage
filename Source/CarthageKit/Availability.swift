import Foundation
import ReactiveSwift
import Result
import XCDBLD

// MARK: - Archive.swift

@available(*, unavailable, renamed: "zip(paths:into:workingDirectory:)")
public func zipIntoArchive(_ destinationArchiveURL: URL, workingDirectory: String, inputPaths: [String]) -> SignalProducer<(), CarthageError> { fatalError() }

@available(*, unavailable, renamed: "unzip(archive:to:)")
public func unzipArchiveToDirectory(_ fileURL: URL, _ destinationDirectoryURL: URL) -> SignalProducer<(), CarthageError> { fatalError() }

@available(*, unavailable, renamed: "unzip(archive:)")
public func unzipArchiveToTemporaryDirectory(_ fileURL: URL) -> SignalProducer<URL, CarthageError> { fatalError() }

// MARK: - Cartfile.swift

extension Cartfile {
	@available(*, unavailable, renamed: "url(in:)")
	public static func urlInDirectory(_ directoryURL: URL) -> URL { fatalError() }

	@available(*, unavailable, renamed: "from(string:)")
	public static func fromString(_ string: String) -> Result<Cartfile, CarthageError> { fatalError() }

	@available(*, unavailable, renamed: "from(file:)")
	public static func fromFile(_ cartfileURL: URL) -> Result<Cartfile, CarthageError> { fatalError() }
}

extension ResolvedCartfile {
	@available(*, unavailable, renamed: "url(in:)")
	public static func urlInDirectory(_ directoryURL: URL) -> URL { fatalError() }

	@available(*, unavailable, renamed: "from(string:)")
	public static func fromString(_ string: String) -> Result<ResolvedCartfile, CarthageError> { fatalError() }

	@available(*, unavailable, renamed: "append(_:)")
	public mutating func appendCartfile(_ cartfile: Cartfile) { fatalError() }
}

@available(*, unavailable, renamed: "duplicateProjectsIn(_:_:)")
public func duplicateProjectsInCartfiles(_ cartfile1: Cartfile, _ cartfile2: Cartfile) -> [ProjectIdentifier] { fatalError() }

// MARK: - Git.swift

@available(*, unavailable, renamed: "cloneRepository(_:_:isBare:)")
public func cloneRepository(_ cloneURL: GitURL, _ destinationURL: URL, bare: Bool = true) -> SignalProducer<String, CarthageError> { fatalError() }

@available(*, unavailable)
public func moveItemInPossibleRepository(_ repositoryFileURL: URL, fromPath: String, toPath: String) -> SignalProducer<URL, CarthageError> { fatalError() }

// MARK: - MachOType.swift

extension MachOType {
	@available(*, unavailable, renamed: "from(string:)")
	public static func fromString(_ string: String) -> Result<MachOType, CarthageError> { fatalError() }
}

// MARK: - ProductType.swift

extension ProductType {
	@available(*, unavailable, renamed: "from(string:)")
	public static func fromString(_ string: String) -> Result<ProductType, CarthageError> { fatalError() }
}

// MARK: - SDK.swift

extension SDK {
	@available(*, unavailable, renamed: "from(string:)")
	public static func fromString(_ string: String) -> Result<SDK, CarthageError> { fatalError() }
}

// MARK: - Version.swift

extension SemanticVersion {
	@available(*, unavailable, renamed: "from(_:)")
	public static func fromPinnedVersion(_ pinnedVersion: PinnedVersion) -> Result<SemanticVersion, CarthageError> { fatalError() }
}

extension VersionSpecifier {
	@available(*, unavailable, renamed: "isSatisfied(by:)")
	public func satisfiedBy(_ version: PinnedVersion) -> Bool { fatalError() }
}

// MARK: - Xcode.swift

@available(*, unavailable, renamed: "ProjectLocator.locate(in:)")
public func locateProjectsInDirectory(_ directoryURL: URL) -> SignalProducer<ProjectLocator, CarthageError> { fatalError() }

@available(*, unavailable, renamed: "ProjectLocator.schemes(self:)")
public func schemesInProject(_ project: ProjectLocator) -> SignalProducer<String, CarthageError> { fatalError() }
