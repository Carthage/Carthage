import Foundation
import Nimble
import Quick

@testable import CarthageKit

class BinaryProjectSpec: QuickSpec {
	override func spec() {
		describe("from") {
			it("should parse") {
				let jsonData = (
					"{" +
						"\"1.0\": \"https://my.domain.com/release/1.0.0/framework.zip\"," +
						"\"1.0.1\": \"https://my.domain.com/release/1.0.1/framework.zip?alt=https://my.domain.com/release/1.0.1/xcframework.zip&alt=https://my.domain.com/some/other/alternate.zip\"," +
						"\"1.0.2\": \"https://my.domain.com/release/1.0.2/framework.zip?alt=https%3A%2F%2Fmy.domain.com%2Frelease%2F1.0.2%2Fxcframework.zip\"," +
						"\"1.0.3\": \"https://my.domain.com/release/1.0.3/framework.zip?alt=media\"," +
						"\"1.0.4\": \"https://my.domain.com/release/1.0.4/framework.zip?alt=media&alt=https://my.domain.com/some/other/alternate.zip\"," +
						"\"1.0.5\": \"https://my.domain.com/release/1.0.5/framework.zip?alt=media&alt=https://my.domain.com/some/other/alternate.zip&carthage-alt=https://my.domain.com/2nd/other/alternate.zip\"" +
						"}"
				).data(using: .utf8)!

				let actualBinaryProject = BinaryProject.from(jsonData: jsonData).value

				let expectedBinaryProject = BinaryProject(versions: [
					PinnedVersion("1.0"): [URL(string: "https://my.domain.com/release/1.0.0/framework.zip")!],
					PinnedVersion("1.0.1"): [
						URL(string: "https://my.domain.com/release/1.0.1/framework.zip")!,
						URL(string: "https://my.domain.com/release/1.0.1/xcframework.zip")!,
						URL(string: "https://my.domain.com/some/other/alternate.zip")!,
					],
					PinnedVersion("1.0.2"): [
						URL(string: "https://my.domain.com/release/1.0.2/framework.zip")!,
						URL(string: "https://my.domain.com/release/1.0.2/xcframework.zip")!
					],
					PinnedVersion("1.0.3"): [
						URL(string: "https://my.domain.com/release/1.0.3/framework.zip?alt=media")!
					],
					PinnedVersion("1.0.4"): [
						URL(string: "https://my.domain.com/release/1.0.4/framework.zip?alt=media")!,
						URL(string: "https://my.domain.com/some/other/alternate.zip")!,
					],
					PinnedVersion("1.0.5"): [
						URL(string: "https://my.domain.com/release/1.0.5/framework.zip?alt=media")!,
						URL(string: "https://my.domain.com/some/other/alternate.zip")!,
						URL(string: "https://my.domain.com/2nd/other/alternate.zip")!
					]
				])

				expect(actualBinaryProject) == expectedBinaryProject
			}

			it("should fail if string is not JSON") {
				let jsonData = "definitely not JSON".data(using: .utf8)!

				let actualError = BinaryProject.from(jsonData: jsonData).error

				switch actualError {
				case .some(.invalidJSON):
					break

				default:
					fail("Expected invalidJSON error")
				}
			}

			it("should fail if string is not a dictionary of strings") {
				let jsonData = "[\"this\", \"is\", \"not\", \"a\", \"dictionary\"]".data(using: .utf8)!

				let actualError = BinaryProject.from(jsonData: jsonData).error

				if case let .invalidJSON(underlyingError)? = actualError {
					expect(underlyingError is DecodingError) == true
				} else {
					fail()
				}
			}

			it("should fail with an invalid semantic version") {
				let jsonData = "{ \"1.a\": \"https://my.domain.com/release/1.0.0/framework.zip\" }".data(using: .utf8)!

				let actualError = BinaryProject.from(jsonData: jsonData).error

				expect(actualError) == .invalidVersion(ScannableError(message: "expected minor version number", currentLine: "1.a"))
			}

			it("should fail with a non-parseable URL") {
				let jsonData = "{ \"1.0\": \"💩\" }".data(using: .utf8)!

				let actualError = BinaryProject.from(jsonData: jsonData).error

				expect(actualError) == .invalidURL("💩")
			}

			it("should fail with a non HTTPS url") {
				var jsonData = "{ \"1.0\": \"http://my.domain.com/framework.zip\" }".data(using: .utf8)!
				var actualError = BinaryProject.from(jsonData: jsonData).error

				expect(actualError) == .nonHTTPSURL(URL(string: "http://my.domain.com/framework.zip")!)

				jsonData = "{ \"1.0\": \"https://my.domain.com/framework.zip?carthage-alt=http://my.domain.com/release/1.0.0/framework.zip\" }".data(using: .utf8)!
				actualError = BinaryProject.from(jsonData: jsonData).error

				expect(actualError) == .nonHTTPSURL(URL(string: "http://my.domain.com/release/1.0.0/framework.zip")!)
			}

			it("should parse with a file url") {
				let jsonData = "{ \"1.0\": \"file:///my/domain/com/framework.zip\" }".data(using: .utf8)!
				let actualBinaryProject = BinaryProject.from(jsonData: jsonData).value

				let expectedBinaryProject = BinaryProject(versions: [
					PinnedVersion("1.0"): [URL(string: "file:///my/domain/com/framework.zip")!],
				])

				expect(actualBinaryProject) == expectedBinaryProject
			}

			it("should be a valid binary url") {
				let urls = [
					"file:///my/domain/com/framework.zip",
					"https://my.domain.com/framework.zip",
					"https://my.domain.com/release/1.0.0/framework.zip"
				]

				let actualValidity = urls.reduce([], { result, value in result + [BinaryProject.getValidBinaryUrl(value: value)] })

				expect(actualValidity) == [
					.success(.init(string: "file:///my/domain/com/framework.zip")!),
					.success(.init(string: "https://my.domain.com/framework.zip")!),
					.success(.init(string: "https://my.domain.com/release/1.0.0/framework.zip")!)
				]
			}

			it("should not be a valid binary url") {
				let urls = [
					"media",
					"💩",
					"some.value",
					"my.domain.com/release/1.0.0/framework.zip",
					"http://my.domain.com/release/1.0.0/framework.zip"
				]

				let actualValidity = urls.reduce([], { result, value in result + [BinaryProject.getValidBinaryUrl(value: value)] })

				expect(actualValidity) == [
					.failure(BinaryJSONError.nonHTTPSURL(URL(string: "media")!)),
					.failure(BinaryJSONError.invalidURL("💩")),
					.failure(BinaryJSONError.nonHTTPSURL(URL(string: "some.value")!)),
					.failure(BinaryJSONError.nonHTTPSURL(URL(string: "my.domain.com/release/1.0.0/framework.zip")!)),
					.failure(BinaryJSONError.nonHTTPSURL(URL(string: "http://my.domain.com/release/1.0.0/framework.zip")!))
				]
			}
		}
	}
}
