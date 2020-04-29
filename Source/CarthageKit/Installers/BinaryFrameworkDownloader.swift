//
//  BinaryFrameworkDownloader.swift
//  CarthageKit
//
//  Created by Laskowski, Michal on 22/04/2020.
//

import Foundation
import ReactiveSwift
import Result
import Tentacle

final class BinaryFrameworkDownloader: BinaryFrameworkDownloading {

    let projectEvents: Signal<ProjectEvent, NoError>
    private let _projectEventsObserver: Signal<ProjectEvent, NoError>.Observer
    private let fileManager: FileManaging

    init(fileManager: FileManaging = FileManager.default) {
        let pipe = Signal<ProjectEvent, NoError>.pipe()
        self.projectEvents = pipe.output
        self._projectEventsObserver = pipe.input
        self.fileManager = fileManager
    }

    func binaryFrameworkDefinition(url: URL, useNetrc: Bool) -> SignalProducer<BinaryProject, CarthageError> {
        let request = self.buildURLRequest(for: url, useNetrc: useNetrc)
        return URLSession.shared.reactive.data(with: request)
            .mapError { CarthageError.readFailed(url, $0 as NSError) }
            .attemptMap { data, _ in
                return BinaryProject.from(jsonData: data).mapError { error in
                    return CarthageError.invalidBinaryJSON(url, error)
                }
        }
    }

    /// Downloads the binary only framework file. Sends the URL to each downloaded zip, after it has been moved to a
    /// less temporary location.
    func downloadBinary(dependency: Dependency, version: SemanticVersion, url: URL, useNetrc: Bool) -> SignalProducer<URL, CarthageError> {
        let fileName = url.lastPathComponent
        let fileURL = fileURLToCachedBinaryDependency(dependency, version, fileName)

        if fileManager.fileExists(atPath: fileURL.path) {
            return SignalProducer(value: fileURL)
        } else {
            let request = self.buildURLRequest(for: url, useNetrc: useNetrc)
            return URLSession.shared.reactive.download(with: request)
                .on(started: {
                    self._projectEventsObserver.send(value: .downloadingBinaries(dependency, version.description))
                })
                .mapError { CarthageError.readFailed(url, $0 as NSError) }
                .flatMap(.concat) { downloadURL, _ in self.cacheDownloadedBinary(downloadURL, toURL: fileURL) }
        }
    }

    func downloadBinaryFromGitHub(for dependency: Dependency, pinnedVersion: PinnedVersion, server: Server, repository: Repository) -> SignalProducer<URL, CarthageError> {
        let client = Client(server: server)
        return self.downloadMatchingBinaries(for: dependency, pinnedVersion: pinnedVersion,
                                                                 fromRepository: repository, client: client)
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

                        if self.fileManager.fileExists(atPath: fileURL.path) {
                            return SignalProducer(value: fileURL)
                        } else {
                            return client.download(asset: asset)
                                .mapError(CarthageError.gitHubAPIRequestFailed)
                                .flatMap(.concat) { downloadURL in self.cacheDownloadedBinary(downloadURL, toURL: fileURL) }
                        }
                    }
            }
    }

    /// Caches the downloaded binary at the given URL, moving it to the other URL
    /// given.
    ///
    /// Sends the final file URL upon .success.
    private func cacheDownloadedBinary(_ downloadURL: URL, toURL cachedURL: URL) -> SignalProducer<URL, CarthageError> {
        return SignalProducer(value: cachedURL)
            .attempt { fileURL in
                Result(at: fileURL.deletingLastPathComponent(), attempt: {
                    try self.fileManager.createDirectory(at: $0, withIntermediateDirectories: true, attributes: nil)
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
                    try self.fileManager.moveItem(at: downloadURL, to: $0)
                })
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
