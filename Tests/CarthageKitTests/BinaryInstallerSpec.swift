@testable import CarthageKit
import Foundation
import Quick
import Nimble
import ReactiveSwift
import XCDBLD
import Result
import Tentacle

final class BinaryInstallerSpec: QuickSpec {

    override func spec() {
        let directoryURL = URL.init(fileURLWithPath: "/tmp/Carthage")
        var installer: BinaryInstaller!
        var fileManager: FileManagerMock!
        var frameworkInfoProvider: FrameworkInformationProviderMock!
        var binaryFrameworkDownloader: BinaryFrameworkDownloading!

        beforeEach {
            fileManager = FileManagerMock()
            frameworkInfoProvider = FrameworkInformationProviderMock()
            binaryFrameworkDownloader = BinaryFrameworkDownloaderMock()

            installer = BinaryInstaller(directoryURL: directoryURL, fileManager: fileManager,
                                        frameworkInformationProvider: frameworkInfoProvider, frameworkDownloader: binaryFrameworkDownloader)
        }

        describe("") {
            it("should broadcast downloading framework definition event") {
                var events = [ProjectEvent]()
                installer.projectEvents.observeValues { events.append($0) }

                let testDefinitionURL = URL(string: "https://test.url")!
                let binary = BinaryURL(url: testDefinitionURL, resolvedDescription: testDefinitionURL.description)
                _ = installer.availableVersions(binary: binary).first()

                expect(events) == [.downloadingBinaryFrameworkDefinition(.binary(binary), testDefinitionURL)]
            }
        }

    }
}

// MARK: - Mocks
// not used yet

private final class FileManagerMock: FileManaging {
    var fileExistsClosure: ((String) -> Bool)!
    func fileExists(atPath: String) -> Bool {
        return fileExistsClosure(atPath)
    }

    func createDirectory(at: URL, withIntermediateDirectories: Bool, attributes: [FileAttributeKey : Any]?) throws {}

    func moveItem(at: URL, to: URL) throws {}

    func removeItem(at url: URL) throws {}
}

private final class FrameworkInformationProviderMock: FrameworkInformationProviding {
    func BCSymbolMapsForFramework(_ frameworkURL: URL, inDirectoryURL directoryURL: URL) -> SignalProducer<URL, CarthageError> {
        return .empty
    }

    func platformForFramework(_ frameworkURL: URL) -> SignalProducer<Platform, CarthageError> {
        return .empty
    }
}

private final class BinaryFrameworkDownloaderMock: BinaryFrameworkDownloading {
    var projectEvents: Signal<ProjectEvent, NoError> {
        return .empty
    }

    func binaryFrameworkDefinition(url: URL, useNetrc: Bool) -> SignalProducer<BinaryProject, CarthageError> {
        return .empty
    }

    func downloadBinary(dependency: Dependency, version: SemanticVersion, url: URL, useNetrc: Bool) -> SignalProducer<URL, CarthageError> {
        return .empty
    }

    func downloadBinaryFromGitHub(for dependency: Dependency, pinnedVersion: PinnedVersion, server: Server, repository: Repository) -> SignalProducer<URL, CarthageError> {
        return .empty
    }
}
