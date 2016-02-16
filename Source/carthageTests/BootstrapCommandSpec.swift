import Quick
import Nimble
import Commandant
import Result

import carthage

class BootstrapCommandSpec: QuickSpec {
	override func spec() {
		var subject: BootstrapCommand!
		var printer: FakePrinter!
		var fileManager: FakeFileManager!

		beforeEach {
			printer = FakePrinter()
			fileManager = FakeFileManager()
			fileManager.fileExistsAtPathStub = { _ in true }
			subject = BootstrapCommand(printer: printer, fileManager: fileManager)
		}

		fdescribe("-run") {
			context("when a Cartfile.resolved file is not found") {
				beforeEach {
					let options = UpdateCommand.Options.evaluate(CommandMode.Arguments(ArgumentParser([]))).value!
					fileManager.fileExistsAtPathStub = { _ in false }
					subject.run(options)
				}

				it("tells the user that no cartfile.resolved was found") {
					expect(printer.printlnCallCount) == 1
					expect(printer.printlnArgsForCall(0) as? String).to(endWith("No Cartfile.resolved found, updating dependencies"))
				}

				pending("updates the dependencies") {

				}
			}

			context("when a Cartfile.resolved file is found") {
				beforeEach {
					let options = UpdateCommand.Options.evaluate(CommandMode.Arguments(ArgumentParser([]))).value!
					fileManager.fileExistsAtPathStub = { _ in true }
					subject.run(options)
				}

				it("does not tell the user anything") {
					expect(printer.printlnCallCount) == 0
				}

				pending("does not update the dependencies") {
					
				}
			}

			context("if the --no-checkout option is specified") {
				beforeEach {
					let options = UpdateCommand.Options.evaluate(CommandMode.Arguments(ArgumentParser(["--no-checkout"]))).value!
					fileManager.fileExistsAtPathStub = { _ in true }
					subject.run(options)
				}

				pending("does not check out the dependencies") {

				}

				pending("does not build the project") {

				}
			}

			context("otherwise") {
				pending("checks out the dependencies") {

				}

				pending("builds the project") {

				}
			}
		}
	}
}
