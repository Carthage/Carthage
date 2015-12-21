import Quick
import Nimble

class FrameworkExtensionsSpec: QuickSpec {
    override func spec() {
		describe("NSURL Extensions") {
			it("should figure out if a is a subdirectory of b") {
				guard let subject = NSURL(string: "file:///foo/bar") else { return }

				guard let unrelatedScheme = NSURL(string: "http:///foo/bar/baz") else { return }
				guard let parentDir = NSURL(string: "file:///foo") else { return }
				guard let immediateSub = NSURL(string: "file:///foo/bar/baz") else { return }
				guard let distantSub = NSURL(string: "file:///foo/bar/baz/qux") else { return }
				guard let unrelatedDirectory = NSURL(string: "file:///bar/bar/baz") else { return }

				expect(subject.hasSubdirectory(subject)).to(beTruthy())
				expect(subject.hasSubdirectory(unrelatedScheme)).to(beFalsy())
				expect(subject.hasSubdirectory(parentDir)).to(beFalsy())
				expect(subject.hasSubdirectory(immediateSub)).to(beTruthy())
				expect(subject.hasSubdirectory(distantSub)).to(beTruthy())
				expect(subject.hasSubdirectory(unrelatedDirectory)).to(beFalsy())
			}
		}
    }
}
