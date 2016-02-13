import Quick
import Nimble
import CarthageKit
import Commandant
import Cocoa
import Result

import carthage

private class MockPrinter: Printer {
	private func println() {}

	private var objectToPrintln: String?
	private func println(object: Any) {
		if let description = (object as? CustomStringConvertible)?.description {
			objectToPrintln = description
		}
	}

	private var objectToPrint: String?
	private func print(object: Any) {
		if let description = (object as? CustomStringConvertible)?.description {
			objectToPrint = description
		}
	}
}

// Because this by-default synchronous and way easier to understand than ReactiveTask
private func runCommand(command: String, fromDirectory: String = NSProcessInfo.processInfo().environment["SourceDir"] ?? "") -> String {
	let task = NSTask()
	let arguments = command.componentsSeparatedByString(" ")
	task.launchPath = arguments.first!
	task.arguments = Array(arguments[1..<arguments.count])
	task.currentDirectoryPath = fromDirectory

	let pipe = NSPipe()
	task.standardOutput = pipe
	task.standardError = pipe
	task.launch()
	task.waitUntilExit()

	return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: NSUTF8StringEncoding) ?? ""
}

class VersionSpec: QuickSpec {
    override func spec() {
		var subject: VersionCommand!
		var printer: MockPrinter!

		beforeEach {
			printer = MockPrinter()
			subject = VersionCommand(printer: printer)
		}

		it("prints the output of git describe --tags on the carthage directory as the version") {
			let versionString = runCommand("/usr/bin/git describe --tags")

//			subject.run(NoOptions<CarthageError>())
			subject.run(NoOptions<CarthageError>.evaluate(.Usage).value!)

			expect(printer.objectToPrintln) == versionString
		}
    }
}
