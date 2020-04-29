import Foundation
import ReactiveSwift
import Tentacle
import Result
import XCDBLD
import ReactiveTask

protocol FileManaging {
    func removeItem(at url: URL) throws
}

extension FileManager: FileManaging {}

final class BinaryInstaller {
    var useNetrc: Bool = false

    private let directoryURL: URL
    private let _projectEventsObserver: Signal<ProjectEvent, NoError>.Observer

    private let fileManager: FileManaging

    init(directoryURL: URL, eventsObserver: Signal<ProjectEvent, NoError>.Observer,
         fileManager: FileManaging = FileManager.default) {
        self.directoryURL = directoryURL
        self._projectEventsObserver = eventsObserver
        self.fileManager = fileManager
    }

    func installBinaries(for dependency: Dependency, pinnedVersion: PinnedVersion, toolchain: String?) -> SignalProducer<Bool, CarthageError> {
        switch dependency {
        case let .gitHub(server, repository):
            let client = Client(server: server)
            return self.downloadMatchingBinaries(for: dependency, pinnedVersion: pinnedVersion, fromRepository: repository, client: client)
                .flatMapError { error -> SignalProducer<URL, CarthageError> in
                    if !client.isAuthenticated {
                        return SignalProducer(error: error)
                    }
                    return self.downloadMatchingBinaries(
                        for: dependency,
                        pinnedVersion: pinnedVersion,
                        fromRepository: repository,
                        client: Client(server: server, isAuthenticated: false)
                    )
            }
            .flatMap(.concat) { (zipFileUrl: URL) -> SignalProducer<URL, CarthageError> in
                return self.unarchiveAndCopyBinaryFrameworks(zipFile: zipFileUrl, projectName: dependency.name,
                                                             pinnedVersion: pinnedVersion, toolchain: toolchain)
            }
            .on(value: { (url: URL) in
                 try! FileManager.default.removeItem(at: url)
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

    func installBinariesForBinaryProject(
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
                return self.downloadBinary(dependency: Dependency.binary(binary), version: semanticVersion, url: frameworkURL)
            }
            .flatMap(.concat) { self.unarchiveAndCopyBinaryFrameworks(zipFile: $0, projectName: projectName, pinnedVersion: pinnedVersion, toolchain: toolchain) }
            .on(value: { (url) in
                try? self.fileManager.removeItem(at: url)
            }).map { _ in
                ()
            }
    }

    func downloadBinaryFrameworkDefinition(binary: BinaryURL, binaryProjectsMap: [URL: BinaryProject]) -> SignalProducer<BinaryProject, CarthageError> {
        return SignalProducer<[URL: BinaryProject], CarthageError>(value: binaryProjectsMap)
            .flatMap(.merge) { binaryProjectsByURL -> SignalProducer<BinaryProject, CarthageError> in
                if let binaryProject = binaryProjectsByURL[binary.url] {
                    return SignalProducer(value: binaryProject)
                } else {
                    self._projectEventsObserver.send(value: .downloadingBinaryFrameworkDefinition(.binary(binary), binary.url))

                    let request = self.buildURLRequest(for: binary.url, useNetrc: self.useNetrc)
                    return URLSession.shared.reactive.data(with: request)
                        .mapError { CarthageError.readFailed(binary.url, $0 as NSError) }
                        .attemptMap { data, _ in
                            return BinaryProject.from(jsonData: data).mapError { error in
                                return CarthageError.invalidBinaryJSON(binary.url, error)
                            }
                        }
                }
            }

    }

    /// Downloads the binary only framework file. Sends the URL to each downloaded zip, after it has been moved to a
    /// less temporary location.
    private func downloadBinary(dependency: Dependency, version: SemanticVersion, url: URL) -> SignalProducer<URL, CarthageError> {
        let fileName = url.lastPathComponent
        let fileURL = fileURLToCachedBinaryDependency(dependency, version, fileName)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            return SignalProducer(value: fileURL)
        } else {
            let request = self.buildURLRequest(for: url, useNetrc: self.useNetrc)
            return URLSession.shared.reactive.download(with: request)
                .on(started: {
                    self._projectEventsObserver.send(value: .downloadingBinaries(dependency, version.description))
                })
                .mapError { CarthageError.readFailed(url, $0 as NSError) }
                .flatMap(.concat) { downloadURL, _ in cacheDownloadedBinary(downloadURL, toURL: fileURL) }
        }
    }

    /// Builds URL request
    ///
    /// - Parameters:
    ///   - url: a url that identifies the location of a resource
    ///   - useNetrc: determines whether to use credentials from `~/.netrc` file
    /// - Returns: a URL request
    private func buildURLRequest(for url: URL, useNetrc: Bool) -> URLRequest {
        var request = URLRequest(url: url)
        guard useNetrc else { return request }

        // When downloading a binary, `carthage` will take into account the user's
        // `~/.netrc` file to determine authentication credentials
        switch Netrc.load() {
        case let .success(netrc):
            if let authorization = netrc.authorization(for: url) {
                request.addValue(authorization, forHTTPHeaderField: "Authorization")
            }
        case .failure(_): break // Do nothing
        }
        return request
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
                                return platformForFramework(url)
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
                        if frameworkDestinationURL.pathExtension != "xcframework" {
                            return self.copyDSYMToBuildFolderForFramework(frameworkDestinationURL, fromDirectoryURL: directoryURL)
                                .then(self.copyBCSymbolMapsToBuildFolderForFramework(frameworkDestinationURL, fromDirectoryURL: directoryURL))
                                .then(SignalProducer(value: frameworkDestinationURL))
                        }
                        else {
                            return SignalProducer(value: frameworkDestinationURL)
                        }
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
        return BCSymbolMapsForFramework(frameworkURL, inDirectoryURL: directoryURL)
            .copyFileURLsIntoDirectory(destinationDirectoryURL)
    }

    /// Constructs the file:// URL at which a given .framework
    /// will be found. Depends on the location of the current project.
    private func frameworkURLInCarthageBuildFolder(
        forPlatform platform: Platform,
        frameworkNameAndExtension: String
    ) -> Result<URL, CarthageError> {
        guard let lastComponent = URL(string: frameworkNameAndExtension)?.pathExtension,
            lastComponent == "framework" || lastComponent == "xcframework" else {
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

    /// Downloads any binaries and debug symbols that may be able to be used
    /// instead of a repository checkout.
    ///
    /// Sends the URL to each downloaded zip, after it has been moved to a
    /// less temporary location.
    private func downloadMatchingBinaries(
        for dependency: Dependency,
        pinnedVersion: PinnedVersion,
        fromRepository repository: Repository,
        client: Client
    ) -> SignalProducer<URL, CarthageError> {
        return client.execute(repository.release(forTag: pinnedVersion.commitish))
            .map { _, release in release }
            .filter { release in
                return !release.isDraft && !release.assets.isEmpty
            }
            .flatMapError { error -> SignalProducer<Release, CarthageError> in
                switch error {
                case .doesNotExist:
                    return .empty

                case let .apiError(_, _, error):
                    // Log the GitHub API request failure, not to error out,
                    // because that should not be fatal error.
                    self._projectEventsObserver.send(value: .skippedDownloadingBinaries(dependency, error.message))
                    return .empty

                default:
                    return SignalProducer(error: .gitHubAPIRequestFailed(error))
                }
            }
            .on(value: { release in
                self._projectEventsObserver.send(value: .downloadingBinaries(dependency, release.nameWithFallback))
            })
            .flatMap(.concat) { release -> SignalProducer<URL, CarthageError> in
                return SignalProducer<Release.Asset, CarthageError>(release.assets)
                    .filter { asset in
                        if asset.name.range(of: Constants.Project.binaryAssetPattern) == nil {
                            return false
                        }
                        return Constants.Project.binaryAssetContentTypes.contains(asset.contentType)
                    }
                    .flatMap(.concat) { asset -> SignalProducer<URL, CarthageError> in
                        let fileURL = fileURLToCachedBinary(dependency, release, asset)

                        if FileManager.default.fileExists(atPath: fileURL.path) {
                            return SignalProducer(value: fileURL)
                        } else {
                            return client.download(asset: asset)
                                .mapError(CarthageError.gitHubAPIRequestFailed)
                                .flatMap(.concat) { downloadURL in cacheDownloadedBinary(downloadURL, toURL: fileURL) }
                        }
                    }
            }
    }
}

/// Constructs a file URL to where the binary corresponding to the given
/// arguments should live.
private func fileURLToCachedBinary(_ dependency: Dependency, _ release: Release, _ asset: Release.Asset) -> URL {
    // ~/Library/Caches/org.carthage.CarthageKit/binaries/ReactiveCocoa/v2.3.1/1234-ReactiveCocoa.framework.zip
    return Constants.Dependency.assetsURL.appendingPathComponent("\(dependency.name)/\(release.tag)/\(asset.id)-\(asset.name)", isDirectory: false)
}

/// Constructs a file URL to where the binary only framework download should be cached
private func fileURLToCachedBinaryDependency(_ dependency: Dependency, _ semanticVersion: SemanticVersion, _ fileName: String) -> URL {
    // ~/Library/Caches/org.carthage.CarthageKit/binaries/MyBinaryProjectFramework/2.3.1/MyBinaryProject.framework.zip
    return Constants.Dependency.assetsURL.appendingPathComponent("\(dependency.name)/\(semanticVersion)/\(fileName)")
}

/// Caches the downloaded binary at the given URL, moving it to the other URL
/// given.
///
/// Sends the final file URL upon .success.
private func cacheDownloadedBinary(_ downloadURL: URL, toURL cachedURL: URL) -> SignalProducer<URL, CarthageError> {
    return SignalProducer(value: cachedURL)
        .attempt { fileURL in
            Result(at: fileURL.deletingLastPathComponent(), attempt: {
                try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
            })
        }
        .attempt { newDownloadURL in
            // Tries `rename()` system call at first.
            let result = downloadURL.withUnsafeFileSystemRepresentation { old in
                newDownloadURL.withUnsafeFileSystemRepresentation { new in
                    rename(old!, new!)
                }
            }
            if result == 0 {
                return .success(())
            }

            if errno != EXDEV {
                return .failure(.taskError(.posixError(errno)))
            }

            // If the “Cross-device link” error occurred, then falls back to
            // `FileManager.moveItem(at:to:)`.
            //
            // See https://github.com/Carthage/Carthage/issues/706 and
            // https://github.com/Carthage/Carthage/issues/711.
            return Result(at: newDownloadURL, attempt: {
                try FileManager.default.moveItem(at: downloadURL, to: $0)
            })
        }
}

/// Sends the URLs of the bcsymbolmap files that match the given framework and are
/// located somewhere within the given directory.
func BCSymbolMapsForFramework(_ frameworkURL: URL, inDirectoryURL directoryURL: URL) -> SignalProducer<URL, CarthageError> {
    return UUIDsForFramework(frameworkURL)
        .flatMap(.merge) { uuids -> SignalProducer<URL, CarthageError> in
            if uuids.isEmpty {
                return .empty
            }
            func filterUUIDs(_ signal: Signal<URL, CarthageError>) -> Signal<URL, CarthageError> {
                var remainingUUIDs = uuids
                let count = remainingUUIDs.count
                return signal
                    .filter { fileURL in
                        let basename = fileURL.deletingPathExtension().lastPathComponent
                        if let fileUUID = UUID(uuidString: basename) {
                            return remainingUUIDs.remove(fileUUID) != nil
                        } else {
                            return false
                        }
                    }
                    .take(first: count)
            }
            return BCSymbolMapsInDirectory(directoryURL)
                .lift(filterUUIDs)
        }
}

/// Sends the URL to each bcsymbolmap found in the given directory.
internal func BCSymbolMapsInDirectory(_ directoryURL: URL) -> SignalProducer<URL, CarthageError> {
    return filesInDirectory(directoryURL)
        .filter { url in url.pathExtension == "bcsymbolmap" }
}

/// Sends the platform specified in the given Info.plist.
func platformForFramework(_ frameworkURL: URL) -> SignalProducer<Platform, CarthageError> {
    return SignalProducer(value: frameworkURL)
        // Neither DTPlatformName nor CFBundleSupportedPlatforms can not be used
        // because Xcode 6 and below do not include either in macOS frameworks.
        .attemptMap { url -> Result<String, CarthageError> in
            let bundle = Bundle(url: url)

            func readFailed(_ message: String) -> CarthageError {
                let error = Result<(), NSError>.error(message)
                return .readFailed(frameworkURL, error)
            }

            func sdkNameFromExecutable() -> String? {
                guard let executableURL = bundle?.executableURL else {
                    return nil
                }

                let task = Task("/usr/bin/xcrun", arguments: ["otool", "-lv", executableURL.path])

                let sdkName: String? = task.launch(standardInput: nil)
                    .ignoreTaskData()
                    .map { String(data: $0, encoding: .utf8) ?? "" }
                    .filter { !$0.isEmpty }
                    .flatMap(.merge) { (output: String) -> SignalProducer<String, NoError> in
                        output.linesProducer
                    }
                    .filter { $0.contains("LC_VERSION") }
                    .take(last: 1)
                    .map { lcVersionLine -> String? in
                        let sdkString = lcVersionLine.split(separator: "_")
                            .last
                            .flatMap(String.init)
                            .flatMap { $0.lowercased() }

                        return sdkString
                    }
                    .skipNil()
                    .single()?
                    .value

                return sdkName
            }

            // Try to read what platfrom this binary is for. Attempt in order:
            // 1. Read `AvailableLibraries > SupportedPlatform` if .xcFramework bundle
            // 2. Read `DTSDKName` from Info.plist.
            //    Some users are reporting that static frameworks don't have this key in the .plist,
            //    so we fall back and check the binary of the executable itself.
            // 3. Read the LC_VERSION_<PLATFORM> from the framework's binary executable file
            if case bundle?.packageType = PackageType.xcFramework,
                let sdkNameFromSupportedPlatform = bundle?.infoDictionary.flatMap(XCFrameworkInfo.init)?
                    .availableLibraries
                    .first?
                    .supportedSDK.rawValue {
                return .success(sdkNameFromSupportedPlatform)
            } else if let sdkNameFromBundle = bundle?.object(forInfoDictionaryKey: "DTSDKName") as? String {
                return .success(sdkNameFromBundle)
            } else if let sdkNameFromExecutable = sdkNameFromExecutable() {
                return .success(sdkNameFromExecutable)
            } else {
                return .failure(readFailed("could not determine platform neither from DTSDKName key in plist nor from the framework's executable"))
            }
        }
        // Thus, the SDK name must be trimmed to match the platform name, e.g.
        // macosx10.10 -> macosx
        .map { sdkName in sdkName.trimmingCharacters(in: CharacterSet.letters.inverted) }
        .attemptMap { platform in SDK.from(string: platform).map { $0.platform } }
}
