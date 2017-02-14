import CarthageKit
import Foundation
import Nimble
import Quick
import Tentacle

class ProjectIdentifierSpec: QuickSpec {
	override func spec() {

		var dependencyType: String!

		sharedExamples("invalid dependency") { (sharedExampleContext: @escaping SharedExampleContext) in

			beforeEach {
				guard let type = sharedExampleContext()["dependencyType"] as? String else {
					fail("no dependency type")
					return
				}

				dependencyType = type
			}

			it("should fail without dependency") {
				let scanner = Scanner(string: dependencyType)

				let error = ProjectIdentifier.from(scanner).error

				let expectedError = ScannableError(message: "expected string after dependency type", currentLine: dependencyType)
				expect(error).to(equal(expectedError))
			}

			it("should fail without closing quote on dependency") {
				let scanner = Scanner(string: "\(dependencyType!) \"dependency")

				let error = ProjectIdentifier.from(scanner).error

				let expectedError = ScannableError(message: "empty or unterminated string after dependency type", currentLine: "\(dependencyType!) \"dependency")
				expect(error).to(equal(expectedError))
			}

			it("should fail with empty dependency") {
				let scanner = Scanner(string: "\(dependencyType!) \" \"")

				let error = ProjectIdentifier.from(scanner).error

				let expectedError = ScannableError(message: "empty or unterminated string after dependency type", currentLine: "\(dependencyType!) \" \"")
				expect(error).to(equal(expectedError))
			}
		}

		describe("name") {
			context ("github") {

				it("should equal the name of a github.com repo") {
					let projectIdentifier = ProjectIdentifier.gitHub(Repository(owner: "owner", name: "name"))

					expect(projectIdentifier.name).to(equal("name"))
				}

				it("should equal the name of an enterprise github repo") {
					let enterpriseRepo = Repository(
						server: .enterprise(url: URL(string: "http://server.com")!),
						owner: "owner",
						name: "name")

					let projectIdentifier = ProjectIdentifier.gitHub(enterpriseRepo)

					expect(projectIdentifier.name).to(equal("name"))
				}
			}

			context("git") {

				it("should be the last component of the URL") {
					let projectIdentifier = ProjectIdentifier.git(GitURL("ssh://server.com/myproject"))

					expect(projectIdentifier.name).to(equal("myproject"))
				}

				it("should not include the trailing git suffix") {
					let projectIdentifier = ProjectIdentifier.git(GitURL("ssh://server.com/myproject.git"))

					expect(projectIdentifier.name).to(equal("myproject"))
				}

				it("should be the entire URL string if there is no last component") {
					let projectIdentifier = ProjectIdentifier.git(GitURL("whatisthisurleven"))

					expect(projectIdentifier.name).to(equal("whatisthisurleven"))
				}

			}

			context("binary") {

				it("should be the last component of the URL") {
					let projectIdentifier = ProjectIdentifier.binary(URL(string: "https://server.com/myproject")!)

					expect(projectIdentifier.name).to(equal("myproject"))
				}

				it("should not include the trailing git suffix") {
					let projectIdentifier = ProjectIdentifier.binary(URL(string: "https://server.com/myproject.json")!)

					expect(projectIdentifier.name).to(equal("myproject"))
				}

			}
		}

		describe("from") {

			context("github") {

				it("should read a github.com dependency") {
					let scanner = Scanner(string: "github \"ReactiveCocoa/ReactiveCocoa\"")

					let projectIdentifier = ProjectIdentifier.from(scanner).value

					let expectedRepo = Repository(owner: "ReactiveCocoa", name: "ReactiveCocoa")
					expect(projectIdentifier).to(equal(ProjectIdentifier.gitHub(expectedRepo)))
				}

				it("should read a github.com dependency with full url") {
					let scanner = Scanner(string: "github \"https://github.com/ReactiveCocoa/ReactiveCocoa\"")

					let projectIdentifier = ProjectIdentifier.from(scanner).value

					let expectedRepo = Repository(owner: "ReactiveCocoa", name: "ReactiveCocoa")
					expect(projectIdentifier).to(equal(ProjectIdentifier.gitHub(expectedRepo)))
				}

				it("should read an enterprise github dependency") {
					let scanner = Scanner(string: "github \"http://mysupercoolinternalwebhost.com/ReactiveCocoa/ReactiveCocoa\"")

					let projectIdentifier = ProjectIdentifier.from(scanner).value

					let expectedRepo = Repository(
						server: .enterprise(url: URL(string: "http://mysupercoolinternalwebhost.com")!),
						owner: "ReactiveCocoa",
						name: "ReactiveCocoa")
					expect(projectIdentifier).to(equal(ProjectIdentifier.gitHub(expectedRepo)))
				}

				it("should fail with invalid github.com dependency") {
					let scanner = Scanner(string: "github \"Whatsthis\"")

					let error = ProjectIdentifier.from(scanner).error

					let expectedError = ScannableError(message: "invalid GitHub repository identifier \"Whatsthis\"")
					expect(error).to(equal(expectedError))
				}

				it("should fail with invalid enterprise github dependency") {
					let scanner = Scanner(string: "github \"http://mysupercoolinternalwebhost.com/ReactiveCocoa\"")

					let error = ProjectIdentifier.from(scanner).error

					let expectedError = ScannableError(message: "invalid GitHub repository identifier \"http://mysupercoolinternalwebhost.com/ReactiveCocoa\"")
					expect(error).to(equal(expectedError))
				}

				itBehavesLike("invalid dependency") { ["dependencyType": "github"] }
			}

			context("git") {

				it("should read a git URL") {
					let scanner = Scanner(string: "git \"mygiturl\"")

					let projectIdentifier = ProjectIdentifier.from(scanner).value

					expect(projectIdentifier).to(equal(ProjectIdentifier.git(GitURL("mygiturl"))))
				}

				itBehavesLike("invalid dependency") { ["dependencyType": "git"] }

			}

			context("binary") {

				it("should read a URL") {
					let scanner = Scanner(string: "binary \"https://mysupercoolinternalwebhost.com/\"")

					let projectIdentifier = ProjectIdentifier.from(scanner).value

					expect(projectIdentifier).to(equal(ProjectIdentifier.binary(URL(string: "https://mysupercoolinternalwebhost.com/")!)))
				}

				it("should fail with non-https URL") {
					let scanner = Scanner(string: "binary \"nope\"")

					let error = ProjectIdentifier.from(scanner).error

					expect(error).to(equal(ScannableError(message: "non-https URL found for dependency type `binary`", currentLine: "binary \"nope\"")))
				}

				it("should fail with invalid URL") {
					let scanner = Scanner(string: "binary \"nop@%@#^@e\"")

					let error = ProjectIdentifier.from(scanner).error

					expect(error).to(equal(ScannableError(message: "invalid URL found for dependency type `binary`", currentLine: "binary \"nop@%@#^@e\"")))
				}

				itBehavesLike("invalid dependency") { ["dependencyType": "binary"] }
			}

		}


	}
}
