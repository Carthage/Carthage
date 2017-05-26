import Foundation
import Nimble
import Quick

@testable import CarthageKit

class BinaryProjectSpec: QuickSpec {
	override func spec() {

		describe("from") {

			let testUrl = URL(string: "http://my.domain.com")!

			it("should parse") {
				let jsonData = (
					"{" +
					"\"1.0\": \"https://my.domain.com/release/1.0.0/framework.zip\"," +
					"\"1.0.1\": \"https://my.domain.com/release/1.0.1/framework.zip\"" +
					"}"
					).data(using: .utf8)!

				let actualBinaryProject = BinaryProject.from(jsonData: jsonData, url: testUrl).value

				let expectedBinaryProject = BinaryProject(versions: [
					PinnedVersion("1.0"): URL(string: "https://my.domain.com/release/1.0.0/framework.zip")!,
					PinnedVersion("1.0.1"): URL(string: "https://my.domain.com/release/1.0.1/framework.zip")!,
				])

				expect(actualBinaryProject).to(equal(expectedBinaryProject))
			}

			it("should fail if string is not JSON") {
				let jsonData = "definitely not JSON".data(using: .utf8)!

				let actualError = BinaryProject.from(jsonData: jsonData, url: testUrl).error

				switch actualError {
				case .some(.invalidJSON(_)): break
				default:
					fail("Expected invalidJSON error")
				}
			}

			it("should fail if string is not a dictionary of strings") {
				let jsonData = "[\"this\", \"is\", \"not\", \"a\", \"dictionary\"]".data(using: .utf8)!

				let actualError = BinaryProject.from(jsonData: jsonData, url: testUrl).error

				expect(actualError).to(equal(BinaryJSONError.invalidJSON(NSError(domain: CarthageKitBundleIdentifier,
				                                                                 code: 1,
				                                                                 userInfo: [NSLocalizedDescriptionKey: "Binary definition was not expected type [String: String]"]))))
			}

			it("should fail with an invalid semantic version") {
				let jsonData = "{ \"1.a\": \"https://my.domain.com/release/1.0.0/framework.zip\" }".data(using: .utf8)!

				let actualError = BinaryProject.from(jsonData: jsonData, url: testUrl).error

				expect(actualError).to(equal(BinaryJSONError.invalidVersion(ScannableError(message: "expected minor version number", currentLine: "1.a"))))
			}

			it("should fail with a non-parseable URL") {
				let jsonData = "{ \"1.0\": \"💩\" }".data(using: .utf8)!

				let actualError = BinaryProject.from(jsonData: jsonData, url: testUrl).error

				expect(actualError).to(equal(BinaryJSONError.invalidURL("💩")))
			}

			it("should fail with a non HTTPS url") {
				let jsonData = "{ \"1.0\": \"http://my.domain.com/framework.zip\" }".data(using: .utf8)!

				let actualError = BinaryProject.from(jsonData: jsonData, url: testUrl).error

				expect(actualError).to(equal(BinaryJSONError.nonHTTPSURL(URL(string: "http://my.domain.com/framework.zip")!)))
			}

		}

	}
}
