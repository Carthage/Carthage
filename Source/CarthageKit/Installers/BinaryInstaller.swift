import Foundation
import ReactiveSwift
import Tentacle
import Result
import XCDBLD
import ReactiveTask

protocol FileManaging {
    func removeItem(at url: URL) throws
    func fileExists(atPath: String) -> Bool
    func createDirectory(at: URL, withIntermediateDirectories: Bool, attributes: [FileAttributeKey : Any]?) throws
    func moveItem(at: URL, to: URL) throws
}

extension FileManager: FileManaging {}

protocol FrameworkInformationProviding {
    func BCSymbolMapsForFramework(_ frameworkURL: URL, inDirectoryURL directoryURL: URL) -> SignalProducer<URL, CarthageError>
    func platformForFramework(_ frameworkURL: URL) -> SignalProducer<Platform, CarthageError>
}

protocol BinaryFrameworkDownloading {
    var projectEvents: Signal<ProjectEvent, NoError> { get }
    func binaryFrameworkDefinition(url: URL, useNetrc: Bool) -> SignalProducer<BinaryProject, CarthageError>
    func downloadBinary(dependency: Dependency, version: SemanticVersion, url: URL, useNetrc: Bool) -> SignalProducer<URL, CarthageError>
    func downloadBinaryFromGitHub(for dependency: Dependency, pinnedVersion: PinnedVersion, server: Server, repository: Repository) -> SignalProducer<URL, CarthageError>
}

final class BinaryInstaller {
    var useNetrc: Bool = false

    private let directoryURL: URL
    let projectEvents: Signal<ProjectEvent, NoError>
    private let _projectEventsObserver: Signal<ProjectEvent, NoError>.Observer

    private let fileManager: FileManaging
    private let frameworkInformationProvider: FrameworkInformationProviding
    private let frameworkDownloader: BinaryFrameworkDownloading

    private typealias CachedBinaryProjects = [URL: BinaryProject]
    // Cache the binary project definitions in memory to avoid redownloading during carthage operation
    private var cachedBinaryProjects: CachedBinaryProjects = [:]
    private let cachedBinaryProjectsQueue = SerialProducerQueue(name: "org.carthage.Constants.Project.cachedBinaryProjectsQueue")

    init(directoryURL: URL,
         fileManager: FileManaging = FileManager.default,
         frameworkInformationProvider: FrameworkInformationProviding = FrameworkInformationProvider(),
         frameworkDownloader: BinaryFrameworkDownloading = BinaryFrameworkDownloader()) {

        let eventsPipe = Signal<ProjectEvent, NoError>.pipe()
        self._projectEventsObserver = eventsPipe.input
        self.projectEvents = eventsPipe.output.merge(with: frameworkDownloader.projectEvents)

        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.frameworkInformationProvider = frameworkInformationProvider
        self.frameworkDownloader = frameworkDownloader
    }

    func availableVersions(binary: BinaryURL) -> SignalProducer<PinnedVersion, CarthageError> {
        return downloadBinaryFrameworkDefinition(binary: binary, binaryProjectsMap: self.cachedBinaryProjects)
        .on(value: { binaryProject in
            self.cachedBinaryProjects[binary.url] = binaryProject
        }).flatMap(.concat) { binaryProject -> SignalProducer<PinnedVersion, CarthageError> in
            return SignalProducer(binaryProject.versions.keys)
        }
        .startOnQueue(self.cachedBinaryProjectsQueue)
    }

    func install(dependency: Dependency, version: PinnedVersion, toolchain: String?, useBinaries: Bool) -> SignalProducer<(Dependency, PinnedVersion), CarthageError> {
        switch dependency {
        case .git, .gitHub:
            guard useBinaries else {
                return .empty
            }
            return self.installBinaries(for: dependency, pinnedVersion: version, toolchain: toolchain)
                .filterMap { installed -> (Dependency, PinnedVersion)? in
                    return installed ? (dependency, version) : nil
            }
        case let .binary(binary):
            return self.installBinariesForBinaryProject(binary: binary,
                                                        pinnedVersion: version,
                                                        binaryProjectsMap: self.cachedBinaryProjects,
                                                        projectName: dependency.name,
                                                        toolchain: toolchain)
                .then(.init(value: (dependency, version)))
        }
    }

    private func installBinaries(for dependency: Dependency, pinnedVersion: PinnedVersion, toolchain: String?) -> SignalProducer<Bool, CarthageError> {
        switch dependency {
        case let .gitHub(server, repository):
            return self.frameworkDownloader.downloadBinaryFromGitHub(for: dependency, pinnedVersion: pinnedVersion, server: server, repository: repository)
            .flatMap(.concat) { (zipFileUrl: URL) -> SignalProducer<URL, CarthageError> in
                return self.unarchiveAndCopyBinaryFrameworks(zipFile: zipFileUrl, projectName: dependency.name,
                                                             pinnedVersion: pinnedVersion, toolchain: toolchain)
            }
            .on(value: { (url: URL) in
                try! self.fileManager.removeItem(at: url)
            })
            .map { _ in true }
            .flatMapError { error -> SignalProducer<Bool, CarthageError> in
                self._projectEventsObserver.send(value: .skippedInstallingBinaries(dependency: dependency, error: error))
                return SignalProducer(value: false)
            }
            .concat(value: false)
            .take(first: 1)

        case .git, .binary:
            return SignalProducer(value: false)
        }
    }

    private func installBinariesForBinaryProject(
        binary: BinaryURL,
        pinnedVersion: PinnedVersion,
        binaryProjectsMap: [URL: BinaryProject],
        projectName: String,
        toolchain: String?
    ) -> SignalProducer<(), CarthageError> {
        return SignalProducer<SemanticVersion, ScannableError>(result: SemanticVersion.from(pinnedVersion))
            .mapError { CarthageError(scannableError: $0) }
            .combineLatest(with: self.downloadBinaryFrameworkDefinition(binary: binary, binaryProjectsMap: binaryProjectsMap))
            .attemptMap { semanticVersion, binaryProject -> Result<(SemanticVersion, URL), CarthageError> in
                guard let frameworkURL = binaryProject.versions[pinnedVersion] else {
                    return .failure(CarthageError.requiredVersionNotFound(Dependency.binary(binary), VersionSpecifier.exactly(semanticVersion)))
                }

                return .success((semanticVersion, frameworkURL))
            }
            .flatMap(.concat) { semanticVersion, frameworkURL in
                return self.frameworkDownloader.downloadBinary(dependency: Dependency.binary(binary), version: semanticVersion,
                                                               url: frameworkURL, useNetrc: self.useNetrc)
            }
            .flatMap(.concat) { self.unarchiveAndCopyBinaryFrameworks(zipFile: $0, projectName: projectName, pinnedVersion: pinnedVersion, toolchain: toolchain) }
            .on(value: { (url) in
                try? self.fileManager.removeItem(at: url)
            }).map { _ in
                ()
            }
    }

    private func downloadBinaryFrameworkDefinition(binary: BinaryURL, binaryProjectsMap: [URL: BinaryProject]) -> SignalProducer<BinaryProject, CarthageError> {
        return SignalProducer<[URL: BinaryProject], CarthageError>(value: binaryProjectsMap)
            .flatMap(.merge) { binaryProjectsByURL -> SignalProducer<BinaryProject, CarthageError> in
                if let binaryProject = binaryProjectsByURL[binary.url] {
                    return SignalProducer(value: binaryProject)
                } else {
                    self._projectEventsObserver.send(value: .downloadingBinaryFrameworkDefinition(.binary(binary), binary.url))
                    return self.frameworkDownloader.binaryFrameworkDefinition(url: binary.url, useNetrc: self.useNetrc)
                }
            }
    }

    /// Unzips the file at the given URL and copies the frameworks, DSYM and
    /// bcsymbolmap files into the corresponding folders for the project. This
    /// step will also check framework compatibility and create a version file
    /// for the given frameworks.
    ///
    /// Sends the temporary URL of the unzipped directory
    private func unarchiveAndCopyBinaryFrameworks(
        zipFile: URL,
        projectName: String,
        pinnedVersion: PinnedVersion,
        toolchain: String?
    ) -> SignalProducer<URL, CarthageError> {

        // Helper type
        typealias SourceURLAndDestinationURL = (frameworkSourceURL: URL, frameworkDestinationURL: URL)

        // Returns the unique pairs in the input array
        // or the duplicate keys by .frameworkDestinationURL
        func uniqueSourceDestinationPairs(
            _ sourceURLAndDestinationURLpairs: [SourceURLAndDestinationURL]
            ) -> Result<[SourceURLAndDestinationURL], CarthageError> {
            let destinationMap = sourceURLAndDestinationURLpairs
                .reduce(into: [URL: [URL]]()) { result, pair in
                    result[pair.frameworkDestinationURL] =
                        (result[pair.frameworkDestinationURL] ?? []) + [pair.frameworkSourceURL]
            }

            let dupes = destinationMap.filter { $0.value.count > 1 }
            guard dupes.count == 0 else {
                return .failure(CarthageError
                    .duplicatesInArchive(duplicates: CarthageError
                        .DuplicatesInArchive(dictionary: dupes)))
            }

            let uniquePairs = destinationMap
                .filter { $0.value.count == 1}
                .map { SourceURLAndDestinationURL(frameworkSourceURL: $0.value.first!,
                                                  frameworkDestinationURL: $0.key)}
            return .success(uniquePairs)
        }

        return SignalProducer<URL, CarthageError>(value: zipFile)
            .flatMap(.concat, unarchive(archive:))
            .flatMap(.concat) { directoryURL -> SignalProducer<URL, CarthageError> in
                // For all frameworks in the directory where the archive has been expanded
                let existingFrameworks = frameworksInDirectory(directoryURL).collect()
                    // Check if multiple frameworks resolve to the same unique destination URL in the Carthage/Build/ folder.
                    // This is needed because frameworks might overwrite each others.
                let uniqueFrameworks = existingFrameworks.flatMap(.merge) { frameworksUrls -> SignalProducer<SourceURLAndDestinationURL, CarthageError> in
                        return SignalProducer<URL, CarthageError>(frameworksUrls)
                            .flatMap(.merge) { url -> SignalProducer<URL, CarthageError> in
                                return self.frameworkInformationProvider.platformForFramework(url)
                                    .attemptMap { self.frameworkURLInCarthageBuildFolder(forPlatform: $0,
                                                                                 frameworkNameAndExtension: url.lastPathComponent) }
                            }
                            .collect()
                            .flatMap(.merge) { destinationUrls -> SignalProducer<SourceURLAndDestinationURL, CarthageError> in
                                let frameworkUrlAndDestinationUrlPairs = zip(frameworksUrls.map{$0.standardizedFileURL},
                                                                             destinationUrls.map{$0.standardizedFileURL})
                                    .map { SourceURLAndDestinationURL(frameworkSourceURL:$0,
                                                                      frameworkDestinationURL: $1) }

                                return uniqueSourceDestinationPairs(frameworkUrlAndDestinationUrlPairs)
                                    .producer
                                    .flatMap(.merge) { SignalProducer($0) }
                            }
                    }
                    // Check if the framework are compatible with the current Swift version
                let compatibleFrameworks = uniqueFrameworks.flatMap(.merge) { pair -> SignalProducer<SourceURLAndDestinationURL, CarthageError> in
                        return checkFrameworkCompatibility(pair.frameworkSourceURL, usingToolchain: toolchain)
                            .mapError { error in CarthageError.internalError(description: error.description) }
                            .reduce(into: pair) { (_, _) = ($0.1, $1) }
                    }
                    // If the framework is compatible copy it over to the destination folder in Carthage/Build
                let copiedFrameworks = compatibleFrameworks.flatMap(.merge) { pair -> SignalProducer<URL, CarthageError> in
                        return SignalProducer<URL, CarthageError>(value: pair.frameworkSourceURL)
                            .copyFileURLsIntoDirectory(pair.frameworkDestinationURL.deletingLastPathComponent())
                            .then(SignalProducer<URL, CarthageError>(value: pair.frameworkDestinationURL))
                    }
                    // Copy .dSYM & .bcsymbolmap too
                let copiedDsyms = copiedFrameworks.flatMap(.merge) { frameworkDestinationURL -> SignalProducer<URL, CarthageError> in
                    return self.copyDSYMToBuildFolderForFramework(frameworkDestinationURL, fromDirectoryURL: directoryURL)
                        .then(self.copyBCSymbolMapsToBuildFolderForFramework(frameworkDestinationURL, fromDirectoryURL: directoryURL))
                        .then(SignalProducer(value: frameworkDestinationURL))
                }
               return copiedDsyms.collect()
                    // Write the .version file
                    .flatMap(.concat) { frameworkURLs -> SignalProducer<(), CarthageError> in
                        return self.createVersionFilesForFrameworks(
                            frameworkURLs,
                            fromDirectoryURL: directoryURL,
                            projectName: projectName,
                            commitish: pinnedVersion.commitish
                        )
                    }
                    .then(SignalProducer<URL, CarthageError>(value: directoryURL))
            }
    }

    /// Creates a .version file for all of the provided frameworks.
    public func createVersionFilesForFrameworks(
        _ frameworkURLs: [URL],
        fromDirectoryURL directoryURL: URL,
        projectName: String,
        commitish: String
    ) -> SignalProducer<(), CarthageError> {
        return createVersionFileForCommitish(commitish, dependencyName: projectName, buildProducts: frameworkURLs, rootDirectoryURL: directoryURL)
    }

    /// Copies the DSYM matching the given framework and contained within the
    /// given directory URL to the directory that the framework resides within.
    ///
    /// If no dSYM is found for the given framework, completes with no values.
    ///
    /// Sends the URL of the dSYM after copying.
    public func copyDSYMToBuildFolderForFramework(_ frameworkURL: URL, fromDirectoryURL directoryURL: URL) -> SignalProducer<URL, CarthageError> {
        let destinationDirectoryURL = frameworkURL.deletingLastPathComponent()
        return dSYMForFramework(frameworkURL, inDirectoryURL: directoryURL)
            .copyFileURLsIntoDirectory(destinationDirectoryURL)
    }

    /// Copies any *.bcsymbolmap files matching the given framework and contained
    /// within the given directory URL to the directory that the framework
    /// resides within.
    ///
    /// If no bcsymbolmap files are found for the given framework, completes with
    /// no values.
    ///
    /// Sends the URLs of the bcsymbolmap files after copying.
    public func copyBCSymbolMapsToBuildFolderForFramework(_ frameworkURL: URL, fromDirectoryURL directoryURL: URL) -> SignalProducer<URL, CarthageError> {
        let destinationDirectoryURL = frameworkURL.deletingLastPathComponent()
        return self.frameworkInformationProvider.BCSymbolMapsForFramework(frameworkURL, inDirectoryURL: directoryURL)
            .copyFileURLsIntoDirectory(destinationDirectoryURL)
    }

    /// Constructs the file:// URL at which a given .framework
    /// will be found. Depends on the location of the current project.
    private func frameworkURLInCarthageBuildFolder(
        forPlatform platform: Platform,
        frameworkNameAndExtension: String
    ) -> Result<URL, CarthageError> {
        guard let lastComponent = URL(string: frameworkNameAndExtension)?.pathExtension,
            lastComponent == "framework" else {
                return .failure(.internalError(description: "\(frameworkNameAndExtension) is not a valid framework identifier"))
        }

        guard let destinationURLInWorkingDir = platform
            .relativeURL?
            .appendingPathComponent(frameworkNameAndExtension, isDirectory: true) else {
                return .failure(.internalError(description: "failed to construct framework destination url from \(platform) and \(frameworkNameAndExtension)"))
        }

        return .success(self
            .directoryURL
            .appendingPathComponent(destinationURLInWorkingDir.path, isDirectory: true)
            .standardizedFileURL)
    }
}
