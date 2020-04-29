@testable import CarthageKit
import Foundation
import Quick
import Nimble

final class BinaryFrameworkDownloaderSpec: QuickSpec {
    override func spec() {
        describe("downloadBinaryFrameworkDefinition") {
            var downloader: BinaryFrameworkDownloader!
            let testDefinitionURL = Bundle(for: type(of: self)).url(forResource: "BinaryOnly/successful", withExtension: "json")!

            beforeEach {
                downloader = BinaryFrameworkDownloader()
            }

            it("should return definition") {
                let actualDefinition = downloader.binaryFrameworkDefinition(url: testDefinitionURL, useNetrc: false).first()?.value

                let expectedBinaryProject = BinaryProject(versions: [
                    PinnedVersion("1.0"): URL(string: "https://my.domain.com/release/1.0.0/framework.zip")!,
                    PinnedVersion("1.0.1"): URL(string: "https://my.domain.com/release/1.0.1/framework.zip")!,
                ])
                expect(actualDefinition) == expectedBinaryProject
            }

            it("should return read failed if unable to download") {
                let url = URL(string: "file:///thisfiledoesnotexist.json")!
                let actualError = downloader.binaryFrameworkDefinition(url: url, useNetrc: false).first()?.error

                switch actualError {
                case .some(.readFailed):
                    break

                default:
                    fail("expected read failed error")
                }
            }

            it("should return an invalid binary JSON error if unable to parse file") {
                let invalidDependencyURL = Bundle(for: type(of: self)).url(forResource: "BinaryOnly/invalid", withExtension: "json")!
                let actualError = downloader.binaryFrameworkDefinition(url: invalidDependencyURL, useNetrc: false).first()?.error

                switch actualError {
                case .some(CarthageError.invalidBinaryJSON(invalidDependencyURL, BinaryJSONError.invalidJSON)):
                    break

                default:
                    fail("expected invalid binary JSON error")
                }
            }
        }
    }
}
