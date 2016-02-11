import Quick
import Nimble
import CarthageKit
import Commandant

import carthage

private class MockPrinter: Printer {
	private func println() {}

	private var objectToPrint: Any?
	private func println(object: Any) {
		objectToPrint = object
	}

	private func print(object: Any) {
		objectToPrint = object
	}
}

class VersionSpec: QuickSpec {
    override func spec() {
		var subject: VersionCommand!
		var printer: MockPrinter!

		beforeEach {
			printer = MockPrinter()
			subject = VersionCommand(printer: printer)
		}

		it("prints the latest CFBundleShortVersionString from CarthageKit") {
			let versionString = NSBundle(identifier: CarthageKitBundleIdentifier)?.objectForInfoDictionaryKey("CFBundleShortVersionString") as! String

			// expect(subject.run(NoOptions<CarthageError>().error).to(beNil())
			// Waiting for https://github.com/Carthage/Commandant/pull/55 to be merged
			// and for Carthage to update

			expect(printer.objectToPrint as? String) == versionString
		}
    }
}
