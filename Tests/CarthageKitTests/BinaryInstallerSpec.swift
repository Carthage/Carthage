@testable import CarthageKit
import Foundation
import Quick
import Nimble
import ReactiveSwift
import XCDBLD
import Result

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

                installer.downloadBinaryFrameworkDefinition(binary: <#T##BinaryURL#>, binaryProjectsMap: <#T##[URL : BinaryProject]#>)

                let binary = BinaryURL(url: testDefinitionURL, resolvedDescription: testDefinitionURL.description)
                _ = downloader.binaryFrameworkDefinition(url: testDefinitionURL, useNetrc: false).first()

                expect(events) == [.downloadingBinaryFrameworkDefinition(.binary(binary), testDefinitionURL)]
            }
        }

    }
}

// MARK: - Mocks
// not used yet

private final class FileManagerMock: FileManaging {
    var fileExists: ((String) -> Bool)!
    func fileExists(atPath: String) -> Bool {
        return fileExists(atPath: atPath)
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

}
