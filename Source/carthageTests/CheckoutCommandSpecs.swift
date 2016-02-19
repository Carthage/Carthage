import Quick
import Nimble
import Commandant
import Result
import CarthageKit

import carthage

class CheckoutCommandSpec: QuickSpec {
	override func spec() {
		describe("CheckoutCommand.Options") {
			var fileManager: FakeFileManager!

			beforeEach {
				fileManager = FakeFileManager()
				fileManager.currentDirectoryPath = "/Foo"
			}

			let buildCheckoutOptions: ([String] -> CheckoutCommand.Options) = { parameters in
				return CheckoutCommand.Options.evaluate(CommandMode.Arguments(ArgumentParser(parameters)), useBinariesAddendum: "", dependenciesUsage: "dependencies usage", fileManager: fileManager).value!
			}

			context("--use-ssh") {
				it("uses the ssh url for github repositories when specified") {
					expect(buildCheckoutOptions(["--use-ssh"]).project().preferHTTPS) == false
				}

				it("uses the https url for github repositories when not specified") {
					expect(buildCheckoutOptions([]).project().preferHTTPS) == true
				}
			}

			context("--use-submodules") {
				it("checks dependencies out as submodules when specified") {
					expect(buildCheckoutOptions(["--use-submodules"]).project().useSubmodules) == true
				}

				it("disables binaries when set") {
					expect(buildCheckoutOptions(["--use-submodules"]).project().useBinaries) == false
				}

				it("does not use submodules when not specified") {
					expect(buildCheckoutOptions([]).project().useSubmodules) == false
				}
			}

			context("--no-use-binaries") {
				it("rebuilds the world when set") {
					expect(buildCheckoutOptions(["--no-use-binaries"]).project().useBinaries) == false
				}

				it("queries github for release binaries when not set") {
					expect(buildCheckoutOptions([]).project().useBinaries) == true
				}
			}

			context("--project-directory [...]") {
				it("assumes the current directory is the project directory when set") {
					expect(buildCheckoutOptions([]).project().directoryURL) == NSURL(string: "file:///Foo/")
				}

				it("uses whatever we give it as the project directory") {
					expect(buildCheckoutOptions(["--project-directory", "/Bar"]).project().directoryURL) == NSURL(string: "file:///Bar/")
				}
			}
		}

		describe("-run") {
			pending("loads the project, resolves the dependencies and checks them out") {

			}
		}
	}
}
