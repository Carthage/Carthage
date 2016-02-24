import Quick
import Nimble

class FrameworkExtensionsSpec: QuickSpec {
	override func spec() {
		describe("NSURL Extensions") {
			it("should figure out if a is a subdirectory of b") {
				let subject = NSURL(string: "file:///foo/bar")!

				let unrelatedScheme = NSURL(string: "http:///foo/bar/baz")!
				let parentDir = NSURL(string: "file:///foo")!
				let immediateSub = NSURL(string: "file:///foo/bar/baz")!
				let distantSub = NSURL(string: "file:///foo/bar/baz/qux")!
				let unrelatedDirectory = NSURL(string: "file:///bar/bar/baz")!

				expect(subject.hasSubdirectory(subject)) == true
				expect(subject.hasSubdirectory(unrelatedScheme)) == false
				expect(subject.hasSubdirectory(parentDir)) == false
				expect(subject.hasSubdirectory(immediateSub)) == true
				expect(subject.hasSubdirectory(distantSub)) == true
				expect(subject.hasSubdirectory(unrelatedDirectory)) == false
			}
		}
	}
}
