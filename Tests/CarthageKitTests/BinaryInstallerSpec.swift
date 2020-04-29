@testable import CarthageKit
import Foundation
import Quick
import Nimble
import ReactiveSwift

final class BinaryInstallerSpec: QuickSpec {

    override func spec() {
        let directoryURL = URL.init(fileURLWithPath: "/tmp/Carthage")
        var installer: BinaryInstaller!
        var fileManager: FileManagerMock
        var frameworkInfoProvider: FrameworkInformationProviderMock!
        var eventsObserver: Signal<ProjectEvent, NoError>.Observer


        beforeEach {
            installer = BinaryInstaller(directoryURL: directoryURL, eventsObserver: <#T##Signal<ProjectEvent, NoError>.Observer#>, fileManager: <#T##FileManaging#>)
        }

    }
}

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
        <#code#>
    }

    func platformForFramework(_ frameworkURL: URL) -> SignalProducer<Platform, CarthageError> {
        <#code#>
    }

}
