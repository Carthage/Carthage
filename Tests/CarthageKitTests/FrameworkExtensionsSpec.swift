import Foundation
import Quick
import Nimble

class FrameworkExtensionsSpec: QuickSpec {
	override func spec() {
		describe("URL Extensions") {
			it("should figure out if a is a subdirectory of b") {
				let subject = URL(string: "file:///foo/bar")!

				let unrelatedScheme = URL(string: "http:///foo/bar/baz")!
				let parentDir = URL(string: "file:///foo")!
				let immediateSub = URL(string: "file:///foo/bar/baz")!
				let distantSub = URL(string: "file:///foo/bar/baz/qux")!
				let unrelatedDirectory = URL(string: "file:///bar/bar/baz")!

				expect(subject.hasSubdirectory(subject)) == true
				expect(subject.hasSubdirectory(unrelatedScheme)) == false
				expect(subject.hasSubdirectory(parentDir)) == false
				expect(subject.hasSubdirectory(immediateSub)) == true
				expect(subject.hasSubdirectory(distantSub)) == true
				expect(subject.hasSubdirectory(unrelatedDirectory)) == false
			}

			context("`hasSubdirectory` with /tmp and /private/tmp") {
				let baseName = "/tmp/CarthageKitTests-URL-hasSubdirectory"
				let parentDirUnderTmp = URL(fileURLWithPath: baseName)
				let childDirUnderPrivateTmp = URL(fileURLWithPath: "/private\(baseName)/foo")

				beforeEach {
					_ = try? FileManager.default
						.createDirectory(at: childDirUnderPrivateTmp, withIntermediateDirectories: true)
				}

				afterEach {
					_ = try? FileManager.default
						.removeItem(at: parentDirUnderTmp)
				}

				it("should resolve the difference between /tmp and /private/tmp") {
					expect(parentDirUnderTmp.hasSubdirectory(childDirUnderPrivateTmp)) == true
				}
			}
		}
	}
}
