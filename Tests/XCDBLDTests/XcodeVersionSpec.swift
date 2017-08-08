import Foundation
import Nimble
import Quick

@testable import XCDBLD

class XcodeVersionSpec: QuickSpec {
	override func spec() {
		describe("\(XcodeVersion.self)") {
			describe("initializer") {
				it("should return nil for empty string") {
					expect(XcodeVersion(xcodebuildOutput: "")).to(beNil())
				}

				it("should return nil for unexpected input") {
					expect(XcodeVersion(xcodebuildOutput: "Xcode 1.0")).to(beNil())
				}

				it("should return a valid value for expected input") {
					let version1 = XcodeVersion(xcodebuildOutput: "Xcode 8.3.2\nBuild version 8E2002")
					expect(version1).notTo(beNil())
					expect(version1?.version) == "8.3.2"
					expect(version1?.buildVersion) == "8E2002"

					let version2 = XcodeVersion(xcodebuildOutput: "Xcode 9.0\nBuild version 9M189t")
					expect(version2).notTo(beNil())
					expect(version2?.version) == "9.0"
					expect(version2?.buildVersion) == "9M189t"
				}
			}
		}
	}
}
